const test = require('node:test');
const assert = require('node:assert/strict');
const {
  planEventUpdate,
  isPastCancelDeadline,
  pickPromotions,
  partySize,
  EventUpdateError,
} = require('./event_update');

const now = new Date('2027-01-01T00:00:00Z');
const hour = 3_600_000;
const input = (overrides = {}) => ({
  title: '週三晚間籃球',
  sport: 'basketball',
  city: '臺北市',
  district: '臺北市大安區',
  venue: '大安運動中心',
  description: '',
  startTime: now.getTime() + 24 * hour,
  endTime: now.getTime() + 26 * hour,
  cost: 150,
  costMode: 'perPerson',
  organizerPlaying: true,
  existingPlayers: 6,
  maxPlayers: 10,
  cancelDeadlineHours: 0,
  ...overrides,
});
const rejects = (current, overrides, code) =>
  assert.throws(
    () => planEventUpdate(current, input(overrides), now),
    (error) => error instanceof EventUpdateError && error.code === code,
  );

test('名額調高或已約人數變少時算出空位；沒有候補就不用遞補', () => {
  const full = { attendeeCount: 4, waitlistCount: 3 };
  assert.equal(planEventUpdate(full, input({ maxPlayers: 10 }), now).openSpots, 0);
  assert.equal(planEventUpdate(full, input({ maxPlayers: 12 }), now).openSpots, 2);
  assert.equal(planEventUpdate(full, input({ existingPlayers: 5 }), now).openSpots, 1);
  assert.equal(planEventUpdate({ attendeeCount: 4, waitlistCount: 0 }, input({ maxPlayers: 20 }), now).openSpots, 0);
});

test('遞補整組一起上，前面那組放不下就停，後面不能插隊', () => {
  const queue = [
    { id: 'a', party: 1 },
    { id: 'b', party: 3 },
    { id: 'c', party: 1 },
  ];
  assert.deepEqual(pickPromotions(queue, 0), { ids: [], people: 0 });
  assert.deepEqual(pickPromotions(queue, 1), { ids: ['a'], people: 1 });
  assert.deepEqual(pickPromotions(queue, 3), { ids: ['a'], people: 1 });
  assert.deepEqual(pickPromotions(queue, 4), { ids: ['a', 'b'], people: 4 });
  assert.deepEqual(pickPromotions(queue, 9), { ids: ['a', 'b', 'c'], people: 5 });
});

test('一組人數：本人加同行朋友，舊資料視為 1 人', () => {
  assert.equal(partySize({ guests: 2 }), 3);
  assert.equal(partySize({}), 1);
  assert.equal(partySize({ guests: 'x' }), 1);
});

test('名額不能低於已約人數加正取人數', () => {
  rejects({ attendeeCount: 4, waitlistCount: 0 }, { maxPlayers: 9 }, 'failed-precondition');
  rejects({ attendeeCount: 4, waitlistCount: 0 }, { existingPlayers: 7 }, 'failed-precondition');
});

test('只回傳允許修改的欄位，時間轉成 Date', () => {
  const plan = planEventUpdate(
    { attendeeCount: 0, waitlistCount: 0 },
    input({ organizerId: 'hacker', status: 2, attendeeCount: 99 }),
    now,
  );
  assert.equal('organizerId' in plan.fields, false);
  assert.equal('status' in plan.fields, false);
  assert.equal('attendeeCount' in plan.fields, false);
  assert.ok(plan.startTime instanceof Date);
  assert.equal(plan.fields.city, '臺北市');
  assert.equal(plan.fields.title, '週三晚間籃球');
});

test('與發布場次相同的欄位驗證', () => {
  const empty = { attendeeCount: 0, waitlistCount: 0 };
  rejects(empty, { sport: 'tennis' }, 'invalid-argument');
  rejects(empty, { title: ' 前後空白 ' }, 'invalid-argument');
  rejects(empty, { title: '名'.repeat(41) }, 'invalid-argument');
  rejects(empty, { title: undefined }, 'invalid-argument');
  assert.equal(planEventUpdate(empty, input({ title: '' }), now).fields.title, '');
  rejects(empty, { district: ' ' }, 'invalid-argument');
  rejects(empty, { city: '' }, 'invalid-argument');
  rejects(empty, { district: '臺北市' }, 'invalid-argument');
  rejects(empty, { district: '新北市板橋區' }, 'invalid-argument');
  rejects(empty, { venue: ' 球館' }, 'invalid-argument');
  rejects(empty, { startTime: now.getTime() - hour }, 'invalid-argument');
  rejects(empty, { endTime: now.getTime() + 24 * hour }, 'invalid-argument');
  rejects(empty, { cost: -1 }, 'invalid-argument');
  rejects(empty, { cost: 1.5 }, 'invalid-argument');
  rejects(empty, { costMode: 'free' }, 'invalid-argument');
  rejects(empty, { organizerPlaying: true, existingPlayers: 0 }, 'invalid-argument');
  rejects(empty, { maxPlayers: 1, existingPlayers: 1 }, 'invalid-argument');
  rejects(empty, { cancelDeadlineHours: 5 }, 'invalid-argument');
  rejects(empty, { cancelDeadlineHours: undefined }, 'invalid-argument');
  assert.equal(planEventUpdate(empty, input({ cancelDeadlineHours: 24 }), now).fields.cancelDeadlineHours, 24);
  assert.throws(() => planEventUpdate(empty, null, now), EventUpdateError);
});

test('取消期限：不限時永遠可取消；有期限時開始前 N 小時內不能自行取消', () => {
  const start = { toMillis: () => now.getTime() + 5 * hour };
  assert.equal(isPastCancelDeadline({ startTime: start, cancelDeadlineHours: 0 }, now), false);
  assert.equal(isPastCancelDeadline({ startTime: start }, now), false);
  assert.equal(isPastCancelDeadline({ startTime: start, cancelDeadlineHours: 2 }, now), false);
  assert.equal(isPastCancelDeadline({ startTime: start, cancelDeadlineHours: 6 }, now), true);
  assert.equal(isPastCancelDeadline({ startTime: start, cancelDeadlineHours: 24 }, now), true);
});
