const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
  deleteDoc,
  query,
  where,
  writeBatch,
  collectionGroup,
  Timestamp,
  serverTimestamp,
} = require('firebase/firestore');

const rules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
const future = Timestamp.fromDate(new Date(Date.now() + 86_400_000));
const later = Timestamp.fromDate(new Date(Date.now() + 90_000_000));
const event = (overrides = {}) => ({
  groupId: '', organizerId: 'alice', sport: 'basketball',
  district: '台北市大安區', description: '', existingPlayers: 1,
  startTime: future, endTime: later, venue: '體育館', cost: 600,
  costMode: 'totalVenue', organizerPlaying: true, maxPlayers: 2,
  attendeeCount: 0, waitlistCount: 0, status: 0, isRecurring: false,
  ...overrides,
});

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-jiuka-rules',
    firestore: { host: '127.0.0.1', port: 8080, rules },
  });
  try {
    const google = (uid) => env.authenticatedContext(uid, {
      email: `${uid}@example.com`, firebase: { sign_in_provider: 'google.com' },
    }).firestore();
    const password = env.authenticatedContext('legacy', {
      email: 'legacy@example.com', firebase: { sign_in_provider: 'password' },
    }).firestore();
    const guest = env.unauthenticatedContext().firestore();
    const alice = google('alice');
    const bob = google('bob');
    const carol = google('carol');
    const game = (store) => doc(store, 'events', 'game');

    await assertSucceeds(setDoc(doc(alice, 'users', 'alice'), {
      name: 'Alice', email: 'alice@example.com', avatarUrl: null, joinedGroups: [],
    }));
    await assertFails(getDoc(doc(bob, 'users', 'alice')));
    await assertFails(getDocs(collection(alice, 'users')));
    await assertFails(setDoc(doc(password, 'users', 'legacy'), {
      name: 'Legacy', email: 'legacy@example.com', avatarUrl: null, joinedGroups: [],
    }));
    await assertFails(updateDoc(doc(alice, 'users', 'alice'), { email: 'new@example.com' }));
    await assertSucceeds(updateDoc(doc(alice, 'users', 'alice'), { name: '自訂暱稱' }));

    await assertFails(setDoc(game(guest), event()));
    await assertFails(setDoc(game(bob), event()));
    await assertFails(setDoc(game(alice), event({ cost: -1 })));
    await assertSucceeds(setDoc(game(alice), event()));
    await assertSucceeds(getDoc(game(guest)));
    await assertSucceeds(getDocs(query(collection(guest, 'events'), where('status', '==', 0))));
    await assertFails(updateDoc(game(guest), { attendeeCount: 1 }));
    await assertFails(updateDoc(game(password), { attendeeCount: 1 }));
    await assertFails(updateDoc(game(bob), { cost: 1 }));
    const join = async (store, uid, status, counter) => {
      const batch = writeBatch(store);
      batch.update(game(store), { [counter]: 1 });
      batch.set(doc(store, 'events', 'game', 'participants', uid), {
        eventId: 'game', userId: uid, status,
        joinedAt: serverTimestamp(),
      });
      await batch.commit();
    };
    await assertFails(updateDoc(game(bob), { attendeeCount: 1 }));
    await assertSucceeds(join(bob, 'bob', 'attending', 'attendeeCount'));
    await assertSucceeds(join(carol, 'carol', 'waitlisted', 'waitlistCount'));
    await assertFails(getDoc(doc(guest, 'events', 'game', 'participants', 'bob')));
    await assertFails(getDoc(doc(carol, 'events', 'game', 'participants', 'bob')));
    await assertSucceeds(getDoc(doc(bob, 'events', 'game', 'participants', 'bob')));
    await assertSucceeds(getDocs(query(
      collectionGroup(carol, 'participants'), where('userId', '==', 'carol'),
    )));
    await assertSucceeds(getDocs(collection(alice, 'events', 'game', 'participants')));
    assert.equal((await getDoc(game(guest))).data().attendeeCount, 1);
    assert.equal((await getDoc(game(guest))).data().waitlistCount, 1);
    await assertFails(deleteDoc(doc(alice, 'events', 'game', 'participants', 'bob')));
    await assertFails(deleteDoc(game(alice)));

    await assertSucceeds(setDoc(doc(alice, 'groups', 'group'), {
      name: '球友團', description: '', adminId: 'alice', maxPlayersDefault: 10,
      recurringEventSettings: null, memberIds: ['alice'],
    }));
    await assertFails(getDoc(doc(guest, 'groups', 'group')));
    await assertFails(updateDoc(doc(bob, 'groups', 'group'), { adminId: 'bob' }));
    await assertSucceeds(updateDoc(doc(bob, 'groups', 'group'), { memberIds: ['alice', 'bob'] }));
    await assertFails(updateDoc(doc(carol, 'groups', 'group'), { memberIds: ['carol'] }));
    await assertFails(setDoc(doc(bob, 'events', 'foreign-group'), event({
      organizerId: 'bob', groupId: 'group',
    })));
    await assertSucceeds(setDoc(doc(alice, 'events', 'own-group'), event({ groupId: 'group' })));
    console.log('Firestore rules: all allow/deny cases passed');
  } finally {
    await env.cleanup();
  }
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
