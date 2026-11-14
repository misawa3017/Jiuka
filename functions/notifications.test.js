const test = require('node:test');
const assert = require('node:assert/strict');
const {
  participantChangeNotice,
  eventChangeNotice,
  removedNotice,
} = require('./notifications');

const at = (ms) => ({ toMillis: () => ms });
const event = { title: '週三晚間籃球', venue: '大安運動中心', status: 0 };

test('候補轉正取才通知本人', () => {
  assert.equal(
    participantChangeNotice({ status: 'waitlisted' }, { status: 'attending' }, event).type,
    'promoted',
  );
  assert.equal(participantChangeNotice({ status: 'attending' }, { status: 'attending', paid: true }, event), null);
  assert.equal(participantChangeNotice({ status: 'attending' }, { status: 'waitlisted' }, event), null);
});

test('取消場次優先於其他變動', () => {
  const notice = eventChangeNotice(
    { ...event, updatedAt: at(1) },
    { ...event, status: 2, updatedAt: at(2) },
  );
  assert.equal(notice.type, 'cancelled');
  assert.match(notice.body, /週三晚間籃球/);
});

test('主揪編輯（updatedAt 改變）才通知，報名人數變動不通知', () => {
  assert.equal(eventChangeNotice({ ...event }, { ...event, updatedAt: at(5) }).type, 'updated');
  assert.equal(eventChangeNotice({ ...event, updatedAt: at(5) }, { ...event, updatedAt: at(5), attendeeCount: 3 }), null);
});

test('費用確定只通知正取', () => {
  const notice = eventChangeNotice(
    { ...event },
    { ...event, costConfirmedAt: at(9), finalCostPerPerson: 180 },
  );
  assert.equal(notice.type, 'costConfirmed');
  assert.equal(notice.attendingOnly, true);
  assert.match(notice.body, /180 元/);
});

test('沒有活動名稱時用球館名稱', () => {
  assert.match(removedNotice({ venue: '三重運動中心' }).body, /三重運動中心/);
});
