---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Agent存取.md#寫入的開關"
    description: 開關與寫入通道依 Agent 存取機制。
  - from: "#E-1"
    to: "../每日目標/[機制]每日目標.md#目標的組成"
    description: 目標的組成與保存方式依每日目標機制。
triggers:
  - dayflow goal set [日期] --focus-minutes <n> [--distraction-limit-minutes <n>] [--focus-category <名稱>]... [--distraction-category <名稱>]...
  - MCP 工具 set_day_goal
  - 寫入通道操作 goal_set
sources:
  _feature:
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift:218-276
    - tools/dayflow-cli/Sources/dayflow/WriteCommands.swift:143-168
---
Feature: 透過 Agent 設定每日目標

# 前置

## A. 權限

1. [A-1（允許編輯）] 「允許編輯」必須開啟；否則回覆 edits_disabled，命令列結束碼 4，目標不變。
2. [A-2（App 必須在執行）] Dayflow App 必須正在執行；否則回覆 app_not_running，命令列結束碼 5，目標不變。

## B. 參數合法條件

1. [B-1（專注目標）] 專注目標分鐘數必須是大於 0 的整數；否則回覆 invalid_argument「A positive focus_minutes value is required.」。沒有上限。
2. [B-2（日期）] 有給日期時必須是非空白的文字；給了非文字回覆 invalid_argument「date must be a YYYY-MM-DD string when provided.」，空白回覆「date cannot be empty when provided.」。未給時使用今天（以 4:00 為界）。日期內容本身不再驗證格式。
3. [B-3（分類名稱）] 有給專注或分心分類時，每個名稱都必須找得到唯一的分類（不分大小寫）；否則回覆 not_found 或 ambiguous，目標不變。

## C. 使用此功能的系統前置狀態條件

無

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（設定結果）] 回覆「<日期>: <專注>m focus target, <上限>m distraction limit」。

## E. 完成後系統狀態應如何更新

1. [E-1（保存目標）] 保存這一天的目標並標記為未略過：專注目標為指定值；分心上限為指定值，未給時沿用這一天既有的上限，再沒有時為 60 分鐘；專注與分心分類為指定的分類（依給的順序），未給時沿用這一天既有的分類，再沒有時為空。這一天已有目標時保留原本的建立時間。
    1. Example: 只給專注目標

        週三沒有目標，agent 呼叫 set_day_goal(focus_minutes: 240)。保存的目標為專注 240 分鐘、分心上限 60 分鐘、專注與分心分類都是空的。
2. [E-2（記錄寫入）] 記錄這次寫入的時間、操作與參數。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

無

## G. 執行沒有完成時，系統狀態應如何更新

無
