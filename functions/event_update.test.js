const test = require('node:test');
const assert = require('node:assert/strict');
const { planEventUpdate, EventUpdateError } = require('./event_update');

const now = new Date('2027-01-01T00:00:00Z');
const hour = 3_600_000;
const input = (overrides = {}) => ({
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
  ...overrides,
});
const rejects = (current, overrides, code) =>
  assert.throws(
    () => planEventUpdate(current, input(overrides), now),
    (error) => error instanceof EventUpdateError && error.code === code,
  );

test('名額調高時，依空出的名額遞補候補，最多補到候補人數', () => {
  const full = { attendeeCount: 4, waitlistCount: 3 };
  assert.equal(planEventUpdate(full, input({ maxPlayers: 10 }), now).promote, 0);
  assert.equal(planEventUpdate(full, input({ maxPlayers: 12 }), now).promote, 2);
  assert.equal(planEventUpdate(full, input({ maxPlayers: 20 }), now).promote, 3);
});

test('已約人數變少也會空出名額並遞補', () => {
  const full = { attendeeCount: 4, waitlistCount: 2 };
  assert.equal(planEventUpdate(full, input({ existingPlayers: 5 }), now).promote, 1);
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
});

test('與發布場次相同的欄位驗證', () => {
  const empty = { attendeeCount: 0, waitlistCount: 0 };
  rejects(empty, { sport: 'tennis' }, 'invalid-argument');
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
  assert.throws(() => planEventUpdate(empty, null, now), EventUpdateError);
});
