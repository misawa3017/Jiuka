import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/repositories/auth_repository.dart';
import '../models/event_model.dart';
import '../repositories/event_repository.dart';
import 'create_event_screen.dart';

/// 載入場次後交給共用表單編輯；只有主揪、且場次仍開放時可以進入。
class EditEventScreen extends StatefulWidget {
  final String eventId;
  const EditEventScreen({super.key, required this.eventId});

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  late final Future<Event?> _event = context
      .read<EventRepository>()
      .getEventStream(widget.eventId)
      .first;

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthRepository>().currentUser?.id;
    return FutureBuilder<Event?>(
      future: _event,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _message('載入場次失敗，請稍後重試。');
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final event = snapshot.data;
        if (event == null) return _message('找不到場次');
        if (event.organizerId != userId) return _message('只有主揪可以編輯這個場次。');
        if (!event.canAcceptParticipants(DateTime.now())) {
          return _message('場次已開始或已取消，不能再編輯。');
        }
        return CreateEventScreen(groupId: event.groupId, initialEvent: event);
      },
    );
  }

  Widget _message(String text) => Scaffold(
    appBar: AppBar(title: const Text('編輯場次')),
    body: Center(child: Text(text)),
  );
}
