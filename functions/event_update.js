// 主揪編輯場次的驗證與遞補計算。不碰資料庫，方便單獨測試。

const SPORTS = ['basketball', 'badminton'];
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
    sport, district, venue, description, startTime, endTime,
    cost, costMode, organizerPlaying, existingPlayers, maxPlayers,
  } = input;

  if (!SPORTS.includes(sport)) invalid('運動類型無效。');
  if (!isTrimmedNonEmpty(district)) invalid('請輸入地區。');
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
      sport, district, venue, description, cost, costMode,
      organizerPlaying, existingPlayers, maxPlayers,
    },
    startTime: new Date(startTime),
    endTime: new Date(endTime),
    promote: Math.min(waitlistCount, openSpots),
  };
}

module.exports = { planEventUpdate, EventUpdateError };
