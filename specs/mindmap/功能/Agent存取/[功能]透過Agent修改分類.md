---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Agent存取.md#寫入的開關"
    description: 開關、寫入通道與破壞性確認依 Agent 存取機制。
  - from: "#E-1"
    to: "../分類/[機制]分類.md#分類與卡片的關係"
    description: 改名時一併更新既有卡片；刪除時既有卡片保留名稱。
triggers:
  - dayflow categories add / rename / color / describe / remove
  - MCP 工具 create_category、update_category、delete_category
  - 寫入通道操作 category_add、category_update、category_remove
sources:
  _feature:
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift:45-147
    - tools/dayflow-cli/Sources/dayflow/WriteCommands.swift:62-112
  B-2:
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift:63-72
  C-2:
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift:47-61
---
Feature: 透過 Agent 修改分類

# 前置

## A. 權限

1. [A-1（允許編輯）] 「允許編輯」必須開啟；關閉時拒絕，回覆 edits_disabled（「Editing is off…」），命令列結束碼 4，分類不變。
2. [A-2（App 必須在執行）] Dayflow App 必須正在執行；否則回覆 app_not_running，命令列結束碼 5，分類不變。

## B. 參數合法條件

1. [B-1（名稱必填）] 新增時名稱去掉前後空白後不可空白；修改與刪除時必須指定分類名稱。否則回覆 invalid_argument。
2. [B-2（顏色格式）] 有給顏色時必須是 6 位十六進位色碼（可省略開頭的 #，大小寫皆可）；否則回覆 invalid_argument「"<值>" is not a hex color like #F96E00.」。保存時統一為大寫並加上 #。
3. [B-3（修改至少一項）] 修改時至少要有新名稱（且與原名不同）、顏色或說明其中之一；否則回覆 invalid_argument「Nothing to change. Pass new_name, color, or description.」。
4. [B-4（刪除需要確認）] 命令列刪除時須在互動終端機回答 y，或加上 --yes；否則取消或拒絕，分類不變。

## C. 使用此功能的系統前置狀態條件

1. [C-1（新增時不可重名）] 新增時不能與既有分類同名（不分大小寫）；否則回覆 already_exists。
2. [C-2（找得到唯一的分類）] 修改與刪除時依名稱（不分大小寫）找分類：找不到時回覆 not_found 並列出現有分類名稱；找到多個時回覆 ambiguous。
3. [C-3（不能刪系統分類）] 刪除的分類是系統分類（Idle）時回覆 permission_denied。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（新增）] 回覆「Created <名稱>」。
2. [D-2（修改）] 回覆分類名稱與做了哪些變更，例如「Work: renamed to Engineering, color #6A7EFF」。
3. [D-3（刪除）] 回覆「Removed <名稱>. <數量> past activities keep the label but lose the color.」，並回傳受影響的活動數。

## E. 完成後系統狀態應如何更新

1. [E-1（同介面操作）] 新增、修改、刪除分別依[新增分類](<../分類/[功能]新增分類.md>)、[修改分類](<../分類/[功能]修改分類.md>)、[刪除分類](<../分類/[功能]刪除分類.md>)的結果更新分類（改名時既有卡片一併改名），但新增時使用指定的名稱、顏色（未給時 #E5E7EB）與說明。MCP 的 update_category 說明應與此一致（程式現況見[修正清單](<../../修正清單.md>) 第 3 項）。
2. [E-2（記錄寫入）] 記錄這次寫入的時間、操作與參數。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（內部錯誤）] App 處理時發生非預期錯誤，回覆 internal_error 與錯誤訊息。

## G. 執行沒有完成時，系統狀態應如何更新

無
