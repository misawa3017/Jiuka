import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../groups/repositories/group_repository.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepo = context.watch<AuthRepository>();
    final groupRepo = context.watch<GroupRepository>();

    // If not logged in, show welcome/login prompt (Ideally Router handles redirect)
    if (!authRepo.isAuthenticated) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = authRepo.currentUser!;
    final allGroups = groupRepo.groups;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的球隊'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authRepo.logout();
              if (context.mounted && authRepo.errorMessage != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(authRepo.errorMessage!)));
              }
            },
          ),
        ],
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
          : allGroups.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sports_basketball,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '還沒有參加任何球隊',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  const Text('點擊右下角按鈕建立新的球隊'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allGroups
                  .length, // Show all for demo so we can see created ones easily
              itemBuilder: (context, index) {
                final group = allGroups[index];
                final isMember = group.memberIds.contains(user.id);

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text(group.name[0].toUpperCase()),
                    ),
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text('${group.memberIds.length} 位成員'),
                          ],
                        ),
                      ],
                    ),
                    trailing: isMember
                        ? const Chip(
                            label: Text('已加入'),
                            visualDensity: VisualDensity.compact,
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      context.push('/group/${group.id}');
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-group'),
        icon: const Icon(Icons.add),
        label: const Text('建立球隊'),
      ),
    );
  }
}
