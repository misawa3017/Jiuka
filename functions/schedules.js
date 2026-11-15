// 季租排程的日期計算。不碰資料庫，方便單獨測試。
// 季租日期存成 'yyyy-MM-dd'、時間存成 'HH:mm'，一律以台灣時間（UTC+8，無日光節約）解讀。

const TAIPEI_OFFSET_HOURS = 8;
const DAY = 86_400_000;

const pad = (n) => String(n).padStart(2, '0');

/** 'yyyy-MM-dd' → 以 UTC 午夜表示的日期（只用來做日期加減與星期判斷）。 */
function parseDate(text) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text || '');
  if (!match) return null;
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
}

function formatDate(date) {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

/** 現在的台灣日期，例如 '2027-01-06'。 */
function taipeiToday(now) {
  return formatDate(new Date(now.getTime() + TAIPEI_OFFSET_HOURS * 3_600_000));
}

/** 1 = 週一 … 7 = 週日（與季租的 dayOfWeek、Dart 的 weekday 相同）。 */
function weekday(date) {
  const day = date.getUTCDay();
  return day === 0 ? 7 : day;
}

/**
 * 這次排程要開出的打球日：在季租期間內、是指定的星期、不是停打日、
 * 不早於今天、在「提前天數」內，而且晚於 lastCreatedFor（避免重複開）。
 * @returns {string[]} 由早到晚的 'yyyy-MM-dd'
 */
function datesToCreate(season, now) {
  if (!season || season.active === false) return [];
  const start = parseDate(season.startDate);
  const end = parseDate(season.endDate);
  const today = parseDate(taipeiToday(now));
  if (!start || !end || !today) return [];
  const horizon = new Date(today.getTime() + (season.openDaysBefore || 0) * DAY);
  const from = start > today ? start : today;
  const until = end < horizon ? end : horizon;
  const skip = new Set(season.skipDates || []);
  const last = season.lastCreatedFor || '';
  const dates = [];
  for (let day = from; day <= until; day = new Date(day.getTime() + DAY)) {
    const text = formatDate(day);
    if (weekday(day) === season.dayOfWeek && !skip.has(text) && text > last) {
      dates.push(text);
    }
  }
  return dates;
}

/** 台灣時間的 '2027-01-06' + '20:00' → Date（UTC 時刻）。 */
function taipeiDateTime(dateText, timeText) {
  const date = parseDate(dateText);
  const match = /^(\d{2}):(\d{2})$/.exec(timeText || '');
  if (!date || !match) return null;
  return new Date(
    date.getTime() + (Number(match[1]) - TAIPEI_OFFSET_HOURS) * 3_600_000 + Number(match[2]) * 60_000,
  );
}

/** 每週場次的固定 ID，同一個季租同一天只會有一場。 */
function seasonEventId(groupId, seasonId, dateText) {
  return `${groupId}_${seasonId}_${dateText.replaceAll('-', '')}`;
}

module.exports = { datesToCreate, taipeiDateTime, taipeiToday, seasonEventId };
