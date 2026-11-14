// 主揪編輯場次的驗證與遞補計算。不碰資料庫，方便單獨測試。

const SPORTS = ['basketball', 'badminton'];
/** 球友自行取消的期限：開始前幾小時；0 表示不限。 */
const CANCEL_DEADLINES = [0, 2, 6, 24];
const COST_MODES = ['perPerson', 'totalVenue'];

class EventUpdateError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const isTrimmed = (value) => typeof value === 'string' && value === value.trim();
const isTrimmedNonEmpty = (value) => isTrimmed(value) && value.length > 0;
const isNonNegativeInt = (value) => Number.isInteger(value) && value >= 0;

/**
 * 檢查主揪送來的新場次資料，並算出要遞補幾位候補。
 *
 * @param {object} current 目前的場次文件（attendeeCount、waitlistCount 等）
 * @param {object} input 主揪送來的欄位；時間以毫秒表示
 * @param {Date} now 目前時間
 * @returns {{ fields: object, startTime: Date, endTime: Date, promote: number }}
 */
function planEventUpdate(current, input, now) {
  const invalid = (message) => {
    throw new EventUpdateError('invalid-argument', message);
  };
  if (!input || typeof input !== 'object') invalid('場次資料無效。');

  const {
    title, sport, city, district, venue, description, startTime, endTime,
    cost, costMode, organizerPlaying, existingPlayers, maxPlayers,
    cancelDeadlineHours,
  } = input;

  if (!isTrimmed(title) || title.length > 40) invalid('活動名稱最多 40 字。');
  if (!SPORTS.includes(sport)) invalid('運動類型無效。');
  if (!isTrimmedNonEmpty(city)) invalid('請選擇縣市。');
  // 與 Firestore 規則一致：地區全名以縣市開頭，後面接鄉鎮市區。
  if (!isTrimmedNonEmpty(district) || !district.startsWith(city) || district.length <= city.length) {
    invalid('請選擇鄉鎮市區。');
  }
  if (!isTrimmedNonEmpty(venue)) invalid('請輸入地點。');
  if (!isTrimmed(description)) invalid('補充說明格式無效。');
  if (!Number.isInteger(startTime) || !Number.isInteger(endTime)) {
    invalid('時間格式無效。');
  }
  if (startTime <= now.getTime()) invalid('開始時間必須在未來。');
  if (endTime <= startTime) invalid('結束時間必須晚於開始時間。');
  if (!isNonNegativeInt(cost)) invalid('費用必須是 0 以上的整數。');
  if (!COST_MODES.includes(costMode)) invalid('費用方式無效。');
  if (typeof organizerPlaying !== 'boolean') invalid('主揪是否上場的設定無效。');
  if (!isNonNegativeInt(existingPlayers)) invalid('已約人數無效。');
  if (organizerPlaying && existingPlayers < 1) invalid('主揪上場時已約人數至少為 1。');
  if (!Number.isInteger(maxPlayers) || maxPlayers < 2) invalid('總名額至少 2 人。');
  if (!CANCEL_DEADLINES.includes(cancelDeadlineHours)) invalid('取消期限無效。');

  const attendeeCount = current.attendeeCount ?? 0;
  const waitlistCount = current.waitlistCount ?? 0;
  if (existingPlayers + attendeeCount > maxPlayers) {
    throw new EventUpdateError(
      'failed-precondition',
      `目前已有 ${attendeeCount} 位正取球友，總名額至少要 ${existingPlayers + attendeeCount} 人。`,
    );
  }

  const openSpots = maxPlayers - existingPlayers - attendeeCount;
  return {
    fields: {
      title, sport, city, district, venue, description, cost, costMode,
      organizerPlaying, existingPlayers, maxPlayers, cancelDeadlineHours,
    },
    startTime: new Date(startTime),
    endTime: new Date(endTime),
    // 有空位且有人候補時才需要查候補名單；實際遞補誰由 pickPromotions 決定。
    openSpots: waitlistCount > 0 ? openSpots : 0,
  };
}

/** 一組報名的人數：本人＋同行朋友（舊資料沒有 guests 視為 0）。 */
const partySize = (participant) => 1 + (Number.isInteger(participant?.guests) ? participant.guests : 0);

/**
 * 依報名順序遞補候補：整組一起上，排在最前面的那組放不下就停止，
 * 後面的組別不能插隊（嚴格先到先得）。
 * @param {{id: string, party: number}[]} queue 依報名順序排好的候補
 * @param {number} openSpots 目前空出的名額
 * @returns {{ids: string[], people: number}}
 */
function pickPromotions(queue, openSpots) {
  const ids = [];
  let people = 0;
  for (const entry of queue) {
    if (people + entry.party > openSpots) break;
    ids.push(entry.id);
    people += entry.party;
  }
  return { ids, people };
}

/** 正取球友是否已超過自行取消的期限（候補不受限）。 */
function isPastCancelDeadline(event, now) {
  const hours = event.cancelDeadlineHours ?? 0;
  if (!hours) return false;
  return now.getTime() > event.startTime.toMillis() - hours * 3_600_000;
}

module.exports = {
  planEventUpdate,
  isPastCancelDeadline,
  pickPromotions,
  partySize,
  EventUpdateError,
  CANCEL_DEADLINES,
};
