const { initializeApp } = require('firebase-admin/app');
const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');

function option(name) {
  return process.argv.find((arg) => arg.startsWith(`--${name}=`))?.split('=')[1];
}

function readRoster(data, eventId) {
  const attendees = data.attendeeIds ?? [];
  const waitlist = data.waitlistIds ?? [];
  if (!Array.isArray(attendees) || !Array.isArray(waitlist)) {
    throw new Error(`Event ${eventId} has a malformed roster; migration stopped.`);
  }
  if (attendees.length + waitlist.length > 240) {
    throw new Error(`Event ${eventId} exceeds the safe migration limit of 240 members.`);
  }
  const allIds = [...attendees, ...waitlist];
  if (
    allIds.some((uid) => typeof uid !== 'string' || !uid || uid.includes('/')) ||
    new Set(allIds).size !== allIds.length
  ) {
    throw new Error(`Event ${eventId} has invalid or duplicate participant UIDs.`);
  }
  return { attendees, waitlist };
}

async function main() {
  const projectId = option('project');
  const apply = process.argv.includes('--apply');
  if (!projectId || projectId.startsWith('demo-')) {
    throw new Error('請提供實際 Firebase 專案：--project=PROJECT_ID');
  }
  if (apply && !process.argv.includes('--confirm-private-roster-migration')) {
    throw new Error(
      '套用前請明確加上 --confirm-private-roster-migration；預設只預覽。',
    );
  }

  initializeApp({ projectId });
  const db = getFirestore();
  const events = await db.collection('events').get();
  let migrated = 0;
  let skipped = 0;
  for (const eventDocument of events.docs) {
    const data = eventDocument.data();
    const { attendees, waitlist } = readRoster(data, eventDocument.id);
    const hasLegacyRoster =
      Object.hasOwn(data, 'attendeeIds') || Object.hasOwn(data, 'waitlistIds');
    const hasValidCounts =
      Number.isInteger(data.attendeeCount) &&
      data.attendeeCount >= 0 &&
      Number.isInteger(data.waitlistCount) &&
      data.waitlistCount >= 0;
    if (!hasLegacyRoster && hasValidCounts) {
      skipped++;
      continue;
    }
    migrated++;
    if (!apply) continue;

    const eventRef = eventDocument.ref;
    await db.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(eventRef);
      if (!currentSnapshot.exists) return;
      const current = currentSnapshot.data();
      const { attendees: currentAttendees, waitlist: currentWaitlist } =
        readRoster(current, eventDocument.id);
      const entries = [
        ...currentAttendees.map((uid, index) => ({ uid, status: 'attending', index })),
        ...currentWaitlist.map((uid, index) => ({ uid, status: 'waitlisted', index })),
      ];
      const participantRefs = entries.map(({ uid }) =>
        eventRef.collection('participants').doc(uid),
      );
      const participantSnapshots = await Promise.all(
        participantRefs.map((ref) => transaction.get(ref)),
      );
      const migrationStartedAt = Date.now();
      for (let index = 0; index < entries.length; index++) {
        const { uid, status, index: joinedIndex } = entries[index];
        const existing = participantSnapshots[index];
        const joinedAtMillis =
          migrationStartedAt +
          (status === 'waitlisted' ? 1000 : 0) +
          joinedIndex;
        if (existing.exists) {
          const value = existing.data();
          if (value.userId !== uid || value.status !== status) {
            throw new Error(`場次 ${eventDocument.id} 的私有名單與舊資料衝突。`);
          }
          if (value.eventId != null && value.eventId !== eventRef.id) {
            throw new Error(`場次 ${eventDocument.id} 的參與文件 ID 不一致。`);
          }
          const repairs = {};
          if (value.eventId == null) repairs.eventId = eventRef.id;
          if (!(value.joinedAt instanceof Timestamp)) {
            repairs.joinedAt = Timestamp.fromMillis(joinedAtMillis);
          }
          if (Object.keys(repairs).length > 0) {
            transaction.update(existing.ref, repairs);
          }
          continue;
        }
        transaction.create(participantRefs[index], {
          eventId: eventRef.id,
          userId: uid,
          status,
          joinedAt: Timestamp.fromMillis(joinedAtMillis),
        });
      }
      transaction.update(eventRef, {
        attendeeCount: currentAttendees.length,
        waitlistCount: currentWaitlist.length,
        attendeeIds: FieldValue.delete(),
        waitlistIds: FieldValue.delete(),
      });
    });
  }

  console.log(
    `${apply ? '已遷移' : '預覽完成'}：${migrated} 場需遷移，${skipped} 場沒有舊 UID 名單。`,
  );
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
