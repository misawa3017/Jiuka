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
  groupId: '', organizerId: 'alice', organizerName: '自訂暱稱', title: '週三晚間籃球', sport: 'basketball',
  city: '臺北市', district: '臺北市大安區', description: '', existingPlayers: 1,
  startTime: future, endTime: later, venue: '體育館', cost: 600,
  costMode: 'totalVenue', organizerPlaying: true, maxPlayers: 2,
  attendeeCount: 0, waitlistCount: 0, status: 0, isRecurring: false, cancelDeadlineHours: 0,
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
    // 系統管理者 root：admins 文件只能繞過規則（等同 Console／Admin SDK）建立。
    const root = google('root');
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'admins', 'root'), { email: 'root@example.com' });
    });
    await assertSucceeds(getDoc(doc(root, 'admins', 'root')));
    await assertFails(getDoc(doc(bob, 'admins', 'root')));
    await assertFails(getDocs(collection(root, 'admins')));
    await assertFails(setDoc(doc(bob, 'admins', 'bob'), { email: 'bob@example.com' }));
    await assertFails(updateDoc(doc(root, 'admins', 'root'), { email: 'x@example.com' }));

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
    // 站內通知：只有本人能讀、只能標成已讀；前端不能建立或刪除。
    const notice = (store) => doc(store, 'users', 'alice', 'notifications', 'n1');
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(notice(context.firestore()), {
        type: 'promoted', title: 't', body: 'b', eventId: 'game', read: false, createdAt: Timestamp.now(),
      });
    });
    await assertSucceeds(getDocs(collection(alice, 'users', 'alice', 'notifications')));
    await assertFails(getDoc(notice(guest)));
    await assertFails(getDocs(collection(bob, 'users', 'alice', 'notifications')));
    await assertFails(updateDoc(notice(alice), { title: '改內容' }));
    await assertFails(updateDoc(notice(alice), { read: false, title: 'x' }));
    await assertFails(updateDoc(notice(bob), { read: true }));
    await assertSucceeds(updateDoc(notice(alice), { read: true }));
    await assertFails(setDoc(doc(alice, 'users', 'alice', 'notifications', 'n2'), { title: '偽造' }));
    await assertFails(deleteDoc(notice(alice)));
    // 推播 token：本人可新增與刪除，別人不行。
    const token = (store, uid) => doc(store, 'users', uid, 'fcmTokens', 'token-abc');
    await assertSucceeds(setDoc(token(alice, 'alice'), { createdAt: serverTimestamp() }));
    await assertFails(setDoc(token(bob, 'alice'), { createdAt: serverTimestamp() }));
    await assertFails(setDoc(token(alice, 'alice'), { createdAt: serverTimestamp(), extra: 1 }));
    await assertFails(getDocs(collection(alice, 'users', 'alice', 'fcmTokens')));
    await assertFails(deleteDoc(token(bob, 'alice')));
    await assertSucceeds(deleteDoc(token(alice, 'alice')));
    for (const [uid, store, name] of [['bob', bob, 'Bob'], ['carol', carol, 'Carol']]) {
      await assertSucceeds(setDoc(doc(store, 'users', uid), {
        name, email: `${uid}@example.com`, avatarUrl: null, joinedGroups: [],
      }));
    }

    await assertFails(setDoc(game(guest), event()));
    await assertFails(setDoc(game(bob), event()));
    await assertFails(setDoc(game(alice), event({ cost: -1 })));
    await assertFails(setDoc(game(alice), event({ cancelDeadlineHours: 5 })));
    const { cancelDeadlineHours: _omitDeadline, ...withoutDeadline } = event();
    await assertFails(setDoc(game(alice), withoutDeadline));
    // 地區：必須有縣市，且地區全名以該縣市開頭、後面接鄉鎮市區。
    const { city: _omitCity, ...withoutCity } = event();
    await assertFails(setDoc(game(alice), withoutCity));
    await assertFails(setDoc(game(alice), event({ city: '' })));
    await assertFails(setDoc(game(alice), event({ district: '新北市板橋區' })));
    await assertFails(setDoc(game(alice), event({ district: '臺北市' })));
    // 主揪暱稱：必須等於主揪自己的暱稱，不能省略或冒名。
    const { organizerName: _omitName, ...withoutName } = event();
    await assertFails(setDoc(game(alice), withoutName));
    await assertFails(setDoc(game(alice), event({ organizerName: 'Bob' })));
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
        joinedAt: serverTimestamp(), guests: 0, ...extra,
      });
      await batch.commit();
    };
    await assertFails(updateDoc(game(bob), { attendeeCount: 1 }));
    // 報名時必須帶上自己的暱稱，不能省略或冒用別人的名字。
    await assertFails(join(bob, 'bob', 'attending', 'attendeeCount', {}));
    await assertFails(join(bob, 'bob', 'attending', 'attendeeCount', { displayName: 'Alice' }));
    // 同行朋友：0～3 人；名額不夠整組放不進正取，計數要加整組人數。
    await assertFails(join(bob, 'bob', 'attending', 'attendeeCount', { displayName: 'Bob', guests: 4 }));
    await assertFails(join(bob, 'bob', 'attending', 'attendeeCount', { displayName: 'Bob', guests: 1 }));
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
    // 出席與收款：主揪與管理者可記錄，只能是布林；球友本人與其他人不行。
    await assertSucceeds(updateDoc(rosterEntry(alice, 'bob'), { attended: true, paid: false }));
    await assertSucceeds(updateDoc(rosterEntry(root, 'bob'), { paid: true }));
    await assertFails(updateDoc(rosterEntry(alice, 'bob'), { attended: 'yes' }));
    await assertFails(updateDoc(rosterEntry(alice, 'bob'), { paid: true, status: 'waitlisted' }));
    await assertFails(updateDoc(rosterEntry(bob, 'bob'), { paid: false }));
    await assertFails(updateDoc(rosterEntry(carol, 'bob'), { attended: false }));
    const marked = (await getDoc(rosterEntry(alice, 'bob'))).data();
    assert.equal(marked.attended, true);
    assert.equal(marked.paid, true);
    // 管理者可讀任何場次的名單。
    await assertSucceeds(getDocs(roster(root)));
    await assertSucceeds(getDoc(rosterEntry(root, 'bob')));

    // 改暱稱：本人可在同一批寫入同步名單上的暱稱；不能改成別的名字，也不能改別人的。
    const rename = writeBatch(bob);
    rename.update(doc(bob, 'users', 'bob'), { name: 'Bobby' });
    rename.update(rosterEntry(bob, 'bob'), { displayName: 'Bobby' });
    await assertSucceeds(rename.commit());
    assert.equal((await getDoc(rosterEntry(alice, 'bob'))).data().displayName, 'Bobby');
    await assertFails(updateDoc(rosterEntry(bob, 'bob'), { displayName: '假名字' }));
    await assertFails(updateDoc(rosterEntry(bob, 'bob'), { displayName: 'Bobby', status: 'waitlisted' }));
    await assertFails(updateDoc(rosterEntry(alice, 'bob'), { displayName: 'Robert' }));
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
      displayName: 'Dave', guests: 0,
    });
    await assertFails(lateJoin.commit());

    const groupDoc = (store) => doc(store, 'groups', 'group');
    const newGroup = (extra = {}) => ({
      name: '球友團', description: '', adminId: 'alice', maxPlayersDefault: 10,
      recurringEventSettings: null, memberIds: ['alice'], memberNames: { alice: '自訂暱稱' }, ...extra,
    });
    // 建立球隊：成員暱稱表只能有自己，且等於自己的暱稱。
    const { memberNames: _omitNames, ...groupWithoutNames } = newGroup();
    await assertFails(setDoc(groupDoc(alice), groupWithoutNames));
    await assertFails(setDoc(groupDoc(alice), newGroup({ memberNames: { alice: '假名' } })));
    await assertSucceeds(setDoc(groupDoc(alice), newGroup()));
    await assertFails(getDoc(groupDoc(guest)));
    await assertFails(updateDoc(groupDoc(bob), { adminId: 'bob' }));
    // 加入球隊：要同時寫入自己的暱稱；不能冒名或改別人的。
    await assertFails(updateDoc(groupDoc(bob), { memberIds: ['alice', 'bob'] }));
    await assertFails(updateDoc(groupDoc(bob), {
      memberIds: ['alice', 'bob'], 'memberNames.bob': 'Alice',
    }));
    await assertFails(updateDoc(groupDoc(bob), {
      memberIds: ['alice', 'bob'], 'memberNames.bob': 'Bobby', 'memberNames.alice': 'x',
    }));
    await assertSucceeds(updateDoc(groupDoc(bob), {
      memberIds: ['alice', 'bob'], 'memberNames.bob': 'Bobby',
    }));
    await assertFails(updateDoc(groupDoc(carol), { memberIds: ['carol'] }));
    // 成員同步自己的暱稱：只能改自己那格；非成員不行。
    const renameBob = writeBatch(bob);
    renameBob.update(doc(bob, 'users', 'bob'), { name: 'Bob 新名' });
    renameBob.update(groupDoc(bob), { 'memberNames.bob': 'Bob 新名' });
    await assertSucceeds(renameBob.commit());
    await assertFails(updateDoc(groupDoc(bob), { 'memberNames.alice': '亂改' }));
    await assertFails(updateDoc(groupDoc(carol), { 'memberNames.carol': 'Carol' }));
    assert.deepEqual((await getDoc(groupDoc(alice))).data().memberNames, {
      alice: '自訂暱稱', bob: 'Bob 新名',
    });
    await assertFails(setDoc(doc(bob, 'events', 'foreign-group'), event({
      organizerId: 'bob', groupId: 'group',
    })));
    await assertSucceeds(setDoc(doc(alice, 'events', 'own-group'), event({ groupId: 'group' })));

    // 管理者可取消別人的場次，但同樣只能改狀態，不能順便改其他欄位。
    await assertSucceeds(setDoc(doc(alice, 'events', 'admin-cancel'), event()));
    const adminTarget = (store) => doc(store, 'events', 'admin-cancel');
    await assertFails(updateDoc(adminTarget(bob), { status: 2, cancelledAt: serverTimestamp() }));
    await assertFails(updateDoc(adminTarget(root), { status: 2, cancelledAt: serverTimestamp(), cost: 0 }));
    await assertFails(updateDoc(adminTarget(root), { cost: 0 }));
    await assertSucceeds(updateDoc(adminTarget(root), { status: 2, cancelledAt: serverTimestamp() }));

    // 確定費用：開始後才能確定；只有主揪或管理者；只能改這兩個欄位；已取消的不行。
    const past = Timestamp.fromDate(new Date(Date.now() - 3_600_000));
    await env.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'events', 'played'), event({ startTime: past, endTime: Timestamp.now() }));
      await setDoc(doc(context.firestore(), 'events', 'played-cancelled'), event({ startTime: past, endTime: Timestamp.now(), status: 2 }));
    });
    const confirm = (store, id, amount, extra = {}) => updateDoc(doc(store, 'events', id), {
      finalCostPerPerson: amount, costConfirmedAt: serverTimestamp(), ...extra,
    });
    await assertFails(confirm(alice, 'admin-cancel', 200));
    await assertFails(confirm(bob, 'played', 200));
    await assertFails(confirm(alice, 'played', -1));
    await assertFails(confirm(alice, 'played', 1.5));
    await assertFails(confirm(alice, 'played', 200, { cost: 0 }));
    await assertFails(updateDoc(doc(alice, 'events', 'played'), { finalCostPerPerson: 200, costConfirmedAt: Timestamp.now() }));
    await assertFails(confirm(alice, 'played-cancelled', 200));
    await assertSucceeds(confirm(alice, 'played', 200));
    await assertSucceeds(confirm(root, 'played', 180));
    assert.equal((await getDoc(doc(guest, 'events', 'played'))).data().finalCostPerPerson, 180);

    // 主揪改暱稱：同一批寫入同步自己的場次，包含已取消的 game；不能改別人的或亂填。
    const renameOrganizer = writeBatch(alice);
    renameOrganizer.update(doc(alice, 'users', 'alice'), { name: 'Alice 主揪' });
    renameOrganizer.update(game(alice), { organizerName: 'Alice 主揪' });
    await assertSucceeds(renameOrganizer.commit());
    assert.equal((await getDoc(game(guest))).data().organizerName, 'Alice 主揪');
    await assertFails(updateDoc(game(alice), { organizerName: '假主揪' }));
    await assertFails(updateDoc(game(bob), { organizerName: 'Bobby' }));
    await assertFails(updateDoc(game(alice), { organizerName: 'Alice 主揪', status: 0 }));

    // 帶朋友報名：名額 5、已有主揪 1 人。
    const groupEvent = (store) => doc(store, 'events', 'group-game');
    await assertSucceeds(setDoc(groupEvent(alice), event({ organizerName: 'Alice 主揪', maxPlayers: 5 })));
    const joinGroup = async (store, uid, name, status, counter, value, guests) => {
      const batch = writeBatch(store);
      batch.update(groupEvent(store), { [counter]: value });
      batch.set(doc(store, 'events', 'group-game', 'participants', uid), {
        eventId: 'group-game', userId: uid, status, joinedAt: serverTimestamp(), displayName: name, guests,
      });
      await batch.commit();
    };
    // 計數只加 1 但帶 2 位朋友 → 拒絕；正確加 3 → 成功（1 + 3 = 4 ≤ 5）。
    await assertFails(joinGroup(bob, 'bob', 'Bob 新名', 'attending', 'attendeeCount', 1, 2));
    await assertSucceeds(joinGroup(bob, 'bob', 'Bob 新名', 'attending', 'attendeeCount', 3, 2));
    // 剩 1 位，carol 帶 1 位朋友（2 人）放不下 → 只能整組候補。
    await assertFails(joinGroup(carol, 'carol', 'Carol', 'attending', 'attendeeCount', 5, 1));
    await assertSucceeds(joinGroup(carol, 'carol', 'Carol', 'waitlisted', 'waitlistCount', 2, 1));
    // 雖然還有 1 個空位，但已有人候補，新報名也要排候補（不能插隊）。
    await assertSucceeds(setDoc(doc(dave, 'users', 'dave'), {
      name: 'Dave', email: 'dave@example.com', avatarUrl: null, joinedGroups: [],
    }));
    await assertFails(joinGroup(dave, 'dave', 'Dave', 'attending', 'attendeeCount', 4, 0));
    await assertSucceeds(joinGroup(dave, 'dave', 'Dave', 'waitlisted', 'waitlistCount', 3, 0));
    console.log('Firestore rules: all allow/deny cases passed');
  } finally {
    await env.cleanup();
  }
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
