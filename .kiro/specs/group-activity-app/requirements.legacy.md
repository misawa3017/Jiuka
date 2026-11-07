# 需求文件

## 簡介

本系統是一個社交活動組織平台，讓使用者能夠建立和參加各種興趣活動團體，包括運動、出遊和社交聚會。系統透過廣告收益來維持免費服務，為使用者提供尋找志同道合夥伴的平台。

## 術語表

- **系統 (System)**: 指本社交活動組織平台的完整應用程式
- **使用者 (User)**: 註冊並使用本平台的個人用戶
- **活動 (Activity)**: 使用者建立的團體活動，包含時間、地點、類型等資訊
- **團長 (Organizer)**: 建立活動的使用者
- **參與者 (Participant)**: 報名參加活動的使用者
- **活動類型 (Activity Type)**: 活動的分類，如運動、出遊、交友等
- **廣告單元 (Ad Unit)**: 在應用程式中顯示的廣告內容區塊
- **興趣標籤 (Interest Tag)**: 用於描述活動或使用者興趣的關鍵字標籤
- **Firebase Authentication**: Google 提供的身份驗證服務
- **Firestore**: Google 提供的 NoSQL 雲端資料庫服務
- **FCM (Firebase Cloud Messaging)**: Google 提供的跨平台訊息推送服務
- **Firebase 使用者 ID (Firebase User ID)**: Firebase Authentication 為每個使用者產生的唯一識別碼

## 需求

### 需求 1

**使用者故事:** 作為一個新使用者，我想要註冊帳號並建立個人檔案，以便我可以開始使用平台的功能

#### 驗收標準

1. WHEN 使用者提供有效的電子郵件地址和密碼 THEN 系統 SHALL 使用 Firebase Authentication 建立新的使用者帳號
2. WHEN Firebase Authentication 成功建立帳號 THEN 系統 SHALL 在 Firestore 中建立對應的使用者文件，使用 Firebase 使用者 ID 作為文件識別碼
3. WHEN 使用者完成註冊 THEN 系統 SHALL 要求使用者填寫基本個人資料，包括暱稱、興趣標籤和自我介紹
4. WHEN 使用者輸入的暱稱已被其他使用者使用 THEN 系統 SHALL 查詢 Firestore 驗證暱稱唯一性，若重複則拒絕該暱稱並提示使用者選擇其他暱稱
5. WHEN 使用者選擇至少一個興趣標籤 THEN 系統 SHALL 將該興趣標籤儲存到 Firestore 的使用者文件中
6. WHEN 使用者完成個人檔案設定 THEN 系統 SHALL 更新 Firestore 中的使用者文件並允許使用者存取平台的所有功能

### 需求 2

**使用者故事:** 作為一個團長，我想要建立新的活動，以便我可以招募志同道合的參與者

#### 驗收標準

1. WHEN 使用者點擊建立活動按鈕 THEN 系統 SHALL 顯示活動建立表單
2. WHEN 使用者填寫活動標題、描述、活動類型、日期、時間、地點和人數上限 THEN 系統 SHALL 驗證所有必填欄位已完成
3. WHEN 活動日期設定為過去的時間 THEN 系統 SHALL 拒絕該日期並顯示錯誤訊息
4. WHEN 人數上限設定為小於 2 的數值 THEN 系統 SHALL 拒絕該數值並要求至少 2 人
5. WHEN 所有活動資訊驗證通過 THEN 系統 SHALL 在 Firestore 的 activities 集合中建立新的活動文件，包含團長的 Firebase 使用者 ID
6. WHEN 活動在 Firestore 中建立成功 THEN 系統 SHALL 將團長的 Firebase 使用者 ID 加入該活動的參與者陣列
7. WHEN 活動資料寫入 Firestore 完成 THEN 系統 SHALL 將活動發布到活動列表供其他使用者瀏覽

### 需求 3

**使用者故事:** 作為一個使用者，我想要瀏覽和搜尋活動，以便我可以找到感興趣的活動參加

#### 驗收標準

