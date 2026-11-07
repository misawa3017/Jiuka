import 'package:flutter/material.dart';
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
    final matchingGroups = groupRepo.groups.where((group) => group.id == groupId);
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

    return Scaffold(
      appBar: AppBar(title: Text('${group.name}・成員')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
              title: const Text('球隊成員'),
              subtitle: Text('${group.memberIds.length} 人'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.admin_panel_settings_outlined),
              ),
              title: Text(user.name.isEmpty ? '你' : user.name),
              subtitle: const Text('管理員'),
              trailing: const Chip(
                label: Text('管理員'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '目前球隊只記錄成員身分，尚未取得其他成員的個人暱稱，因此不在這裡顯示臨時或虛構的姓名。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
