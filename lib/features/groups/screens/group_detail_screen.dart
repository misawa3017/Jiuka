import '../../events/models/event_model.dart';
import 'package:flutter/material.dart';
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
    final isMember = group.memberIds.contains(currentUser?.id);
    final isAdmin = group.adminId == currentUser?.id;

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
            if (isAdmin) ...[
              _AdminTools(groupId: group.id),
            ] else if (!isMember && currentUser != null) ...[
              _JoinGroupButton(groupId: group.id, userId: currentUser.id),
            ],

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

class _JoinGroupButton extends StatefulWidget {
  final String groupId;
  final String userId;

  const _JoinGroupButton({required this.groupId, required this.userId});

  @override
  State<_JoinGroupButton> createState() => _JoinGroupButtonState();
}

class _JoinGroupButtonState extends State<_JoinGroupButton> {
  bool _isJoining = false;

  Future<void> _join() async {
    if (_isJoining) return;
    setState(() => _isJoining = true);
    try {
      await context.read<GroupRepository>().joinGroup(
        widget.groupId,
        widget.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('成功加入球隊！')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加入球隊失敗，請稍後重試。')));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: _isJoining ? null : _join,
    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
    child: _isJoining
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Text('加入球隊', style: TextStyle(fontSize: 18)),
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

class _AdminTools extends StatelessWidget {
  final String groupId;
  const _AdminTools({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '管理員功能',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push('/group/$groupId/create-event');
                },
                icon: const Icon(Icons.calendar_today),
                label: const Text('建立活動'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push('/group/$groupId/members');
                },
                icon: const Icon(Icons.manage_accounts),
                label: const Text('查看成員'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
