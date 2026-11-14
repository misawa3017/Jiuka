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
  groupId: '', organizerId: 'alice', title: '週三晚間籃球', sport: 'basketball',
  city: '臺北市', district: '臺北市大安區', description: '', existingPlayers: 1,
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
    for (const [uid, store, name] of [['bob', bob, 'Bob'], ['carol', carol, 'Carol']]) {
      await assertSucceeds(setDoc(doc(store, 'users', uid), {
        name, email: `${uid}@example.com`, avatarUrl: null, joinedGroups: [],
      }));
    }

    await assertFails(setDoc(game(guest), event()));
    await assertFails(setDoc(game(bob), event()));
    await assertFails(setDoc(game(alice), event({ cost: -1 })));
    // 地區：必須有縣市，且地區全名以該縣市開頭、後面接鄉鎮市區。
    const { city: _omitCity, ...withoutCity } = event();
    await assertFails(setDoc(game(alice), withoutCity));
    await assertFails(setDoc(game(alice), event({ city: '' })));
    await assertFails(setDoc(game(alice), event({ district: '新北市板橋區' })));
    await assertFails(setDoc(game(alice), event({ district: '臺北市' })));
    // 活動名稱：選填（可空字串），最多 40 字，不能前後空白，也不能省略欄位。
    const { title: _omitTitle, ...withoutTitle } = event();
    await assertFails(setDoc(game(alice), withoutTitle));
    await assertFails(setDoc(game(alice), event({ title: '名'.repeat(41) })));
    await assertFails(setDoc(game(alice), event({ title: ' 前後空白 ' })));
    await assertSucceeds(setDoc(doc(alice, 'events', 'untitled'), event({ title: '' })));
    await assertSucceeds(setDoc(game(alice), event()));
    await assertSucceeds(getDoc(game(guest)));
    await assertSucceeds(getDocs(query(collection(guest, 'events'), where('status', '==', 0))));
    await assertFails(updateDoc(game(guest), { attendeeCount: 1 }));
    await assertFails(updateDoc(game(password), { attendeeCount: 1 }));
    await assertFails(updateDoc(game(bob), { cost: 1 }));
    const join = async (store, uid, status, counter, extra = { displayName: uid === 'bob' ? 'Bob' : 'Carol' }) => {
      const batch = writeBatch(store);
      batch.update(game(store), { [counter]: 1 });
      batch.set(doc(store, 'events', 'game', 'participants', uid), {
        eventId: 'game', userId: uid, status,
        joinedAt: serverTimestamp(), ...extra,
      });
      await batch.commit();
    };
    await assertFails(updateDoc(game(bob), { attendeeCount: 1 }));
    // 報名時必須帶上自己的暱稱，不能省略或冒用別人的名字。
    await assertFails(join(bob, 'bob', 'attending', 'attendeeCount', {}));
    await assertFails(join(bob, 'bob', 'attending', 'attendeeCount', { displayName: 'Alice' }));
    await assertSucceeds(join(bob, 'bob', 'attending', 'attendeeCount'));
    await assertSucceeds(join(carol, 'carol', 'waitlisted', 'waitlistCount'));
    await assertFails(getDoc(doc(guest, 'events', 'game', 'participants', 'bob')));
    await assertFails(getDoc(doc(carol, 'events', 'game', 'participants', 'bob')));
    await assertSucceeds(getDoc(doc(bob, 'events', 'game', 'participants', 'bob')));
    await assertSucceeds(getDocs(query(
      collectionGroup(carol, 'participants'), where('userId', '==', 'carol'),
    )));
    // 主揪名單：主揪可讀整份名單與個別報名者，其他人不行。
    const roster = (store) => collection(store, 'events', 'game', 'participants');
    const rosterEntry = (store, uid) => doc(store, 'events', 'game', 'participants', uid);
    await assertSucceeds(getDocs(roster(alice)));
    assert.equal((await getDocs(roster(alice))).size, 2);
    await assertSucceeds(getDoc(rosterEntry(alice, 'bob')));
    await assertSucceeds(getDoc(rosterEntry(alice, 'carol')));
    await assertFails(getDocs(roster(bob)));
    await assertFails(getDocs(roster(carol)));
    await assertFails(getDocs(roster(guest)));
    await assertFails(getDocs(roster(password)));
    await assertFails(getDoc(rosterEntry(bob, 'carol')));
    assert.equal((await getDoc(rosterEntry(alice, 'bob'))).data().displayName, 'Bob');

    // 改暱稱：本人可在同一批寫入同步名單上的暱稱；不能改成別的名字，也不能改別人的。
    const rename = writeBatch(bob);
    rename.update(doc(bob, 'users', 'bob'), { name: 'Bobby' });
    rename.update(rosterEntry(bob, 'bob'), { displayName: 'Bobby' });
    await assertSucceeds(rename.commit());
    assert.equal((await getDoc(rosterEntry(alice, 'bob'))).data().displayName, 'Bobby');
    await assertFails(updateDoc(rosterEntry(bob, 'bob'), { displayName: '假名字' }));
    await assertFails(updateDoc(rosterEntry(bob, 'bob'), { displayName: 'Bobby', status: 'waitlisted' }));
    await assertFails(updateDoc(rosterEntry(alice, 'bob'), { displayName: 'Bobby' }));
    await assertFails(updateDoc(rosterEntry(carol, 'bob'), { displayName: 'Carol' }));
    assert.equal((await getDoc(game(guest))).data().attendeeCount, 1);
    assert.equal((await getDoc(game(guest))).data().waitlistCount, 1);
    await assertFails(deleteDoc(doc(alice, 'events', 'game', 'participants', 'bob')));
    await assertFails(deleteDoc(game(alice)));

    // 取消場次：只有主揪、只能改狀態為已取消，編輯其他欄位必須走 Cloud Function。
    const cancel = (store, extra = {}) => updateDoc(game(store), {
      status: 2, cancelledAt: serverTimestamp(), ...extra,
    });
    await assertFails(updateDoc(game(alice), { cost: 800 }));
    await assertFails(updateDoc(game(alice), { maxPlayers: 4 }));
    await assertFails(cancel(bob));
    await assertFails(cancel(guest));
    await assertFails(cancel(alice, { cost: 0 }));
    await assertFails(updateDoc(game(alice), { status: 2 }));
    await assertFails(updateDoc(game(alice), { status: 2, cancelledAt: Timestamp.now() }));
    await assertFails(updateDoc(game(alice), { status: 1, cancelledAt: serverTimestamp() }));
    await assertSucceeds(cancel(alice));
    assert.equal((await getDoc(game(guest))).data().status, 2);
    // 取消後不能重新開放，也不能再報名。
    await assertFails(updateDoc(game(alice), { status: 0 }));
    const dave = google('dave');
    const lateJoin = writeBatch(dave);
    lateJoin.update(game(dave), { waitlistCount: 2 });
    lateJoin.set(doc(dave, 'events', 'game', 'participants', 'dave'), {
      eventId: 'game', userId: 'dave', status: 'waitlisted', joinedAt: serverTimestamp(),
      displayName: 'Dave',
    });
    await assertFails(lateJoin.commit());

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
