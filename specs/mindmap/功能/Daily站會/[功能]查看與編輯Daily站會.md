---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Daily站會.md#"
    description: 來源日、產生方式與交給 AI 的內容依 Daily 站會機制。
triggers:
  - Daily 分頁（切換日期、編輯條目、複製、重新產生、更換產生方式）
sources:
  _feature:
    - Dayflow/Dayflow/Views/UI/DailyView+Standup.swift
    - Dayflow/Dayflow/Views/UI/DailyView+Workflow.swift
  D-2:
    - Dayflow/Dayflow/Views/UI/DailyWorkflowComputation.swift
  E-1:
    - Dayflow/Dayflow/Views/UI/DailyView+Standup.swift:641-675
  E-2:
    - Dayflow/Dayflow/Views/UI/DailyView+Standup.swift:264-520
    - Dayflow/Dayflow/Views/UI/DailyView+Workflow.swift:382-407
---
Feature: 查看與編輯 Daily 站會

使用者在 Daily 分頁查看某一天的 Daily 與當天的活動格狀圖，可以直接編輯條目、複製成站會更新、手動重新產生，或更換產生方式。

# 前置

## A. 權限

1. [A-1（已解鎖）] Daily 未解鎖時只顯示解鎖流程（見[解鎖 Daily](<[功能]解鎖Daily.md>)）。

## B. 參數合法條件

無

## C. 使用此功能的系統前置狀態條件

1. [C-1（重新產生需要產生方式）] 重新產生時，產生方式不能是「不產生」；是的話不產生，顯示「No Daily provider is selected…」。
2. [C-2（重新產生需要來源日）] 重新產生時，依機制的「來源日」以 120 分鐘的門檻找得到來源日，且來源日有卡片；否則不產生，按鈕暫時顯示沒有資料。
3. [C-3（同一時間只重新產生一次）] 重新產生進行中時，再按不會重複執行。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（Daily 內容）] 使用者看見這一天保存的 Daily；沒有保存的 Daily 時，依情況顯示：產生方式為「不產生」的提示、找不到來源日的「Not enough captured activity…」，或「Daily data has not been generated yet…」。
2. [D-2（活動格狀圖）] 使用者看見這一天依時段排列的活動格狀圖與各分類的時間合計。
3. [D-3（複製）] 按複製時，把三段內容整理成站會更新文字放進剪貼簿，按鈕顯示已複製 2 秒。
4. [D-4（重新產生完成）] 重新產生成功後，畫面換成新的內容，按鈕暫時顯示已重新產生。

## E. 完成後系統狀態應如何更新

1. [E-1（編輯即保存）] 使用者編輯條目或阻礙後約 0.25 秒自動保存這一天的 Daily；尚未保存過且內容仍是系統提示時不保存，「不產生」的提示也不保存。
2. [E-2（重新產生）] 重新產生時，依目前的產生方式與機制的「產生方式與交給 AI 的內容」重新產生，覆蓋這一天的 Daily，並排定「Daily 已準備好」的通知。
3. [E-3（更換產生方式）] 更換產生方式只影響之後的產生，已保存的 Daily 不變。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（重新產生失敗）] AI 呼叫失敗時，畫面保留原本的內容，按鈕回到可以再按的狀態。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（重新產生失敗）] 失敗時這一天保存的 Daily 不變。
