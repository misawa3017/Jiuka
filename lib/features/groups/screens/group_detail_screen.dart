import '../../events/models/event_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth/models/user_model.dart';
import '../../../components/content_width.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/group_model.dart';
import '../repositories/group_repository.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../events/repositories/event_repository.dart';
import '../../../components/ad_banner_widget.dart';
import 'package:intl/intl.dart';

class GroupDetailScreen extends StatelessWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final authRepo = context.watch<AuthRepository>();
    final groupRepo = context.watch<GroupRepository>();

    // Find group safely
    final group = groupRepo.groups.firstWhere(
      (g) => g.id == groupId,
      orElse: () => Group(
        id: '',
        name: 'Error',
        description: 'Group not found',
        adminId: '',
      ),
    );

    if (group.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('發生錯誤')),
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
              : const Text('找不到該球隊'),
        ),
      );
    }

    final currentUser = authRepo.currentUser;
    final userId = currentUser?.id;
    final isMember = group.isMember(userId);
    final canManage = group.canManage(userId);

    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '球隊介紹',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(group.description),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _InfoChip(
                          icon: Icons.people,
                          label: '${group.memberIds.length} 位成員',
                        ),
                        _InfoChip(
                          icon: Icons.person_outline,
                          label: '人數上限: ${group.maxPlayersDefault}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            if (canManage)
              _ManagerTools(group: group, userId: userId!)
            else if (isMember)
              _MemberTools(group: group, userId: userId!)
            else if (currentUser != null)
              _JoinRequestButton(group: group, user: currentUser),

            const SizedBox(height: 24),
            Text('近期活動', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: AdBannerWidget(),
              ),
            ),
            _EventList(groupId: groupId),
          ],
        ),
      ),
    );
  }
}

/// 非隊員：申請加入；送出後顯示「等待隊長審核」並可以撤回。
class _JoinRequestButton extends StatefulWidget {
  final Group group;
  final User user;

  const _JoinRequestButton({required this.group, required this.user});

  @override
  State<_JoinRequestButton> createState() => _JoinRequestButtonState();
}

class _JoinRequestButtonState extends State<_JoinRequestButton> {
  late final Stream<bool> _pending = context
      .read<GroupRepository>()
      .watchMyRequest(widget.group.id, widget.user.id);
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<GroupRepository>();
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<bool>(
      stream: _pending,
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.schedule, color: scheme.tertiary),
              title: const Text('已送出申請，等待隊長審核'),
              subtitle: const Text('審核結果會通知你'),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => repository.withdrawRequest(
                          widget.group.id,
                          widget.user.id,
                        ),
                        '撤回失敗，請稍後重試。',
                      ),
                child: const Text('撤回'),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _busy || !snapshot.hasData
                  ? null
                  : () => _run(
                      () => repository.requestToJoin(
                        widget.group.id,
                        widget.user.id,
                        widget.user.name,
                      ),
                      '申請失敗，請稍後重試。',
                    ),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('申請加入'),
            ),
            const SizedBox(height: 6),
            Text(
              '送出後由隊長審核，結果會通知你',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

/// 隊長或幹部：開球隊場次、管理成員（隊長會看到待審核數量）。
class _ManagerTools extends StatelessWidget {
  final Group group;
  final String userId;
  const _ManagerTools({required this.group, required this.userId});

  @override
  Widget build(BuildContext context) {
    final captain = group.isCaptain(userId);
    return SectionCard(
      title: captain ? '隊長功能' : '幹部功能',
      icon: Icons.admin_panel_settings_outlined,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _copyInvite(context, group),
          icon: const Icon(Icons.link),
          label: const Text('複製邀請連結'),
        ),
        if (captain)
          StreamBuilder<List<JoinRequest>>(
            stream: context.read<GroupRepository>().watchJoinRequests(group.id),
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text('$count 筆入隊申請等待審核'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/group/${group.id}/members'),
                ),
              );
            },
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/group/${group.id}/create-event'),
                icon: const Icon(Icons.add),
                label: const Text('開球隊場次'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/group/${group.id}/members'),
                icon: const Icon(Icons.groups_outlined),
                label: Text(captain ? '成員管理' : '查看成員'),
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/group/${group.id}/venues'),
          icon: const Icon(Icons.stadium_outlined),
          label: const Text('常用場地'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/group/${group.id}/seasons'),
          icon: const Icon(Icons.event_repeat),
          label: const Text('季租'),
        ),
        if (!captain) _LeaveButton(group: group, userId: userId),
      ],
    );
  }
}

/// 複製球隊連結與加入說明，方便貼到 LINE 群組。
Future<void> _copyInvite(BuildContext context, Group group) async {
  final link = Uri.base.replace(
    path: '/group/${group.id}',
    query: '',
    fragment: '',
  );
  final text =
      '邀請你加入揪咖球隊「${group.name}」\n'
      '$link\n'
      '打開後用 Google 登入，按「申請加入」，隊長核准後就是隊員了。';
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已複製邀請連結，可以貼到 LINE 群組了。')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('無法複製，請手動分享這個網址：$link')));
    }
  }
}

/// 一般隊員：查看成員、退出球隊。
class _MemberTools extends StatelessWidget {
  final Group group;
  final String userId;
  const _MemberTools({required this.group, required this.userId});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '你是隊員',
      icon: Icons.verified_user_outlined,
      children: [
        OutlinedButton.icon(
          onPressed: () => context.push('/group/${group.id}/members'),
          icon: const Icon(Icons.groups_outlined),
          label: const Text('查看成員'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/group/${group.id}/venues'),
          icon: const Icon(Icons.stadium_outlined),
          label: const Text('常用場地'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/group/${group.id}/seasons'),
          icon: const Icon(Icons.event_repeat),
          label: const Text('季租'),
        ),
        _LeaveButton(group: group, userId: userId),
      ],
    );
  }
}

class _LeaveButton extends StatelessWidget {
  final Group group;
  final String userId;
  const _LeaveButton({required this.group, required this.userId});

  Future<void> _leave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('退出「${group.name}」？'),
        content: const Text('退出後要重新申請、由隊長核准才能再加入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('退出球隊'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<GroupRepository>().removeMember(group.id, userId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('退出失敗，請稍後重試。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _leave(context),
    icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
    label: Text(
      '退出球隊',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _EventList extends StatefulWidget {
  final String groupId;
  const _EventList({required this.groupId});

  @override
  State<_EventList> createState() => _EventListState();
}

class _EventListState extends State<_EventList> {
  int _retryKey = 0;

  @override
  Widget build(BuildContext context) {
    final eventRepo = context.read<EventRepository>();

    return StreamBuilder<List<Event>>(
      key: ValueKey(_retryKey),
      stream: eventRepo.getEventsStream(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('活動載入失敗。'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _retryKey++),
                  child: const Text('重新載入'),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text('暫無活動', style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final isFull = event.isFull;
            final amount = event.estimatedCostPerPerson();

            return Card(
              child: ListTile(
                title: Text(
                  DateFormat('MM/dd (E) HH:mm').format(event.startTime),
                ),
                subtitle: Text(
                  event.costMode == CostMode.perPerson
                      ? '${event.venue} • 每人 ${event.cost} 元'
                      : '${event.venue} • 每人預估 ${amount ?? '待估算'} 元',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${event.occupiedCount}/${event.maxPlayers}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isFull ? Colors.red : Colors.green,
                      ),
                    ),
                    if (event.waitlistCount > 0)
                      Text(
                        '候補: ${event.waitlistCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  context.push('/event/${event.id}');
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
