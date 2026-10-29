---
type: Auth
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Dayflow帳號與方案.md#登入狀態"
    description: 憑證保存、失效與重新讀取依帳號機制。
triggers:
  - 設定「帳號」、新手引導的登入步驟
endpoints:
  - POST {Dayflow 後端}/v1/auth/code/start
  - POST {Dayflow 後端}/v1/auth/code/verify
  - GET {Dayflow 後端}/v1/me
  - POST {Dayflow 後端}/v1/auth/logout
sources:
  _feature:
    - Dayflow/Dayflow/System/DayflowAuthManager.swift:355-470
    - Dayflow/Dayflow/System/DayflowAuthManager.swift:629-648
---
Feature: 登入與登出 Dayflow 帳號

# 前置

## A. 權限

無

## B. 參數合法條件

1. [B-1（email）] 寄送驗證碼前，email（去掉空白、轉小寫）必須看起來是有效的 email；否則顯示「Enter a valid email address.」，不寄送。
2. [B-2（驗證碼）] 驗證碼取出數字後必須剛好 6 位；否則顯示「Enter the 6 digit code.」，不驗證。
3. [B-3（先輸入 email）] 驗證時必須已輸入 email；否則顯示「Start with your email first.」。

## C. 使用此功能的系統前置狀態條件

1. [C-1（驗證碼有效）] 驗證碼必須正確且未過期；否則顯示「That code is wrong or has expired. Check it, or send a new one.」，維持未登入。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（寄出驗證碼）] 寄出後顯示「Code sent to <email>.」，可以重寄或改用其他 email。
2. [D-2（登入成功）] 登入成功後顯示「Signed in.」，帳號頁顯示 email、方案與推薦狀態。
3. [D-3（登出）] 登出後顯示「Signed out.」。

## E. 完成後系統狀態應如何更新

1. [E-1（登入）] 把後端發的登入憑證存入系統鑰匙圈，取得帳號、方案權益與 Flow 是否開放，記住 email；有待兌換的推薦碼時自動兌換。
2. [E-2（登出）] 通知後端登出，刪除鑰匙圈中的憑證、清除帳號與推薦資料；即使後端判定憑證已失效也照樣在本機登出。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（憑證無法保存）] 憑證無法存入鑰匙圈時顯示「Could not save your session to Keychain.」，維持未登入。
2. [F-2（連線失敗）] 後端無法連線時顯示錯誤訊息。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（登入未完成）] 登入未完成時不保存憑證，帳號狀態維持原狀。
