# TapBook — iOS 自動記帳 App

支援 **繁體中文（香港用語）** 及 **English** 的原生 SwiftUI iOS 記帳 App，配合 iOS「捷徑自動化」實現 **Apple Wallet 拍卡背景自動記帳**，並為 **八達通（Octopus）** 提供一鍵快記及 Siri 語音記帳。

## 主要功能

- **Apple Wallet 自動記帳（App Intents）**：透過 iOS「捷徑」交易自動化，每次使用 Apple Pay（Visa / Mastercard 等）拍卡後，背景自動寫入金額、商戶、配對卡片並自動分類，同時發出本地通知確認。
- **香港常見商戶自動分類**：內置 60+ 條香港商戶規則（大家樂、大快活、美心、麥當勞、譚仔、壽司郎、7-Eleven、OK 便利店、百佳、惠康、Donki、MTR、九巴、Starbucks、Foodpanda、Keeta 等），並可自由增刪。
- **八達通快記方案**：首頁橫向一鍵快記按鈕（八達通搭港鐵、巴士、便利店、午餐等）＋ Siri 語音記帳（「用 TapBook 記帳」）。
- **消費統計圖表**：按月切換、Swift Charts 圓餅圖分析分類佔比、條狀圖比較各張卡片支出。
- **多帳戶管理**：預設 Visa、Mastercard、八達通、現金，可自訂 Apple Wallet 配對關鍵字。
- **雙語即時切換**：設定頁可即時切換「繁體中文（香港）」、「English」或「跟隨系統」。
- **CSV 匯出**：一鍵匯出所有消費紀錄。

## 如何在 Xcode 開啟及執行

1. 雙擊開啟 `TapBook.xcodeproj`
2. 在 Signing & Capabilities 選擇你的 Apple ID / Team（免費 Apple ID 亦可直接裝落自己部 iPhone 測試）
3. 揀選 Simulator 或實體 iPhone，按 `⌘R` 執行
4. 想喺 Simulator 立即試自動記帳：去 **設定 → 測試模擬 Apple Pay 拍卡記帳**

## 在 iPhone 設定 Apple Wallet 自動記帳

1. 打開 iPhone 內置 **「捷徑」（Shortcuts）** App → **自動化** → 按 **＋**
2. 揀選 **「交易」（Transaction）** → 勾選你嘅 Visa / Mastercard → 揀選 **「立即執行」**
3. 新增空白自動化 → 搜尋 **TapBook** → 揀選 **「記錄 Apple Wallet 交易」**
4. 填入 3 個變數：
   - **金額** → 捷徑輸入（金額）
   - **商戶** → 捷徑輸入（商戶）
   - **卡片或帳戶** → 捷徑輸入（卡或票證）
5. 完成！之後每次拍卡都會喺背景自動記帳。
