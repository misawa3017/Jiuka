import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../components/content_width.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/group_model.dart';
import '../repositories/group_repository.dart';

/// 球隊成員：隊員可查看；隊長可審核入隊申請、任免幹部、轉移隊長、移除成員。
class MemberManagementScreen extends StatelessWidget {
  final String groupId;

  const MemberManagementScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final groupRepo = context.watch<GroupRepository>();
    final user = context.watch<AuthRepository>().currentUser;
    final matchingGroups = groupRepo.groups.where(
      (group) => group.id == groupId,
    );
    final group = matchingGroups.isEmpty ? null : matchingGroups.first;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('球隊成員')),
        body: Center(
          child: groupRepo.isLoading
              ? const CircularProgressIndicator()
              : groupRepo.error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('球隊資料載入失敗。'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: groupRepo.retry,
                      child: const Text('重新載入'),
                    ),
                  ],
                )
              : const Text('找不到這個球隊。'),
        ),
      );
    }

    if (user == null || !group.isMember(user.id)) {
      return Scaffold(
        appBar: AppBar(title: const Text('球隊成員')),
        body: const Center(child: Text('只有球隊成員可以查看這個頁面。')),
      );
    }

    final captain = group.isCaptain(user.id);
    // 隊長排第一，接著幹部，其餘依加入順序。
    final members = [
      group.adminId,
      ...group.memberIds.where(group.isOfficer),
      ...group.memberIds.where(
        (id) => id != group.adminId && !group.isOfficer(id),
      ),
    ];
    final missing = members
        .where((id) => (group.memberNames[id] ?? '').isEmpty)
        .length;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('${group.name}・成員')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (captain) ...[
                  _JoinRequests(group: group),
                  const SizedBox(height: 12),
                ],
                SectionCard(
                  title: '隊員 ${members.length} 人',
                  icon: Icons.groups_outlined,
                  children: [
                    for (final id in members)
                      _MemberTile(
                        group: group,
                        memberId: id,
                        isMe: id == user.id,
                        canManage: captain && id != user.id,
                      ),
                  ],
                ),
                if (missing > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '有 $missing 位成員是在暱稱功能上線前加入的，他們下次登入後就會顯示暱稱。',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 隊長看到的待審核入隊申請。
class _JoinRequests extends StatefulWidget {
  final Group group;
  const _JoinRequests({required this.group});

  @override
  State<_JoinRequests> createState() => _JoinRequestsState();
}

class _JoinRequestsState extends State<_JoinRequests> {
  late final Stream<List<JoinRequest>> _requests = context
      .read<GroupRepository>()
      .watchJoinRequests(widget.group.id);
  final _busy = <String>{};

  Future<void> _review(JoinRequest request, bool approve) async {
    setState(() => _busy.add(request.userId));
    try {
      await context.read<GroupRepository>().reviewJoinRequest(
        widget.group.id,
        request.userId,
        approve: approve,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('審核失敗，請稍後重試。')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(request.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<JoinRequest>>(
      stream: _requests,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <JoinRequest>[];
        if (requests.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: '入隊申請 ${requests.length}',
          icon: Icons.person_add_alt,
          children: [
            for (final request in requests)
              Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      request.displayName.isEmpty
                          ? '?'
                          : request.displayName.characters.first,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.displayName.isEmpty
                              ? '球友'
                              : request.displayName,
                        ),
                        if (request.createdAt != null)
                          Text(
                            '${DateFormat('MM/dd').format(request.createdAt!)} 申請',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _busy.contains(request.userId)
                        ? null
                        : () => _review(request, false),
                    child: const Text('拒絕'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _busy.contains(request.userId)
                        ? null
                        : () => _review(request, true),
                    child: const Text('核准'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

enum _MemberAction { officer, unofficer, transfer, remove }

class _MemberTile extends StatelessWidget {
  final Group group;
  final String memberId;
  final bool isMe;
  final bool canManage;

  const _MemberTile({
    required this.group,
    required this.memberId,
    required this.isMe,
    required this.canManage,
  });

  String get _name {
    final name = group.memberNames[memberId] ?? '';
    return name.isEmpty ? '成員（尚未同步暱稱）' : name;
  }

  Future<void> _act(BuildContext context, _MemberAction action) async {
    final repository = context.read<GroupRepository>();
    final (title, body, confirm) = switch (action) {
      _MemberAction.transfer => (
        '把隊長轉移給 $_name？',
        '轉移後你會變成一般隊員，由新隊長管理成員與幹部。',
        '轉移隊長',
      ),
      _MemberAction.remove => (
        '把 $_name 移出球隊？',
        '對方之後要重新申請、由隊長核准才能再加入。',
        '移出球隊',
      ),
      _ => ('', '', ''),
    };
    if (title.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('返回'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await switch (action) {
        _MemberAction.officer => repository.setOfficer(
          group.id,
          memberId,
          true,
        ),
        _MemberAction.unofficer => repository.setOfficer(
          group.id,
          memberId,
          false,
        ),
        _MemberAction.transfer => repository.transferCaptain(
          group.id,
          memberId,
        ),
        _MemberAction.remove => repository.removeMember(group.id, memberId),
      };
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失敗，請稍後重試。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final officer = group.isOfficer(memberId);
    final (roleLabel, roleColor) = group.isCaptain(memberId)
        ? ('隊長', scheme.primary)
        : officer
        ? ('幹部', scheme.secondary)
        : (null, scheme.primary);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(
          (group.memberNames[memberId] ?? '').isEmpty
              ? '?'
              : group.memberNames[memberId]!.characters.first,
        ),
      ),
      title: Text(_name),
      subtitle: isMe ? const Text('你') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (roleLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  color: roleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          if (canManage)
            PopupMenuButton<_MemberAction>(
              tooltip: '$_name 的選項',
              onSelected: (action) => _act(context, action),
              itemBuilder: (_) => [
                officer
                    ? const PopupMenuItem(
                        value: _MemberAction.unofficer,
                        child: Text('取消幹部'),
                      )
                    : const PopupMenuItem(
                        value: _MemberAction.officer,
                        child: Text('設為幹部'),
                      ),
                PopupMenuItem(
                  value: _MemberAction.transfer,
                  child: Text('轉移隊長給 $_name'),
                ),
                PopupMenuItem(
                  value: _MemberAction.remove,
                  child: Text('移出球隊', style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
