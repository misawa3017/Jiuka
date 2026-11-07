const { initializeApp } = require('firebase-admin/app');
const {
  FieldPath,
  FieldValue,
  getFirestore,
} = require('firebase-admin/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

initializeApp();
setGlobalOptions({ region: 'asia-east1', maxInstances: 10 });

const db = getFirestore();

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
