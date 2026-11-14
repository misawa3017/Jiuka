import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/repositories/auth_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';
import '../widgets/event_card.dart';
import '../../../components/content_width.dart';

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthRepository>().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的場次'),
          actions: [
            IconButton(
              tooltip: '發布場次',
              onPressed: () => context.push('/create-event'),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '我主揪的'),
              Tab(text: '我報名的'),
              Tab(text: '我候補的'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final list in UserEventList.values)
              _UserEventListView(
                key: ValueKey('$_refreshKey-$list'),
                userId: user.id,
                list: list,
                onRetry: () => setState(() => _refreshKey++),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserEventListView extends StatelessWidget {
  final String userId;
  final UserEventList list;
  final VoidCallback onRetry;

  const _UserEventListView({
    super.key,
    required this.userId,
    required this.list,
    required this.onRetry,
  });

  String get _emptyMessage => switch (list) {
    UserEventList.organized => '你還沒有發布場次',
    UserEventList.attending => '你還沒有報名場次',
    UserEventList.waitlisted => '你目前沒有候補場次',
  };

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventRepository>();
    return StreamBuilder<List<Event>>(
      stream: repository.getUserEventsStream(userId, list),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('載入場次失敗，請稍後重試。'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: onRetry, child: const Text('重新載入')),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(_emptyMessage),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('去找打球場次'),
                ),
              ],
            ),
          );
        }

        final role = switch (list) {
          UserEventList.organized => '主揪',
          UserEventList.attending => '正取',
          UserEventList.waitlisted => '候補',
        };
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => ContentWidth(
            child: EventCard(
              event: events[index],
              badge: role,
              onTap: () => context.push('/event/${events[index].id}'),
            ),
          ),
        );
      },
    );
  }
}
