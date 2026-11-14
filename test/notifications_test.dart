import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiuka/features/notifications/notification_repository.dart';
import 'package:jiuka/features/notifications/push_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockStore extends Mock implements FirebaseFirestore {}

void main() {
  test('解析站內通知，缺欄位時有安全預設值', () {
    final created = DateTime(2026, 11, 14, 20, 30);
    final item = AppNotification.fromMap({
      'type': 'promoted',
      'title': '候補遞補成功',
      'body': '你已從候補轉為正取：週三晚間籃球',
      'eventId': 'game',
      'read': false,
      'createdAt': Timestamp.fromDate(created),
    }, 'n1');
    expect(item.type, 'promoted');
    expect(item.eventId, 'game');
    expect(item.read, isFalse);
    expect(item.createdAt, created);

    final broken = AppNotification.fromMap({'read': 'yes'}, 'n2');
    expect(broken.title, '');
    expect(broken.read, isFalse);
    expect(broken.createdAt, isNull);
  });

  test('非網頁或沒有 VAPID 金鑰時推播停用，不會呼叫瀏覽器', () async {
    final push = PushService(firestore: _MockStore());
    expect(push.isSupported, isFalse);
    expect(await push.status('u1'), PushStatus.unavailable);
    expect(await push.enable('u1'), PushStatus.unavailable);
    await push.disable('u1');
  });
}
