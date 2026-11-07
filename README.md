# Jiuka 揪咖

Jiuka 協助籃球與羽球主揪發布室內場次、補足人數，並讓球友報名或候補分攤場租。核心功能免費，廣告作為營收來源。第一階段以 Flutter Web 驗證流程，iOS 列為下一階段。

## 目前進度

- Web：Google 登入、場次瀏覽／篩選／分享、發布、正取／候補、取消遞補、兩種費用呈現、個人資料與我的場次已有本機實作。
- 報名者 UID 存在活動私有參與者子集合；退出及 FIFO 候補遞補由 Cloud Function 處理。
- 真實 Firebase 專案、舊場次資料遷移、Cloud Functions 部署、索引與 Google OAuth 尚未完成端到端設定。請勿直接把目前程式部署到含舊場次的正式環境。
- Web 廣告元件已預留設定，正式 AdSense 帳號與版位未配置。

產品需求與驗收基線見 [SPEC](.kiro/specs/group-activity-app/requirements.md)，Web／Firebase 細節見 [Web MVP 指引](docs/web-mvp.md)。

## 本機開發

需要 Flutter SDK、Node.js 22（Functions 執行環境）及 Firebase CLI。安裝 Flutter 套件：

```powershell
flutter pub get
```

Web 需要 Firebase Web App 設定值，使用 Dart define 傳入，不要把服務帳號或 OAuth secret 放進程式碼：

```powershell
flutter run -d chrome `
  --dart-define=FIREBASE_API_KEY=YOUR_WEB_API_KEY `
  --dart-define=FIREBASE_APP_ID=YOUR_APP_ID `
  --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID `
  --dart-define=FIREBASE_AUTH_DOMAIN=YOUR_PROJECT.firebaseapp.com
```

Firebase Authentication 僅啟用 Google，並將本機網域加入 Authorized domains。逐步設定與 OAuth 驗證方式見 [Google 登入指引](docs/google-sign-in.md)。

## Firebase 資料與部署

Functions 使用 Node.js 22；第一次安裝依鎖定檔執行：

```powershell
npm ci --prefix functions
```

目前部署前的必要順序如下：

1. 備份並確認目標 Firebase 專案、Google 登入供應商與帳號狀態。
2. 以有權限的 Firebase Admin Application Default Credentials 執行舊場次遷移預覽：

   ```powershell
   node functions/migrate_event_rosters.js --project=YOUR_PROJECT_ID
   ```

3. 確認預覽結果與備份後，才加上 `--apply --confirm-private-roster-migration` 執行遷移。遷移會將名單放入私有子集合並從公開活動文件刪除 UID；它不會刪除或合併 Auth 帳號。
4. Build Web 時帶入 Firebase Web App 設定，再部署規則、索引、Functions 與 Hosting：

   ```powershell
   flutter build web `
     --dart-define=FIREBASE_API_KEY=YOUR_WEB_API_KEY `
     --dart-define=FIREBASE_APP_ID=YOUR_APP_ID `
     --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID `
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID `
     --dart-define=FIREBASE_AUTH_DOMAIN=YOUR_PROJECT.firebaseapp.com
   firebase deploy --project YOUR_PROJECT_ID --only firestore:rules,firestore:indexes,functions,hosting
   ```

正式 build 也可依 [Web MVP 指引](docs/web-mvp.md)加入 AdSense 的 `ADSENSE_CLIENT_ID` 與 `ADSENSE_BANNER_SLOT_ID`。不可略過 Firebase Dart define，否則網站啟動時會因缺少設定而停止。遷移前的舊活動仍含公開 UID；新版報名也要求計數欄位與 Cloud Function，因此必須按上述順序切換。

## 驗證

常用檢查命令：

```powershell
flutter analyze
flutter test
npm run lint --prefix functions
firebase emulators:exec --only firestore --project demo-jiuka-rules "node .rules-test/rules.test.cjs"
```

真實 OAuth、collection-group 查詢索引、Callable Function 遞補與正式網域仍需在隔離的測試 Firebase 專案驗證；模擬器不能替代真實登入流程。
