const test = require('node:test');
const assert = require('node:assert/strict');
const { datesToCreate, taipeiDateTime, taipeiToday, seasonEventId } = require('./schedules');

// 2027-01-06 是週三。
const season = (overrides = {}) => ({
  startDate: '2027-01-06',
  endDate: '2027-03-31',
  dayOfWeek: 3,
  openDaysBefore: 7,
  skipDates: [],
  lastCreatedFor: '',
  active: true,
  ...overrides,
});
// 台灣時間 2027-01-01 06:00 = UTC 2026-12-31 22:00。
const taipei = (date, hour = 6) => new Date(`${date}T${String(hour).padStart(2, '0')}:00:00+08:00`);

test('用台灣時間判斷今天（UTC 還是前一天時）', () => {
  assert.equal(taipeiToday(new Date('2026-12-31T22:00:00Z')), '2027-01-01');
  assert.equal(taipeiToday(new Date('2027-01-01T15:59:00Z')), '2027-01-01');
  assert.equal(taipeiToday(new Date('2027-01-01T16:00:00Z')), '2027-01-02');
});

test('季租開始前，到了提前天數才開第一場', () => {
  assert.deepEqual(datesToCreate(season(), taipei('2026-12-29')), []);
  assert.deepEqual(datesToCreate(season(), taipei('2026-12-30')), ['2027-01-06']);
});

test('已經開過的日期不重複開；下一週到了時間才開', () => {
  const opened = season({ lastCreatedFor: '2027-01-06' });
  assert.deepEqual(datesToCreate(opened, taipei('2027-01-05')), []);
  assert.deepEqual(datesToCreate(opened, taipei('2027-01-06')), ['2027-01-13']);
});

test('提前 14 天會一次開出兩週；停打日跳過', () => {
  assert.deepEqual(
    datesToCreate(season({ openDaysBefore: 14 }), taipei('2027-01-06')),
    ['2027-01-06', '2027-01-13', '2027-01-20'],
  );
  assert.deepEqual(
    datesToCreate(season({ skipDates: ['2027-01-13'], lastCreatedFor: '2027-01-06' }), taipei('2027-01-10')),
    [],
  );
});

test('季租結束後、或停用時不再開', () => {
  assert.deepEqual(datesToCreate(season(), taipei('2027-04-01')), []);
  assert.deepEqual(datesToCreate(season({ active: false }), taipei('2027-01-01')), []);
  assert.deepEqual(datesToCreate(season({ startDate: 'bad' }), taipei('2027-01-01')), []);
});

test('台灣時間轉成實際時刻，以及固定的場次 ID', () => {
  assert.equal(taipeiDateTime('2027-01-06', '20:00').toISOString(), '2027-01-06T12:00:00.000Z');
  assert.equal(taipeiDateTime('2027-01-06', '07:30').toISOString(), '2027-01-05T23:30:00.000Z');
  assert.equal(seasonEventId('g', 'q1', '2027-01-06'), 'g_q1_20270106');
});
