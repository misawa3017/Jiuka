const { initializeApp } = require('firebase-admin/app');
const {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { setGlobalOptions, logger } = require('firebase-functions/v2');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const {
  planEventUpdate,
  isPastCancelDeadline,
  pickPromotions,
  partySize,
  EventUpdateError,
} = require('./event_update');
const {
  participantChangeNotice,
  eventChangeNotice,
  removedNotice,
} = require('./notifications');

initializeApp();
setGlobalOptions({ region: 'asia-east1', maxInstances: 10 });

const db = getFirestore();

/** 只接受 Google 登入的呼叫者，回傳其 UID。 */
function requireGoogleUser(request, message) {
  const uid = request.auth?.uid;
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider !== 'google.com') {
    throw new HttpsError('unauthenticated', message);
  }
  return uid;
}

/** 檢查文件 ID 格式，避免路徑注入。 */
function requireId(value, message) {
  if (typeof value !== 'string' || !value || value.includes('/')) {
    throw new HttpsError('invalid-argument', message);
  }
  return value;
}

/** 系統管理者名單存在 admins/{uid}，只能由 Firebase Console 或 Admin SDK 寫入。 */
const adminRef = (uid) => db.collection('admins').doc(uid);

/**
 * 發通知：寫入站內通知 users/{uid}/notifications，並推播到該使用者已開啟推播的瀏覽器。
 * 推播失敗不影響站內通知；失效的推播 token 會被清除。
 */
