import 'package:flutter/material.dart';

import '../../../components/content_width.dart';
import 'package:provider/provider.dart';

import '../../auth/repositories/auth_repository.dart';
import '../repositories/group_repository.dart';

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

    if (user == null || group.adminId != user.id) {
      return Scaffold(
        appBar: AppBar(title: const Text('球隊成員')),
        body: const Center(child: Text('只有球隊管理員可以查看這個頁面。')),
      );
    }

    // 管理員排第一，其餘依加入順序。
    final members = [
      group.adminId,
      ...group.memberIds.where((id) => id != group.adminId),
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
                SectionCard(
                  title: '球隊成員 ${members.length} 人',
                  icon: Icons.groups_outlined,
                  children: [
                    for (final id in members)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Text(
                            (group.memberNames[id] ?? '').isEmpty
                                ? '?'
                                : group.memberNames[id]!.characters.first,
                          ),
                        ),
                        title: Text(
                          (group.memberNames[id] ?? '').isEmpty
                              ? '成員（尚未同步暱稱）'
                              : group.memberNames[id]!,
                        ),
                        subtitle: id == user.id ? const Text('你') : null,
                        trailing: id == group.adminId
                            ? const Chip(
                                label: Text('管理員'),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
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
