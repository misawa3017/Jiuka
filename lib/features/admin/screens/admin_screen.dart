import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../components/content_width.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../events/models/event_model.dart';
import '../../events/repositories/event_repository.dart';
import '../../events/widgets/event_card.dart';

enum _AdminFilter { all, upcoming, past, cancelled }

/// 系統管理者後台：列出所有場次（含已取消、已結束）與基本統計。
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  _AdminFilter _filter = _AdminFilter.all;
  static const _pageSize = 50;
  int _limit = _pageSize;
  // StreamBuilder 換 stream 時會保留上一批資料，所以載入更多時清單不會閃。
  late Stream<List<Event>> _events = _load();

  Stream<List<Event>> _load() =>
      context.read<EventRepository>().getAllEventsStream(limit: _limit);

  void _loadMore() => setState(() {
    _limit += _pageSize;
    _events = _load();
  });

  bool _matches(Event event, DateTime now) => switch (_filter) {
    _AdminFilter.all => true,
    _AdminFilter.upcoming =>
      event.isAcceptingSignups && event.startTime.isAfter(now),
    _AdminFilter.past =>
      event.status != EventStatus.cancelled && !event.startTime.isAfter(now),
    _AdminFilter.cancelled => event.status == EventStatus.cancelled,
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    if (!auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理後台')),
        body: const Center(child: Text('只有系統管理者可以進入這個頁面。')),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('管理後台')),
      body: StreamBuilder<List<Event>>(
        stream: _events,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('載入場次失敗，請稍後重試。'));
          }
          final events = snapshot.data;
          if (events == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now();
          final upcoming = events.where(
            (e) => e.isAcceptingSignups && e.startTime.isAfter(now),
          );
          final cancelled = events.where(
            (e) => e.status == EventStatus.cancelled,
          );
          final signups = events.fold<int>(
            0,
            (sum, e) => sum + e.attendeeCount + e.waitlistCount,
          );
          final shown = events.where((e) => _matches(e, now)).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Stat(label: '全部場次', value: events.length),
                        _Stat(label: '即將開始', value: upcoming.length),
                        _Stat(label: '已取消', value: cancelled.length),
                        _Stat(label: '報名與候補人次', value: signups),
                      ],
                    ),
                    if (events.length >= _limit)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '目前載入最近 ${events.length} 場，統計只計算已載入的場次。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (filter, label) in const [
                          (_AdminFilter.all, '全部'),
                          (_AdminFilter.upcoming, '即將開始'),
                          (_AdminFilter.past, '已結束'),
                          (_AdminFilter.cancelled, '已取消'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('沒有符合的場次')),
                      ),
                    for (final event in shown) ...[
                      EventCard(
                        event: event,
                        badge: event.startTime.isAfter(now) ? null : '已結束',
                        onTap: () => context.push('/event/${event.id}'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (events.length >= _limit)
                      Center(
                        child: OutlinedButton.icon(
                          onPressed:
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? null
                              : _loadMore,
                          icon: const Icon(Icons.expand_more),
                          label: const Text('載入更多'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$value',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
