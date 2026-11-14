import 'package:cloud_firestore/cloud_firestore.dart';

/// 站內通知，由 Cloud Functions 寫入 users/{uid}/notifications。
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String eventId;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.eventId,
    required this.read,
    this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map, String id) {
    final created = map['createdAt'];
    return AppNotification(
      id: id,
      type: map['type'] is String ? map['type'] as String : '',
      title: map['title'] is String ? map['title'] as String : '',
      body: map['body'] is String ? map['body'] as String : '',
      eventId: map['eventId'] is String ? map['eventId'] as String : '',
      read: map['read'] == true,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

class NotificationRepository {
  final FirebaseFirestore _firestore;

  NotificationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _inbox(String userId) =>
      _firestore.collection('users').doc(userId).collection('notifications');

  /// 最近 50 則通知，由新到舊。
  Stream<List<AppNotification>> watch(String userId) => _inbox(userId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => AppNotification.fromMap(doc.data(), doc.id))
            .toList(),
      );

  /// 未讀數量（最多計到 99，畫面顯示 99+）。
  Stream<int> watchUnreadCount(String userId) => _inbox(userId)
      .where('read', isEqualTo: false)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.size);

  Future<void> markRead(String userId, String notificationId) =>
      _inbox(userId).doc(notificationId).update({'read': true});

  Future<void> markAllRead(String userId, List<AppNotification> items) async {
    final unread = items.where((item) => !item.read).toList();
    for (var start = 0; start < unread.length; start += 500) {
      final batch = _firestore.batch();
      for (final item in unread.skip(start).take(500)) {
        batch.update(_inbox(userId).doc(item.id), {'read': true});
      }
      await batch.commit();
    }
  }
}
