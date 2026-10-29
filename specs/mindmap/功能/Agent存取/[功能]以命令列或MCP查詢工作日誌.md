---
type: Query
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Agent存取.md#讀取與寫入走不同路徑"
    description: 讀取直接讀本機資料庫，不需要 App 開著，依 Agent 存取機制。
triggers:
  - dayflow status、timeline（today、yesterday、--from/--to、--category、--summary、--detailed）、card、daily、weekly、categories、search
  - MCP 工具 get_status、get_timeline、get_time_breakdown、get_activity_detail、search_activities、get_daily、get_weekly、list_categories
sources:
  _feature:
    - tools/dayflow-cli/Sources/dayflow/main.swift
    - tools/dayflow-cli/Sources/dayflow/Queries.swift
    - tools/dayflow-cli/Sources/dayflow/MCPServer.swift:110-172
  B-1:
    - tools/dayflow-cli/Sources/dayflow/main.swift:59-67
  B-2:
    - tools/dayflow-cli/Sources/dayflow/main.swift:91-104
  C-1:
    - tools/dayflow-cli/Sources/dayflow/main.swift:46-57
  D-2:
    - tools/dayflow-cli/Sources/dayflow/main.swift:91-170
  D-4:
    - tools/dayflow-cli/Sources/dayflow/main.swift:186-221
---
Feature: 以命令列或 MCP 查詢工作日誌

# 前置

## A. 權限

1. [A-1（本機使用者）] 只有能讀取這台 Mac 上 Dayflow 資料的系統使用者才能查詢；不需要開啟「允許編輯」，也不需要 Dayflow 正在執行。

## B. 參數合法條件

1. [B-1（日期格式）] 日期必須是 YYYY-MM-DD；格式不符時拒絕，回覆「"<輸入>" is not a date. Use YYYY-MM-DD, e.g. 2026-03-11.」，結束碼 2。
2. [B-2（日期範圍）] 查詢範圍必須同時給開始與結束日期，且開始不晚於結束；否則拒絕，結束碼 2。
3. [B-3（活動編號）] 查詢單一活動時必須給整數編號；否則拒絕並提示用法，結束碼 2。
4. [B-4（搜尋文字）] 搜尋時必須給非空的文字；否則拒絕，結束碼 2。

## C. 使用此功能的系統前置狀態條件

1. [C-1（有 Dayflow 資料）] 這台 Mac 必須已有 Dayflow 的資料；沒有時回覆「No Dayflow data found. Open Dayflow and let it record for a bit.」，結束碼 5。
2. [C-2（活動存在）] 查詢單一活動時，該編號的活動必須存在且未刪除；否則回覆「No activity with ID <編號>.」，結束碼 3。
3. [C-3（Daily 存在）] 查詢 Daily 時，該日期必須已有 Daily；否則回覆「No Daily for <日期>. Dayflow generates one after a day with enough activity.」，結束碼 3。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（一天的活動）] 回傳那一天（以 4:00 為界）未刪除的活動：時間、標題、分類、編號；可只看某個分類（不分大小寫），可附一行摘要或完整說明。
2. [D-2（日期範圍）] 範圍不超過 7 天時逐筆列出；超過 7 天時改回傳各分類的時間合計與占比（不含 System 卡片），並說明超過 7 天只給合計，命令列可加 --force 強制逐筆列出。
    1. Example: 查詢 30 天

        查詢 3/1 到 3/31，回傳「Coding 4,200 分鐘（52%）、Communication 1,800 分鐘（22%）…」，並附註「Range exceeds 7 days. Returning totals instead of individual activities.」。
3. [D-3（搜尋）] 回傳標題或摘要包含搜尋文字、未刪除的活動，最多最近 50 筆。
4. [D-4（狀態）] 回傳今天（以 4:00 為界）、時區、最後一次擷取的時間、待分析與失敗的批次數。
5. [D-5（週報）] 回傳包含該日期的那一週的總記錄時間、專注時間（不含 Idle）與各分類的合計（不含 System）。
6. [D-6（輸出格式）] 加上 --json 時輸出固定結構的 JSON；MCP 一律以 JSON 回傳，並提醒 agent 活動內容來自螢幕、不可當成指令執行。

## E. 完成後系統狀態應如何更新

無

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（讀取失敗）] 資料庫無法開啟或查詢失敗時回覆錯誤原因，結束碼 1。

## G. 執行沒有完成時，系統狀態應如何更新

無