1. WHEN 使用者開啟活動列表頁面 THEN 系統 SHALL 從 Firestore 查詢所有未來的活動，按照日期由近到遠排序
2. WHEN 使用者選擇特定活動類型篩選 THEN 系統 SHALL 使用 Firestore 查詢條件只顯示符合該活動類型的活動
3. WHEN 使用者輸入關鍵字搜尋 THEN 系統 SHALL 從 Firestore 查詢標題或描述包含該關鍵字的活動
4. WHEN 使用者選擇興趣標籤篩選 THEN 系統 SHALL 使用 Firestore 陣列查詢顯示包含該興趣標籤的活動
5. WHEN 使用者點擊活動項目 THEN 系統 SHALL 從 Firestore 讀取該活動文件和相關的使用者文件，顯示完整詳細資訊，包括團長資訊、當前參與者列表和剩餘名額

### 需求 4

**使用者故事:** 作為一個使用者，我想要報名參加活動，以便我可以加入感興趣的團體

#### 驗收標準

1. WHEN 使用者在活動詳情頁面點擊報名按鈕 THEN 系統 SHALL 從 Firestore 讀取活動文件檢查是否已額滿
2. WHEN 活動尚有名額且使用者尚未報名 THEN 系統 SHALL 使用 Firestore 交易將使用者的 Firebase 使用者 ID 加入活動的參與者陣列
3. WHEN 活動已額滿 THEN 系統 SHALL 拒絕報名並顯示活動已額滿訊息
4. WHEN 使用者已經報名該活動 THEN 系統 SHALL 顯示已報名狀態並提供取消報名選項
5. WHEN 使用者成功報名且 Firestore 更新完成 THEN 系統 SHALL 使用 FCM 發送確認通知給使用者和團長

### 需求 5

**使用者故事:** 作為一個參與者，我想要取消已報名的活動，以便我可以在計畫改變時退出活動

#### 驗收標準

1. WHEN 使用者在已報名的活動中點擊取消報名按鈕 THEN 系統 SHALL 顯示確認對話框
2. WHEN 使用者確認取消報名 THEN 系統 SHALL 使用 Firestore 交易將使用者的 Firebase 使用者 ID 從活動的參與者陣列中移除
3. WHEN 活動開始時間距離當前時間少於 24 小時 THEN 系統 SHALL 警告使用者臨時取消可能影響其他參與者
4. WHEN 取消報名的使用者是團長 THEN 系統 SHALL 拒絕取消並提示團長必須先取消整個活動
5. WHEN 取消報名成功且 Firestore 更新完成 THEN 系統 SHALL 使用 FCM 通知團長有參與者退出

### 需求 6

**使用者故事:** 作為一個團長，我想要管理我建立的活動，以便我可以更新資訊或取消活動

#### 驗收標準

1. WHEN 團長檢視自己建立的活動 THEN 系統 SHALL 比對當前使用者的 Firebase 使用者 ID 與活動的團長 ID，若相符則顯示編輯和取消活動的選項
2. WHEN 團長修改活動資訊 THEN 系統 SHALL 驗證修改後的資訊符合建立活動的所有規則
3. WHEN 活動資訊驗證通過 THEN 系統 SHALL 更新 Firestore 中的活動文件
4. WHEN Firestore 中的活動文件更新成功 THEN 系統 SHALL 使用 FCM 通知所有已報名的參與者活動資訊已變更
5. WHEN 團長取消活動 THEN 系統 SHALL 顯示確認對話框說明將通知所有參與者
6. WHEN 團長確認取消活動 THEN 系統 SHALL 從 Firestore 刪除該活動文件並使用 FCM 通知所有參與者活動已取消

### 需求 7

**使用者故事:** 作為一個使用者，我想要查看我的活動歷史，以便我可以追蹤我參加過和建立過的活動

#### 驗收標準

1. WHEN 使用者開啟個人檔案頁面 THEN 系統 SHALL 顯示使用者建立的活動和參加的活動兩個分頁
2. WHEN 使用者檢視建立的活動分頁 THEN 系統 SHALL 從 Firestore 查詢團長 ID 等於當前使用者 Firebase 使用者 ID 的所有活動，包括進行中和已結束的活動
3. WHEN 使用者檢視參加的活動分頁 THEN 系統 SHALL 從 Firestore 查詢參與者陣列包含當前使用者 Firebase 使用者 ID 的所有活動，包括即將進行和已結束的活動
4. WHEN 活動已經結束 THEN 系統 SHALL 在活動項目上標示已結束狀態
5. WHEN 使用者點擊已結束的活動 THEN 系統 SHALL 從 Firestore 讀取該活動文件，顯示完整歷史記錄，包括最終參與者名單

