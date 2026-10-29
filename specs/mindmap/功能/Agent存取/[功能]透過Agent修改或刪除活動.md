---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Agent存取.md#寫入的開關"
    description: 開關、寫入通道與破壞性確認依 Agent 存取機制。
triggers:
  - dayflow timeline update <編號> --title / --category
  - dayflow timeline delete <編號>
  - MCP 工具 update_activity、delete_activity
  - 寫入通道操作 activity_update、activity_delete
sources:
  _feature:
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift:149-216
    - tools/dayflow-cli/Sources/dayflow/WriteCommands.swift:114-141
  B-2:
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift:168-199
  E-1:
    - Dayflow/Dayflow/Core/Recording/StorageManager+TimelineCards.swift:265-281
  E-2:
    - Dayflow/Dayflow/Core/Recording/StorageManager+TimelineCards.swift:187-247
---
Feature: 透過 Agent 修改或刪除活動

# 前置

## A. 權限

1. [A-1（允許編輯）] 「允許編輯」必須開啟；否則回覆 edits_disabled，命令列結束碼 4，活動不變。
2. [A-2（App 必須在執行）] Dayflow App 必須正在執行；否則回覆 app_not_running，命令列結束碼 5，活動不變。

## B. 參數合法條件

1. [B-1（活動編號）] 必須給整數的活動編號；否則回覆 invalid_argument「record_id is required.」。
2. [B-2（修改的內容）] 修改時至少要有標題（去掉前後空白後非空白）或分類其中之一；否則回覆 invalid_argument「Nothing to change. Pass title and/or category.」。給了分類時必須找得到唯一的分類（不分大小寫），找不到回覆 not_found、找到多個回覆 ambiguous；分類檢查在寫入前完成，任一項不合法時都不寫入。
3. [B-3（刪除需要確認）] 命令列刪除時須在互動終端機回答 y，或加上 --yes；否則取消或拒絕，活動不變。

## C. 使用此功能的系統前置狀態條件

1. [C-1（活動存在且未刪除）] 在參數合法後，該編號的活動必須存在且尚未刪除；否則拒絕，回覆 not_found「No activity with ID <編號>.」，任何活動、觀察與縮時影片都不變。程式目前不檢查且一律回報成功，見[修正清單](<../../修正清單.md>) 第 2 項。
    1. Example: 編號打錯

        活動 214 已在昨天刪除。agent 呼叫 update_activity(record_id: 214, title: "寫週報")，得到 not_found；資料庫中 214 的標題不變。接著呼叫 delete_activity(record_id: 99999)，同樣得到 not_found。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（修改）] 回覆「Updated <編號>: title, category → <分類>」這類變更說明。
2. [D-2（刪除）] 回覆「Deleted activity <編號>」。
3. [D-3（畫面更新）] 開著的時間軸畫面立即重新整理。

## E. 完成後系統狀態應如何更新

1. [E-1（修改）] 在同一次寫入中更新活動的標題與（或）分類；分類保存為找到的分類的正式名稱。其餘內容不變。
2. [E-2（刪除）] 依[刪除卡片](<../時間軸/[功能]刪除卡片.md>) E-1 到 E-3：標記刪除、刪除該時段的觀察、刪除縮時影片。
3. [E-3（記錄寫入）] 記錄這次寫入的時間、操作與參數。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（修改寫入失敗）] 修改寫入資料庫失敗時回覆 internal_error 與錯誤訊息。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（修改寫入失敗）] 修改寫入失敗時標題與分類都不變。
