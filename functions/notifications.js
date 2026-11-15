// 判斷資料變動要發出哪些通知。不碰資料庫，方便單獨測試。

/** 場次標題：有活動名稱用活動名稱，否則用球館名稱。 */
const eventTitle = (event) => (event?.title || event?.venue || '場次');

/**
 * 報名資料變動：候補轉正取時通知本人。
 * @returns {{type: string, title: string, body: string} | null}
 */
function participantChangeNotice(before, after, event) {
  if (before?.status === 'waitlisted' && after?.status === 'attending') {
    return {
      type: 'promoted',
      title: '候補遞補成功',
      body: `你已從候補轉為正取：${eventTitle(event)}`,
    };
  }
  return null;
}

/**
 * 場次文件變動：取消、主揪更新資訊、主揪確定費用時通知報名者。
 * 同一次變動只發一則，取消優先。
 * @returns {{type: string, title: string, body: string, attendingOnly?: boolean} | null}
 */
function eventChangeNotice(before, after) {
  if (!before || !after) return null;
  const title = eventTitle(after);
  if (before.status !== 2 && after.status === 2) {
    return { type: 'cancelled', title: '場次已取消', body: `主揪取消了場次：${title}` };
  }
  const millis = (value) => (value && typeof value.toMillis === 'function' ? value.toMillis() : null);
  if (millis(after.costConfirmedAt) !== null && millis(before.costConfirmedAt) !== millis(after.costConfirmedAt)) {
    return {
      type: 'costConfirmed',
      title: '費用已確定',
      body: `${title}：每人 ${after.finalCostPerPerson} 元`,
      attendingOnly: true,
    };
  }
  if (millis(after.updatedAt) !== null && millis(before.updatedAt) !== millis(after.updatedAt)) {
    return { type: 'updated', title: '場次資訊已更新', body: `主揪更新了場次：${title}，請確認時間、地點與費用` };
  }
  return null;
}

/** 被主揪或管理者移出名單。 */
function removedNotice(event) {
  return { type: 'removed', title: '你已被移出名單', body: `你已被移出場次：${eventTitle(event)}` };
}

/** 有人申請加入球隊：通知隊長。 */
function joinRequestNotice(group, applicantName) {
  return {
    type: 'joinRequest',
    title: '新的入隊申請',
    body: `${applicantName || '有球友'} 申請加入 ${group?.name || '你的球隊'}`,
  };
}

/** 隊長審核結果：通知申請人。 */
function joinReviewedNotice(group, approved) {
  const name = group?.name || '球隊';
  return approved
    ? { type: 'joinApproved', title: '入隊申請已核准', body: `歡迎加入 ${name}！` }
    : { type: 'joinRejected', title: '入隊申請未通過', body: `${name} 這次沒有核准你的申請` };
}

module.exports = {
  participantChangeNotice,
  eventChangeNotice,
  removedNotice,
  joinRequestNotice,
  joinReviewedNotice,
  eventTitle,
};