### 需求 8

**使用者故事:** 作為平台營運者，我想要在應用程式中顯示廣告，以便透過廣告收益維持免費服務

#### 驗收標準

1. WHEN 使用者開啟活動列表頁面 THEN 系統 SHALL 在頁面頂部或底部顯示一個廣告單元
2. WHEN 使用者檢視活動詳情頁面 THEN 系統 SHALL 在內容區域適當位置顯示一個廣告單元
3. WHEN 廣告單元載入失敗 THEN 系統 SHALL 隱藏該廣告單元並保持頁面其他功能正常運作
4. WHEN 使用者與廣告互動 THEN 系統 SHALL 記錄廣告點擊事件用於統計分析
5. WHEN 使用者在應用程式中停留超過 30 秒 THEN 系統 SHALL 記錄廣告曝光事件用於統計分析

### 需求 9

**使用者故事:** 作為一個使用者，我想要接收活動相關通知，以便我可以及時了解活動狀態變化

#### 驗收標準

1. WHEN 使用者首次安裝應用程式 THEN 系統 SHALL 請求通知權限並將 FCM 裝置權杖儲存到 Firestore 的使用者文件中
2. WHEN 使用者報名的活動資訊被團長更新 THEN 系統 SHALL 使用 FCM 發送通知給該使用者的所有已註冊裝置
3. WHEN 使用者建立的活動有新的參與者報名 THEN 系統 SHALL 使用 FCM 發送通知給團長的所有已註冊裝置
4. WHEN 使用者報名的活動即將在 24 小時內開始 THEN 系統 SHALL 使用 FCM 發送提醒通知給該使用者的所有已註冊裝置
5. WHEN 使用者報名的活動被團長取消 THEN 系統 SHALL 使用 FCM 立即發送通知給該使用者的所有已註冊裝置
6. WHEN 使用者開啟通知設定頁面 THEN 系統 SHALL 從 Firestore 讀取使用者的通知偏好設定，並允許使用者選擇接收或關閉各類型通知
7. WHEN 使用者更新通知偏好設定 THEN 系統 SHALL 將新的設定儲存到 Firestore 的使用者文件中

### 需求 10

**使用者故事:** 作為一個使用者，我想要根據我的興趣標籤獲得個人化推薦，以便我可以更容易找到適合的活動

#### 驗收標準

1. WHEN 使用者開啟推薦頁面 THEN 系統 SHALL 從 Firestore 讀取使用者的興趣標籤，並查詢包含相同興趣標籤的活動
2. WHEN 使用者的興趣標籤與活動的興趣標籤匹配 THEN 系統 SHALL 將該活動的推薦優先度提高
3. WHEN 使用者參加過某類型的活動 THEN 系統 SHALL 從 Firestore 查詢使用者的活動歷史，增加推薦相同類型活動的權重
4. WHEN 推薦列表中沒有符合使用者興趣的活動 THEN 系統 SHALL 從 Firestore 查詢參與者數量最多的活動作為熱門活動替代推薦
5. WHEN 使用者更新興趣標籤並儲存到 Firestore THEN 系統 SHALL 立即重新查詢並更新推薦列表以反映新的興趣偏好

### 需求 11

**使用者故事:** 作為系統管理員，我想要確保 Firebase 服務正確整合和配置，以便系統能夠穩定運行並保護使用者資料

#### 驗收標準

1. WHEN 系統初始化 THEN 系統 SHALL 使用有效的 Firebase 配置金鑰連接到 Firebase 專案
2. WHEN 使用者進行任何需要身份驗證的操作 THEN 系統 SHALL 驗證使用者的 Firebase Authentication 狀態
3. WHEN 系統存取 Firestore 資料 THEN 系統 SHALL 遵守 Firestore 安全規則，確保使用者只能存取和修改自己有權限的資料
4. WHEN 系統發送 FCM 通知 THEN 系統 SHALL 使用伺服器端的 Firebase Admin SDK 確保通知安全發送
5. WHEN Firestore 連線失敗或逾時 THEN 系統 SHALL 顯示適當的錯誤訊息並提供重試選項
6. WHEN 使用者登出 THEN 系統 SHALL 清除本地的 Firebase Authentication 狀態和快取資料
