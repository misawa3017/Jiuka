import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../components/ad_banner_widget.dart';
import '../../auth/repositories/auth_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  int _retryKey = 0;

  void _retry() => setState(() => _retryKey++);

  Future<void> _share(BuildContext context, Event event) async {
    final link = Uri.base.replace(
      path: '/event/${event.id}',
      query: '',
      fragment: '',
    );
    try {
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('場次連結已複製。')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法複製連結，請檢查瀏覽器剪貼簿權限。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventRepository>();
    final auth = context.watch<AuthRepository>();
    final userId = auth.currentUser?.id;
    return StreamBuilder<Event?>(
      key: ValueKey('event-$_retryKey'),
      stream: repository.getEventStream(widget.eventId),
      builder: (context, eventSnapshot) {
        if (eventSnapshot.hasError) {
          return _messagePage('載入場次失敗。', onRetry: _retry);
        }
        if (eventSnapshot.connectionState == ConnectionState.waiting) {
          return _loadingPage();
        }
        final event = eventSnapshot.data;
        if (event == null) return _messagePage('找不到場次');
        if (userId == null) {
          return _EventDetails(
            event: event,
            userId: null,
            participant: null,
            repository: repository,
            onShare: () => _share(context, event),
            onRetry: _retry,
          );
        }
        return StreamBuilder<EventParticipant?>(
          key: ValueKey('participation-$_retryKey'),
          stream: repository.getParticipationStream(widget.eventId, userId),
          builder: (context, participantSnapshot) {
            if (participantSnapshot.hasError) {
              return _messagePage('載入報名狀態失敗。', onRetry: _retry);
            }
            if (participantSnapshot.connectionState ==
                ConnectionState.waiting) {
              return _loadingPage();
            }
            return _EventDetails(
              event: event,
              userId: userId,
              participant: participantSnapshot.data,
              repository: repository,
              onShare: () => _share(context, event),
              onRetry: _retry,
            );
          },
        );
      },
    );
  }

  Scaffold _loadingPage() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  Scaffold _messagePage(String message, {VoidCallback? onRetry}) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('重新載入')),
          ],
        ],
      ),
    ),
  );
}

class _EventDetails extends StatelessWidget {
  final Event event;
  final String? userId;
  final EventParticipant? participant;
  final EventRepository repository;
  final VoidCallback onShare;
  final VoidCallback onRetry;

  const _EventDetails({
    required this.event,
    required this.userId,
    required this.participant,
    required this.repository,
    required this.onShare,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isAttending =
        participant?.status == EventParticipationStatus.attending;
    final isWaitlisted =
        participant?.status == EventParticipationStatus.waitlisted;
    final organizerAlreadyPlaying =
        userId != null && event.organizerPlaying && event.organizerId == userId;
    final canJoin = event.canAcceptParticipants(DateTime.now());
    final joining =
        canJoin &&
        !event.isFull &&
        !isAttending &&
        !isWaitlisted &&
        !organizerAlreadyPlaying;
    final estimated = event.estimatedCostPerPerson(joining: joining);
    final costText = event.costMode == CostMode.perPerson
        ? '每人固定 ${event.cost} 元'
        : estimated == null
        ? '整場場租 ${event.cost} 元，待有人報名後估算'
        : '整場場租 ${event.cost} 元；每人預估 $estimated 元';
    final sportName = switch (event.sport) {
      SportType.basketball => '籃球',
      SportType.badminton => '羽毛球',
      null => '球類',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('$sportName場次'),
        actions: [
          if (kIsWeb)
            IconButton(
              tooltip: '複製場次連結',
              icon: const Icon(Icons.share),
              onPressed: onShare,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$sportName · ${DateFormat('yyyy/MM/dd (EEE) HH:mm').format(event.startTime)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('至 ${DateFormat('HH:mm').format(event.endTime)}'),
          Text('${event.district} · ${event.venue}'),
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(event.description),
          ],
          const SizedBox(height: 20),
          Text(costText, style: Theme.of(context).textTheme.titleMedium),
          if (event.costMode == CostMode.totalVenue)
            const Text('預估金額依目前確定人數計算，最終金額可能隨報名或取消變動。'),
          const SizedBox(height: 12),
          Text(
            '已有人數 ${event.occupiedCount} / ${event.maxPlayers} · 尚缺 ${event.spotsLeft} 人',
          ),
          if (event.existingPlayers > 0)
            Text(
              '其中 ${event.existingPlayers} 人由主揪事先安排'
              '${event.organizerPlaying ? '（含主揪）' : ''}',
            ),
          if (event.waitlistCount > 0) Text('目前候補 ${event.waitlistCount} 人'),
          if (event.status != EventStatus.open || !canJoin)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('此場次已不開放報名'),
            ),
          const SizedBox(height: 24),
          if (canJoin)
            if (userId == null)
              FilledButton(
                onPressed: () => context.push(
                  '/login?from=${Uri.encodeComponent('/event/${event.id}')}',
                ),
                child: const Text('使用 Google 登入後報名'),
              )
            else if (organizerAlreadyPlaying)
              const Center(child: Text('你已以主揪身分計入名額'))
            else if (isAttending || isWaitlisted)
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(isWaitlisted ? '取消候補？' : '取消報名？'),
                      content: const Text('取消後名額與預估費用可能變動。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('返回'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('確認取消'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  try {
                    await repository.leaveEvent(event.id, userId!);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('取消失敗，請稍後重試。')),
                      );
                    }
                  }
                },
                child: Text(isWaitlisted ? '取消候補' : '取消報名'),
              )
            else
              FilledButton(
                onPressed: () async {
                  try {
                    await repository.joinEvent(event.id, userId!);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('報名失敗，請稍後重試。')),
                      );
                    }
                  }
                },
                child: Text(event.isFull ? '加入候補' : '我要報名'),
              ),
          const SizedBox(height: 24),
          if (userId == event.organizerId) ...[
            Text('正取與候補名單', style: Theme.of(context).textTheme.titleMedium),
            _OrganizerRoster(
              stream: repository.getParticipantsStream(event.id),
              onRetry: onRetry,
            ),
          ],
          if (kIsWeb) ...[const SizedBox(height: 24), const AdBannerWidget()],
        ],
      ),
    );
  }
}

class _OrganizerRoster extends StatelessWidget {
  final Stream<List<EventParticipant>> stream;
  final VoidCallback onRetry;

  const _OrganizerRoster({required this.stream, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventParticipant>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('名單載入失敗。'),
              OutlinedButton(onPressed: onRetry, child: const Text('重新載入名單')),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          );
        }
        final attendees = snapshot.data!
            .where((p) => p.status == EventParticipationStatus.attending)
            .toList();
        final waitlist = snapshot.data!
            .where((p) => p.status == EventParticipationStatus.waitlisted)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('正取球友'),
            _Roster(users: attendees),
            const SizedBox(height: 8),
            const Text('候補球友'),
            _Roster(users: waitlist),
          ],
        );
      },
    );
  }
}

class _Roster extends StatelessWidget {
  final List<EventParticipant> users;
  const _Roster({required this.users});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const Text('目前沒有球友');
    return Column(
      children: [
        for (var index = 0; index < users.length; index++)
          ListTile(
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text('球友 ${index + 1}'),
          ),
      ],
    );
  }
}
