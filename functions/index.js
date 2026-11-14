const { initializeApp } = require('firebase-admin/app');
const {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { planEventUpdate, EventUpdateError } = require('./event_update');

initializeApp();
setGlobalOptions({ region: 'asia-east1', maxInstances: 10 });

const db = getFirestore();

// 主揪編輯場次。名額變多時，在同一個 transaction 內依報名順序遞補候補，
// 避免空出的名額被新報名者搶走。
exports.updateEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider !== 'google.com') {
    throw new HttpsError('unauthenticated', 'Google 登入後才能編輯場次。');
  }

  const eventId = request.data?.eventId;
  if (typeof eventId !== 'string' || !eventId || eventId.includes('/')) {
    throw new HttpsError('invalid-argument', '場次編號無效。');
  }

  const eventRef = db.collection('events').doc(eventId);
  const organizerEntryRef = eventRef.collection('participants').doc(uid);
  const organizerRef = db.collection('users').doc(uid);
  return db.runTransaction(async (transaction) => {
    const [eventSnapshot, organizerEntry, organizerProfile] = await Promise.all([
      transaction.get(eventRef),
      transaction.get(organizerEntryRef),
      transaction.get(organizerRef),
    ]);
    if (!eventSnapshot.exists) {
      throw new HttpsError('not-found', '找不到場次。');
    }
    const event = eventSnapshot.data();
    if (event.organizerId !== uid) {
      throw new HttpsError('permission-denied', '只有主揪可以編輯場次。');
    }
    if (event.status !== 0 || event.startTime.toDate() <= new Date()) {
      throw new HttpsError('failed-precondition', '場次已開始或已取消，不能編輯。');
    }

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
        '你已經以球友身分報名，請先取消報名再設定主揪上場。',
      );
    }

    let promoted = [];
    if (plan.promote > 0) {
      const queue = await transaction.get(
        eventRef
          .collection('participants')
          .where('status', '==', 'waitlisted')
          .orderBy('joinedAt', 'asc')
          .orderBy(FieldPath.documentId(), 'asc')
          .limit(plan.promote),
      );
      if (queue.size !== plan.promote) {
        throw new HttpsError('failed-precondition', '候補名單與人數不一致。');
      }
      promoted = queue.docs;
    }

    for (const entry of promoted) {
      transaction.update(entry.ref, {
        status: 'attending',
        promotedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(eventRef, {
      ...plan.fields,
      // 順便補上或更新主揪暱稱（舊場次沒有這個欄位）。
      ...(typeof organizerProfile.data()?.name === 'string'
        ? { organizerName: organizerProfile.data().name }
        : {}),
      startTime: Timestamp.fromDate(plan.startTime),
      endTime: Timestamp.fromDate(plan.endTime),
      attendeeCount: (event.attendeeCount ?? 0) + promoted.length,
      waitlistCount: (event.waitlistCount ?? 0) - promoted.length,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { updated: true, promoted: promoted.length };
  });
});

exports.leaveEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  if (!uid || provider !== 'google.com') {
    throw new HttpsError('unauthenticated', 'Google 登入後才能取消報名。');
  }

  const eventId = request.data?.eventId;
  if (typeof eventId !== 'string' || !eventId || eventId.includes('/')) {
    throw new HttpsError('invalid-argument', '場次編號無效。');
  }

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
    if (!participantSnapshot.exists) return { left: false };

    const event = eventSnapshot.data();
    const participant = participantSnapshot.data();
    if (event.status !== 0 || event.startTime.toDate() <= new Date()) {
      throw new HttpsError('failed-precondition', '場次已開始或不開放取消。');
    }

    if (participant.status === 'waitlisted') {
      if (event.waitlistCount < 1) {
        throw new HttpsError('failed-precondition', '候補人數資料不一致。');
      }
      transaction.delete(participantRef);
      transaction.update(eventRef, { waitlistCount: event.waitlistCount - 1 });
      return { left: true, status: 'waitlisted' };
    }
    if (participant.status !== 'attending') {
      throw new HttpsError('failed-precondition', '報名狀態無效。');
    }

    if (event.waitlistCount > 0) {
      const queue = eventRef
        .collection('participants')
        .where('status', '==', 'waitlisted')
        .orderBy('joinedAt', 'asc')
        .orderBy(FieldPath.documentId(), 'asc')
        .limit(1);
      const waitlistSnapshot = await transaction.get(queue);
      if (waitlistSnapshot.empty) {
        throw new HttpsError('failed-precondition', '候補名單與人數不一致。');
      }
      const nextParticipant = waitlistSnapshot.docs[0];
      transaction.delete(participantRef);
      transaction.update(nextParticipant.ref, {
        status: 'attending',
        promotedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(eventRef, {
        waitlistCount: event.waitlistCount - 1,
      });
      return { left: true, status: 'attending', promoted: true };
    }

    if (event.attendeeCount < 1) {
      throw new HttpsError('failed-precondition', '正取人數資料不一致。');
    }
    transaction.delete(participantRef);
    transaction.update(eventRef, { attendeeCount: event.attendeeCount - 1 });
    return { left: true, status: 'attending', promoted: false };
  });
});
