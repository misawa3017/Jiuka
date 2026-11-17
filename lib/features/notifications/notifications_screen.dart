import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../components/content_width.dart';
import '../auth/repositories/auth_repository.dart';
import 'notification_repository.dart';
import 'push_service.dart';

IconData _iconFor(String type) => switch (type) {
  'promoted' => Icons.upgrade,
  'cancelled' => Icons.event_busy,
  'updated' => Icons.update,
  'removed' => Icons.person_remove_outlined,
  'costConfirmed' => Icons.payments_outlined,
  'joinRequest' => Icons.person_add_alt,
  'joinApproved' => Icons.group_add_outlined,
  'joinRejected' => Icons.group_off_outlined,
  _ => Icons.notifications_outlined,
};

/// 首頁右上角的鈴鐺，顯示未讀數量。
class NotificationBell extends StatelessWidget {
  final String userId;
  const NotificationBell({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: context.read<NotificationRepository>().watchUnreadCount(userId),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return IconButton(
          tooltip: '通知',
          onPressed: () => context.push('/notifications'),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Stream<List<AppNotification>>? _stream;
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<AuthRepository>().currentUser?.id;
    if (userId != null && userId != _userId) {
      _userId = userId;
      _stream = context.read<NotificationRepository>().watch(userId);
    }
  }

  Future<void> _open(AppNotification item) async {
    final userId = _userId;
    if (userId == null) return;
    if (!item.read) {
      // 標成已讀失敗不影響跳轉。
      context
          .read<NotificationRepository>()
          .markRead(userId, item.id)
          .catchError((_) {});
    }
    if (item.eventId.isNotEmpty) {
      context.push('/event/${item.eventId}');
    } else if (item.groupId.isNotEmpty) {
      context.push('/group/${item.groupId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _userId;
    final stream = _stream;
    if (userId == null || stream == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    return StreamBuilder<List<AppNotification>>(
      stream: stream,
      builder: (context, snapshot) {
        final items = snapshot.data;
        final hasUnread = items?.any((item) => !item.read) ?? false;
        return Scaffold(
          appBar: AppBar(
            title: const Text('通知'),
            actions: [
              if (hasUnread)
                TextButton(
                  onPressed: () => context
                      .read<NotificationRepository>()
                      .markAllRead(userId, items!),
                  child: const Text('全部標為已讀'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PushCard(userId: userId),
                    const SizedBox(height: 16),
                    if (snapshot.hasError)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('載入通知失敗，請稍後重試。')),
                      )
                    else if (items == null)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 48,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            const Text('目前沒有通知'),
                          ],
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                leading: Icon(
                                  _iconFor(items[i].type),
                                  color: items[i].read
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.primary,
                                ),
                                title: Text(
                                  items[i].title,
                                  style: TextStyle(
                                    fontWeight: items[i].read
                                        ? FontWeight.normal
                                        : FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    items[i].body,
                                    if (items[i].createdAt != null)
                                      DateFormat(
                                        'MM/dd HH:mm',
                                      ).format(items[i].createdAt!),
                                  ].join('\n'),
                                ),
                                isThreeLine: items[i].createdAt != null,
                                trailing: items[i].read
                                    ? null
                                    : Icon(
                                        Icons.circle,
                                        size: 10,
                                        color: theme.colorScheme.primary,
                                      ),
                                onTap: () => _open(items[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 開啟／查看這台裝置的瀏覽器推播狀態。
class _PushCard extends StatefulWidget {
  final String userId;
  const _PushCard({required this.userId});

  @override
  State<_PushCard> createState() => _PushCardState();
}

class _PushCardState extends State<_PushCard> {
  PushStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<PushService>().status(widget.userId).then((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final status = await context.read<PushService>().enable(widget.userId);
      if (mounted) setState(() => _status = status);
    } catch (error) {
      // 顯示實際原因，方便回報與排查。
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('開啟推播失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || status == PushStatus.unavailable) {
      return const SizedBox.shrink();
    }
    final (icon, text) = switch (status) {
      PushStatus.on => (Icons.notifications_active, '這台裝置已開啟推播通知'),
      PushStatus.blocked => (
        Icons.notifications_off_outlined,
        '瀏覽器已封鎖通知。請在網址列左側的網站設定中允許通知，再重新整理。',
      ),
      PushStatus.needsInstall => (
        Icons.add_to_home_screen,
        'iPhone 要先把揪咖加入主畫面才能收推播：點 Safari 下方的分享按鈕 →「加入主畫面」，'
            '再從主畫面的揪咖圖示打開，回到這頁按「開啟」。',
      ),
      PushStatus.unsupported => (
        Icons.notifications_off_outlined,
        '這個瀏覽器不支援推播，通知仍會顯示在這一頁。',
      ),
      _ => (Icons.notifications_outlined, '開啟推播，網站沒開著也能收到遞補、異動等通知'),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(text),
        trailing: status == PushStatus.off
            ? FilledButton(
                onPressed: _busy ? null : _enable,
                child: Text(_busy ? '處理中…' : '開啟'),
              )
            : null,
      ),
    );
  }
}