async function notify(userIds, notice, eventId) {
  const recipients = [...new Set(userIds)].filter(Boolean);
  if (recipients.length === 0) return;
  const { type, title, body } = notice;

  for (let start = 0; start < recipients.length; start += 400) {
    const batch = db.batch();
    for (const uid of recipients.slice(start, start + 400)) {
      batch.set(db.collection('users').doc(uid).collection('notifications').doc(), {
        type,
        title,
        body,
        eventId,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  const tokenDocs = (
    await Promise.all(
      recipients.map((uid) => db.collection('users').doc(uid).collection('fcmTokens').get()),
    )
  ).flatMap((snapshot) => snapshot.docs);
  if (tokenDocs.length === 0) return;

  const project = process.env.GCLOUD_PROJECT;
  const link = project ? `https://${project}.web.app/event/${eventId}` : undefined;
  for (let start = 0; start < tokenDocs.length; start += 500) {
    const docs = tokenDocs.slice(start, start + 500);
    try {
      const response = await getMessaging().sendEachForMulticast({
        tokens: docs.map((doc) => doc.id),
        notification: { title, body },
        webpush: link ? { fcmOptions: { link } } : undefined,
      });
      await Promise.all(
        response.responses.map((result, index) => {
          const code = result.error?.code;
          if (code === 'messaging/registration-token-not-registered'
            || code === 'messaging/invalid-registration-token') {
            return docs[index].ref.delete();
          }
          return null;
        }),
      );
    } catch (error) {
      logger.warn('推播失敗', error);
    }
  }
}

/** 場次仍開放（公開或限熟人）且尚未開始。 */
function requireOpen(event, message) {
  // 0 = 公開報名、3 = 限熟人，兩者都算開放中。
  if (![0, 3].includes(event.status) || event.startTime.toDate() <= new Date()) {
    throw new HttpsError('failed-precondition', message);
  }
}

/**
 * 讀取候補名單（依報名順序）並挑出這次要遞補的組別。只做讀取，寫入由呼叫端處理，
 * 因為 transaction 必須先讀完再寫。
 */
async function readPromotions(transaction, eventRef, openSpots, excludeId) {
  if (openSpots <= 0) return { docs: [], people: 0 };
  const queue = await transaction.get(
    eventRef
      .collection('participants')
      .where('status', '==', 'waitlisted')
      .orderBy('joinedAt', 'asc')
      .orderBy(FieldPath.documentId(), 'asc')
      .limit(50),
  );
  const entries = queue.docs.filter((doc) => doc.id !== excludeId);
  const { ids, people } = pickPromotions(
    entries.map((doc) => ({ id: doc.id, party: partySize(doc.data()) })),
    openSpots,
  );
  return { docs: entries.filter((doc) => ids.includes(doc.id)), people };
}

function writePromotions(transaction, docs) {
  for (const doc of docs) {
    transaction.update(doc.ref, {
      status: 'attending',
      promotedAt: FieldValue.serverTimestamp(),
    });
  }
}

/**
 * 把 uid 從場次名單移除；若移除的是正取且有候補，依報名順序遞補第一位。
 * 退出報名（本人）與管理者移除共用。
 */
async function removeFromEvent(
  eventId,
  uid,
  closedMessage,
  authorize = async () => {},
  { enforceDeadline = false } = {},
) {
  const eventRef = db.collection('events').doc(eventId);
  const participantRef = eventRef.collection('participants').doc(uid);
  return db.runTransaction(async (transaction) => {
    const [eventSnapshot, participantSnapshot] = await Promise.all([
      transaction.get(eventRef),
      transaction.get(participantRef),
    ]);
    if (!eventSnapshot.exists) {
      throw new HttpsError('not-found', '找不到場次。');
    }
    const event = eventSnapshot.data();
    // 先檢查權限，避免無權限者藉由回應判斷某人是否在名單中。
    await authorize(event, transaction);
    if (!participantSnapshot.exists) return { left: false };

    const participant = participantSnapshot.data();
    requireOpen(event, closedMessage);

    // 人數以「組」計：本人＋同行朋友。
    const party = partySize(participant);
    let attendeeCount = event.attendeeCount ?? 0;
    let waitlistCount = event.waitlistCount ?? 0;
    if (participant.status === 'waitlisted') {
      waitlistCount -= party;
    } else if (participant.status === 'attending') {
      // 球友自行取消時檢查主揪設定的期限；主揪或管理者移除不受限。
      if (enforceDeadline && isPastCancelDeadline(event, new Date())) {
        throw new HttpsError(
          'failed-precondition',
          `已超過取消期限（開始前 ${event.cancelDeadlineHours} 小時），請聯絡主揪。`,
        );
      }
      attendeeCount -= party;
    } else {
      throw new HttpsError('failed-precondition', '報名狀態無效。');
    }
    if (attendeeCount < 0 || waitlistCount < 0) {
      throw new HttpsError('failed-precondition', '報名人數資料不一致。');
    }

    // 有人離開後重新檢查候補：前面的組放得下就依序遞補。
    const openSpots = event.maxPlayers - (event.existingPlayers ?? 0) - attendeeCount;
    const promotion = waitlistCount > 0
      ? await readPromotions(transaction, eventRef, openSpots, participantRef.id)
      : { docs: [], people: 0 };

    transaction.delete(participantRef);
    writePromotions(transaction, promotion.docs);
    transaction.update(eventRef, {
      attendeeCount: attendeeCount + promotion.people,
      waitlistCount: waitlistCount - promotion.people,
    });
    return {
      left: true,
      status: participant.status,
      promoted: promotion.docs.length,
    };
  });
}

// 主揪或系統管理者編輯場次。名額變多時，在同一個 transaction 內依報名順序遞補候補，
// 避免空出的名額被新報名者搶走。
exports.updateEvent = onCall(async (request) => {
  const uid = requireGoogleUser(request, 'Google 登入後才能編輯場次。');
  const eventId = requireId(request.data?.eventId, '場次編號無效。');

  const eventRef = db.collection('events').doc(eventId);
  return db.runTransaction(async (transaction) => {
    const [eventSnapshot, callerAdmin] = await Promise.all([
      transaction.get(eventRef),
      transaction.get(adminRef(uid)),
    ]);
    if (!eventSnapshot.exists) {
      throw new HttpsError('not-found', '找不到場次。');
    }
    const event = eventSnapshot.data();
    if (event.organizerId !== uid && !callerAdmin.exists) {
      throw new HttpsError('permission-denied', '只有主揪或管理者可以編輯場次。');
    }
    requireOpen(event, '場次已開始或已取消，不能編輯。');

    // 一律以「主揪」的資料判斷，管理者代為編輯時不會寫入管理者自己的暱稱。
    const organizerId = event.organizerId;
    const [organizerEntry, organizerProfile] = await Promise.all([
      transaction.get(eventRef.collection('participants').doc(organizerId)),
      transaction.get(db.collection('users').doc(organizerId)),
    ]);

    let plan;
    try {
      plan = planEventUpdate(event, request.data.event, new Date());
    } catch (error) {
      if (error instanceof EventUpdateError) {
        throw new HttpsError(error.code, error.message);
      }
      throw error;
    }
    if (plan.fields.organizerPlaying && organizerEntry.exists) {
      throw new HttpsError(
        'failed-precondition',
        '主揪已經以球友身分報名，請先取消該報名再設定主揪上場。',
      );
    }

    const promotion = await readPromotions(transaction, eventRef, plan.openSpots);
    writePromotions(transaction, promotion.docs);
    transaction.update(eventRef, {
      ...plan.fields,
      // 順便補上或更新主揪暱稱（舊場次沒有這個欄位）。
      ...(typeof organizerProfile.data()?.name === 'string'
        ? { organizerName: organizerProfile.data().name }
        : {}),
      startTime: Timestamp.fromDate(plan.startTime),
      endTime: Timestamp.fromDate(plan.endTime),
      attendeeCount: (event.attendeeCount ?? 0) + promotion.people,
      waitlistCount: (event.waitlistCount ?? 0) - promotion.people,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { updated: true, promoted: promotion.docs.length };
  });
});

// 本人退出報名或候補。
exports.leaveEvent = onCall(async (request) => {
  const uid = requireGoogleUser(request, 'Google 登入後才能取消報名。');
  const eventId = requireId(request.data?.eventId, '場次編號無效。');
  return removeFromEvent(eventId, uid, '場次已開始或不開放取消。', undefined, {
    enforceDeadline: true,
  });
});

// 主揪或系統管理者把某位球友移出名單；正取被移除時候補會自動遞補。
exports.removeParticipant = onCall(async (request) => {
  const uid = requireGoogleUser(request, 'Google 登入後才能管理名單。');
  const eventId = requireId(request.data?.eventId, '場次編號無效。');
  const userId = requireId(request.data?.userId, '球友編號無效。');
  const authorize = async (event, transaction) => {
    if (event.organizerId === uid) return;
    if (!(await transaction.get(adminRef(uid))).exists) {
      throw new HttpsError('permission-denied', '只有主揪或系統管理者可以移除報名者。');
    }
  };
  const result = await removeFromEvent(
    eventId,
    userId,
    '場次已開始或已取消，不能移除報名者。',
    authorize,
  );
  if (!result.left) {
    throw new HttpsError('not-found', '這位球友不在名單中。');
  }
  const event = (await db.collection('events').doc(eventId).get()).data();
  await notify([userId], removedNotice(event), eventId);
  return result;
});

// 候補轉正取（退出、移除、名額增加都會觸發）時通知本人。
exports.onParticipantUpdated = onDocumentUpdated(
  'events/{eventId}/participants/{userId}',
  async (change) => {
    const before = change.data?.before.data();
    const after = change.data?.after.data();
    const { eventId, userId } = change.params;
    const event = (await db.collection('events').doc(eventId).get()).data();
    const notice = participantChangeNotice(before, after, event);
    if (notice) await notify([userId], notice, eventId);
  },
);

// 場次被取消、主揪更新資訊、主揪確定費用時通知報名者。
exports.onEventUpdated = onDocumentUpdated('events/{eventId}', async (change) => {
  const notice = eventChangeNotice(change.data?.before.data(), change.data?.after.data());
  if (!notice) return;
  const { eventId } = change.params;
  let participants = db.collection('events').doc(eventId).collection('participants');
  if (notice.attendingOnly) participants = participants.where('status', '==', 'attending');
  const snapshot = await participants.get();
  await notify(snapshot.docs.map((doc) => doc.id), notice, eventId);
});
