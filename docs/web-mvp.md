# Web 場次功能：本機實作與待接雲端設定

目前首頁是未來場次列表；訪客可瀏覽及分享場次，登入後可報名、取消與候補。「我的場次」分別列出使用者主揪、正取及候補的場次。主揪可發布不依附球隊的籃球／羽球場次，並填入已約好的球友人數。總名額包含主揪（若上場）、已約好的球友與 App 正取球友，不包含候補。

球隊成員頁目前只呈現成員總數及管理員本人。其他成員的暱稱尚未串接，因此不以假姓名代替；頁面也會限制只有管理員可進入。

費用可選每人固定價格或整場場租。整場場租頁面目前依已確定人數估算新球友加入後的每人金額，向上取整至整數元，明確標示為預估；報名人數改變後會重新估算。最終收費、退款與金額鎖定規則尚待產品決策，此版本沒有線上金流。地區以「縣市＋鄉鎮市區」兩層下拉選單選擇（22 縣市、368 鄉鎮市區，採正式「臺」字），場次存入縣市 `city` 與全名 `district`（例如「臺北市大安區」）；首頁可只選縣市篩選整個縣市，或再選鄉鎮市區。舊場次沒有 `city` 時由地區全名推算。場次與球隊活動清單每次最多載入 100 場，後續可補分頁。

Web 所需 Firebase 設定沿用 [Google 登入文件](google-sign-in.md)。Firestore `events` 查詢需要部署專案根目錄的 `firestore.indexes.json`，並等待索引建好。`firebase.json` 準備了 Firebase Hosting 的單頁應用程式重寫規則，讓 `/event/:id` 連結重新整理時仍進入 Flutter Web。尚未部署。

專案根目錄的 `firestore.rules` 已納入 `firebase.json`。公開場次文件只存正取／候補人數；每位參與者的 UID 與狀態存在 `/events/{eventId}/participants/{uid}`。本人可查詢自己的參與文件，主揪可查看該場名單。報名由 Firestore 原子交易寫入，退出與候補遞補由 asia-east1 的 callable Cloud Function `leaveEvent` 原子處理。使用者查詢「我的場次」需要部署參與者 collection-group 複合索引，場次瀏覽及球隊活動也需要 `firestore.indexes.json` 中列出的索引。

部署前須先把既有公開場次遷移：`node functions/migrate_event_rosters.js --project=YOUR_PROJECT_ID` 只會預覽；確認備份與預覽後，才以 `--apply --confirm-private-roster-migration` 寫入。遷移會保留名單 UID 與狀態，補齊缺少的參與文件欄位；若發現公開名單與既有私有文件的 UID 或狀態衝突，會停止該次遷移，不刪除舊名單。遷移成功後，以 `firebase deploy --project YOUR_PROJECT_ID --only firestore:rules,firestore:indexes,functions,hosting` 部署新版規則、索引、Functions 與 Web。正式資料需有 Firebase Admin Application Default Credentials；本機不可用 `demo-*` 專案執行遷移。未完成遷移前舊場次仍含公開 UID，且新版報名仰賴計數欄位，不能直接上線切換。遷移不會刪除或合併 Firebase Auth 帳號。

Firestore 規則可用 `npm ci --prefix .rules-test` 安裝測試套件，再以 `firebase emulators:exec --only firestore --project demo-jiuka-rules "node .rules-test/rules.test.cjs"` 在本地測試；Functions 依 `functions/package-lock.json` 安裝依賴後部署。部署前仍須在測試 Firebase 專案確認 Google 登入、查詢索引、Callable Function 與遞補流程。請勿在正式資料庫使用測試模式。規則對 collection-group 查詢的限制可參考 [Firebase 官方文件](https://firebase.google.com/docs/firestore/security/rules-query)。

本機 Flutter 與 Firestore 規則驗證需在本次資料模型變更後重新執行；尚未以真實 Firebase 專案、Google 帳號及已部署索引做端到端測試。

## 廣告設定

場次詳情與球隊活動頁支援 Web AdSense 響應式橫幅；iOS／Android 使用 AdMob 橫幅。沒有提供廣告 ID 時，Web 不載入第三方廣告腳本；行動版保留 Google 官方測試廣告 ID。建立並核准 AdSense／AdMob 帳戶、取得發布者及版位 ID 後，將下列 Dart define 加到正式 build 命令：

```sh
flutter build web \
  --dart-define=ADSENSE_CLIENT_ID=ca-pub-1234567890123456 \
  --dart-define=ADSENSE_BANNER_SLOT_ID=1234567890 \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=...
```

行動版 release build 另提供 `ADMOB_ANDROID_BANNER_ID` 或 `ADMOB_IOS_BANNER_ID`；正式上架前也要將 `AndroidManifest.xml` 的 `APPLICATION_ID` 與 `ios/Runner/Info.plist` 的 `GADApplicationIdentifier` 換成自己的 AdMob App ID。兩處目前都使用 Google 官方測試 App ID。先完成網站網域核准、AdSense 要求的 `ads.txt`，並按目標地區處理廣告同意設定；本機預覽與未核准網域不會產生實際營收。Google Mobile Ads Flutter 外掛不支援 Web，因此 Web 使用 AdSense 網頁版廣告碼；詳見[官方 AdSense 廣告碼格式](https://support.google.com/adsense/answer/12003870?hl=en)及[官方 Flutter AdMob 平台支援說明](https://developers.google.com/admob/flutter/quick-start?authuser=9)。
