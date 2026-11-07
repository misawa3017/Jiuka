# Google 單一登入設定與驗證

Web 與 iOS 僅支援 Google；Email 是個人資料，不提供密碼登入。

## Firebase 專案設定（目前尚未執行）

本目錄沒有 Firebase 專案識別與有效平台設定，不能確認雲端供應商狀態。

1. 確認開發／測試 Firebase 專案，在 Authentication 啟用 Google 並設定支援信箱，停用 Email/Password 與其他登入供應商。
2. 先盤點既有帳號的 UID、供應商與 Firestore users 文件關聯，不刪除或自行合併。Firebase 對可信任 Google 身分可能自動轉換同 Email 的舊帳號供應商，測試前須確認舊帳號處理方式；本程式不呼叫帳號連結或依 Email 合併資料。
   App 偵測到僅有舊密碼供應商的本機工作階段時會登出；若使用者改以 Google 登入，Firebase 帳號是否沿用舊 UID 仍需在測試專案確認。
3. 加入實際 Web 網域至 Authorized domains；本機測試亦須確認 localhost 已授權。
4. 建立 Firebase Web App，從其設定取得下列值。
5. 確認 Firestore 規則允許 Google 使用者讀取／建立自己的 users/{uid} 文件及更新暱稱；其他資料授權須沿用完整產品規則。不要為了測試開放全資料庫。

```powershell
flutter run -d chrome --dart-define=FIREBASE_API_KEY=YOUR_WEB_API_KEY --dart-define=FIREBASE_APP_ID=YOUR_APP_ID --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID --dart-define=FIREBASE_AUTH_DOMAIN=YOUR_PROJECT.firebaseapp.com
```

正式 Web build 亦需傳入相同參數；不要放入服務帳號、私鑰或 OAuth client secret。缺少參數時啟動會明確報錯。

## iOS 第二階段

程式已接入 google_sign_in 與 Firebase credential 交換；實機登入尚未驗證。需使用對應 Bundle ID 的 GoogleService-Info.plist，完成 Google Sign-In 所需的 iOS client ID／URL scheme 配置，再以測試專案驗證。此工作不等同 iOS 已可上架。

## 測試

- flutter test：使用 Firebase 替身驗證首次建立、保留暱稱、取消重試、讀寫失敗、恢復工作階段、舊密碼工作階段限制與安全返回位置。
- flutter test integration_test/google_login_test.dart -d <device-id>：以替身驗證登入頁、場次路由與登出串接，不會存取正式資料或真正開啟 OAuth 視窗。
- 真實 Web 驗證：使用測試 Firebase 專案，以新 Google 帳號登入，修改暱稱、登出再登入、重新整理場次網址，確認 UID 與暱稱不變；取消視窗、阻擋視窗及斷網後能重試。
- 真實規則驗證：確認未授權帳號不能修改他人的 users 文件；此處隔離測試無法代替規則與真實 OAuth 驗證。

參考：https://firebase.google.com/docs/auth/flutter/federated-auth
