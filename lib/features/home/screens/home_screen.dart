import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../components/content_width.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../groups/models/group_model.dart';
import '../../groups/repositories/group_repository.dart';

/// 球隊總覽：上面是自己加入的球隊（標示角色），下面是其他球隊（點進去可申請加入）。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepo = context.watch<AuthRepository>();
    final groupRepo = context.watch<GroupRepository>();
    final user = authRepo.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final mine = groupRepo.groups.where((g) => g.isMember(user.id)).toList();
    final others = groupRepo.groups.where((g) => !g.isMember(user.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('球隊')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-group'),
        icon: const Icon(Icons.add),
        label: const Text('建立球隊'),
      ),
      body: groupRepo.isLoading
          ? const Center(child: CircularProgressIndicator())
          : groupRepo.error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('球隊資料載入失敗，請檢查網路後重試。'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: groupRepo.retry,
                    child: const Text('重新載入'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('我的球隊', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (mine.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.groups_outlined,
                                  size: 40,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(height: 8),
                                const Text('你還沒有加入球隊'),
                                const SizedBox(height: 4),
                                Text(
                                  '建立自己的球隊，或從下面的球隊申請加入',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () =>
                                      context.push('/create-group'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('建立球隊'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        for (final group in mine) ...[
                          _GroupCard(group: group, userId: user.id),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 20),
                      Text('其他球隊', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '點進球隊頁可以申請加入，由隊長審核',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (others.isEmpty)
                        Text(
                          '目前沒有其他球隊',
                          style: TextStyle(color: theme.colorScheme.outline),
                        )
                      else
                        for (final group in others) ...[
                          _GroupCard(group: group, userId: user.id),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Group group;
  final String userId;
  const _GroupCard({required this.group, required this.userId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final role = group.isCaptain(userId)
        ? '隊長'
        : group.isOfficer(userId)
        ? '幹部'
        : group.isMember(userId)
        ? '隊員'
        : null;
    final captainName = group.memberNames[group.adminId] ?? '';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(group.name.characters.first),
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            '${group.memberIds.length} 位成員'
                '${captainName.isEmpty ? '' : ' · 隊長 $captainName'}',
            if (group.description.isNotEmpty) group.description,
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: group.description.isNotEmpty,
        trailing: role == null
            ? const Icon(Icons.chevron_right)
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
        onTap: () => context.push('/group/${group.id}'),
      ),
    );
  }
}
