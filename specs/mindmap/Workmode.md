---
fact-sources:
  application-code:
    - Dayflow/Dayflow/App
    - Dayflow/Dayflow/Core
    - Dayflow/Dayflow/Models
    - Dayflow/Dayflow/System
    - Dayflow/Dayflow/Menu
    - Dayflow/Dayflow/Views
    - Dayflow/Dayflow/Utilities
    - tools/dayflow-cli/Sources/dayflow
  database-ddl:
    - Dayflow/Dayflow/Core/Recording/StorageManager.swift
    - Dayflow/Dayflow/Core/Recording/StorageManager+Migrations.swift
  tests:
    - Dayflow/DayflowTests
    - DayflowTests
  auxiliary:
    - README.md
    - Dayflow/Dayflow/AnalyticsEventDictionary.md
    - plugins/dayflow/skills
---

# Dayflow 規格 Workmode

## 目的與範圍

把 Dayflow（macOS 上自動產生工作日誌的 App）的規格與商業邏輯，依本 Project 使用的格式（`software-service`）的 layer 與文件位置呈現。

範圍：repository `benchen216/Dayflow` 的 macOS App 與隨附的 `dayflow` 命令列工具（含 MCP server）。外部服務（Gemini、ChatGPT／Claude 的命令列工具、Ollama／LM Studio、Dayflow 後端、PostHog、Sentry、Sparkle）只描述與本系統互動的邊界。

## 事實來源

程式碼是唯一事實來源。規格描述程式碼實際做了什麼。

| 來源 | 地位 | 用途 |
|---|---|---|
| 應用程式原始碼 | 事實 | 行為、條件、狀態轉換、錯誤回應 |
| SQLite DDL（StorageManager 內的 CREATE／ALTER） | 事實（資料庫層） | ORM 未表達的約束 |
| 測試 | 輔助 | 理解意圖、Example 素材 |
| README、AnalyticsEventDictionary、plugins 的 skills | 輔助 | 業務用語與背景 |

程式碼出處只寫在格式規定的位置（frontmatter 或擴充欄位），路徑從 repository 根目錄起算。

過大未收錄的檔案：`Dayflow/Dayflow/Localizable.xcstrings`（1.9 MiB，多語系字串表）。只影響介面文案的翻譯，不影響行為規則。

## 規格樹

```text
功能/
├── [Problem]還原一天的工作              核心問題（還原困難、分心難察覺、隱私）
├── 錄製/
│   ├── [機制]螢幕錄製                     錄製狀態、擷取、隱私排除、失敗退避
│   ├── [功能]開始與停止錄製               選單列、主視窗、deep link
│   ├── [功能]暫停錄製
│   ├── [功能]設定擷取頻率與解析度
│   ├── [功能]設定不錄製的App
│   ├── [功能]⚙系統睡眠與鎖定時自動暫停      系統事件
│   └── [功能]⚙螢幕錄製權限遺失時停止錄製
├── AI分析/
│   ├── [機制]分析批次與活動卡片
│   ├── [功能]⚙定時分析新的錄製            每 60 秒
│   ├── [功能]重試失敗的時段
│   ├── [功能]重新處理某一天
│   └── [功能]設定AI供應商
├── 時間軸/
│   ├── [機制]時間軸                       一天的範圍、卡片內容、評分
│   └── [功能]瀏覽時間軸、修改卡片、刪除卡片、評分時段、匯出與複製時間軸
├── 分類/
│   ├── [機制]分類
│   └── [功能]新增、修改、刪除分類、調整分類順序
├── 每日目標/
│   ├── [機制]每日目標
│   └── [功能]設定每日目標、查看每日目標進度
├── Daily站會/
│   ├── [機制]Daily站會
│   ├── [功能]解鎖Daily、查看與編輯Daily站會
│   ├── [功能]⚙自動產生Daily站會              每 5 分鐘
│   └── [功能]⚙產生Daily brief                限量開放
├── 週報/       [功能]解鎖週報、查看週報
├── Chat/       [功能]與工作日誌對話、管理對話紀錄
├── Agent存取/
│   ├── [機制]Agent存取
│   └── [功能]以命令列或MCP查詢工作日誌、透過Agent修改分類、透過Agent修改或刪除活動、透過Agent設定每日目標、設定Agent存取
├── 儲存與資料維護/  [功能]設定儲存上限、⚙依容量上限清除錄影（每小時）、⚙資料庫備份與損毀還原
├── 帳號與方案/
│   ├── [機制]Dayflow帳號與方案
│   └── [功能]登入與登出Dayflow帳號、購買與管理方案、兌換與分享推薦碼
├── Flow專注夥伴/  [功能]取得Flow使用資格、進行Flow專注時段
└── 其他/        [功能]完成新手引導、⚙發送系統通知、回答App內問卷、使用分析與錯誤回報
介面/
├── components.yaml                     x-auth 詞彙、排程、啟動任務、事件
└── Dayflow.yaml                        Agent 寫入通道（本機 socket）
實體&關聯/
└── 錄製與分析.dbml、時間軸.dbml、Daily與每日目標.dbml、Chat.dbml
```

⚙ 表示自動觸發（排程、啟動掃描、事件 listener）。分類與偏好設定存在 App 的偏好設定中，不在資料庫，因此沒有 DBML。

## 已確認的慣例

- 「一天」以早上 4:00 為分界（凌晨 0:00–3:59 屬於前一天）。

## 協作方式

1. 一次深化一個業務領域：先讀該領域的程式碼，再寫功能與規則。
2. 已從程式碼確認的內容直接寫入；不確定的地方以問卷題目提問，答完後寫進規格；規格內文不留 clarify note。
3. 每輪至多五個問題，每題只處理一個決策。
4. 拆檔、合檔、改名、新增分類層，先取得確認。
5. 更新規格時，同輪核對 API、DBML 與引用是否一致。

## 下一步

1. 依[修正清單](<修正清單.md>)修正程式：使用分析不送內容、Agent 找不到活動時回報 not_found、分類改名一併更新卡片。
2. Daily brief 把畫面另存複本、不受錄影容量上限管理，若要改變可於後續 Plan 討論。
