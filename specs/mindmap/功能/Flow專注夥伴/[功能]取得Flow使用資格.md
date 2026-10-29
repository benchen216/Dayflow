---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "../帳號與方案/[機制]Dayflow帳號與方案.md#方案與權益"
    description: Flow 由後端依帳號開放，並需要 Plus 或 Pro 方案。
triggers:
  - Flow 分頁（候補名單、邀請碼、購買或試用 Plus）
endpoints:
  - POST {Dayflow 後端}/v1/flow/waitlist
  - POST {Dayflow 後端}/v1/flow/access-code
sources:
  _feature:
    - Dayflow/Dayflow/Views/UI/Flow/FlowView.swift
    - Dayflow/Dayflow/Views/UI/Flow/FlowWaitlistView.swift
    - Dayflow/Dayflow/System/DayflowAuthManager.swift:762-795
  C-1:
    - Dayflow/Dayflow/Views/UI/Flow/FlowView.swift:29-51
  C-2:
    - Dayflow/Dayflow/Views/UI/Flow/FlowWebView.swift:390-400
---
Feature: 取得 Flow 使用資格

Flow 是實驗中的專注夥伴：使用者設定一段專注時段與目標，Flow 在時段中看畫面，偏離時提醒。本功能定義使用者如何取得使用資格。

# 前置

## A. 權限

1. [A-1（兌換邀請碼需要登入）] 兌換邀請碼必須已登入；否則顯示「Sign in first to use an access code.」。加入候補名單不需要登入。

## B. 參數合法條件

1. [B-1（候補 email）] 加入候補名單時 email 必須看起來有效；否則顯示「Enter a valid email address.」。
2. [B-2（邀請碼不可空白）] 邀請碼去掉前後空白後不可空白；否則顯示「Enter your access code.」。

## C. 使用此功能的系統前置狀態條件

1. [C-1（Flow 分頁顯示什麼）] Flow 分頁依序判斷：帳號尚未讀取完成時顯示讀取中；帳號已開放 Flow、但時間軸主要 AI 供應商不是 ChatGPT、Claude 或 Dayflow 時，顯示需要更換供應商的說明；帳號已開放 Flow 時顯示 Flow；已登入但帳號讀取失敗時顯示需要網路的錯誤與重試；其他情況顯示候補名單。
2. [C-2（使用需要方案）] 開放 Flow 的帳號，方案為 Plus 或 Pro 且狀態為 active 時才能開始專注時段；否則 Flow 頁面提供購買或 Plus 試用（見[購買與管理方案](<../帳號與方案/[功能]購買與管理方案.md>)）。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（加入候補）] 加入候補名單後顯示已加入。
2. [D-2（兌換成功）] 邀請碼兌換成功後，Flow 分頁立即切換為 Flow。

## E. 完成後系統狀態應如何更新

1. [E-1（開放 Flow）] 邀請碼兌換成功時，後端把帳號加入開放名單，本機記錄 Flow 已開放。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（後端拒絕）] 邀請碼無效或後端錯誤時顯示錯誤訊息。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（後端拒絕）] Flow 是否開放維持原狀。
