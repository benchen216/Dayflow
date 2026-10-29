---
document_type: Spec
references:
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題一（還原困難）：一天結束時很難還原自己做了什麼"
    description: Dayflow 帳號是選用的；登入後可以使用 Dayflow 自家的 AI 服務（Pro）與 Flow（Plus），不需要自備 AI。
  - from: "#帳號是選用的"
    to: "../[Problem]還原一天的工作.md#問題三（隱私）：螢幕畫面含大量敏感資訊"
    description: 不登入也能完整使用本機功能與其他 AI 供應商。
sources:
  _mechanism:
    - Dayflow/Dayflow/System/DayflowAuthManager.swift
    - Dayflow/Dayflow/System/DayflowBackendConfiguration.swift
  方案與權益:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:636-640
    - Dayflow/Dayflow/System/DayflowAuthManager.swift:480-600
  登入狀態:
    - Dayflow/Dayflow/System/DayflowAuthManager.swift:320-470
---

# 範圍

本機制定義 Dayflow 帳號：帳號是選用的、登入狀態如何保存與失效、方案與權益如何決定可用的功能，以及推薦碼。帳號資料由 Dayflow 後端提供；付款由 Stripe 處理。

# 帳號是選用的

不登入也能錄製、使用自備的 AI 供應商（Gemini、ChatGPT、Claude、本機模型、OpenAI 相容服務），以及所有本機功能。需要登入的只有：以 Dayflow 作為 AI 供應商（Pro）、Flow（Plus／Pro）、推薦計畫，以及限量開放的 Daily brief。

# 登入狀態

1. 以 email 收到的 6 位數驗證碼登入；登入成功後，後端發給這台 Mac 的登入憑證保存在系統鑰匙圈，並記住這個 email 方便下次登入。
2. App 啟動時與回到前景時重新讀取帳號資料（使用者、方案權益、Flow 是否開放、推薦狀態）。
3. 任何帳號請求被後端判定為未授權時，刪除保存的憑證，視為已登出，顯示「Session expired. Sign in again.」。
4. 啟動時若因離線讀不到帳號，保留憑證，之後再試。
5. 登入後，這台 Mac 的使用分析身分與帳號合併（每個帳號只做一次），讓同一帳號在多台 Mac 的紀錄合併。

# 方案與權益

| 方案 | 狀態 | 可用功能 |
|---|---|---|
| free | — | 帳號基本功能、推薦計畫 |
| pro | active | 以 Dayflow 作為時間軸與 Daily 的 AI 供應商；Flow |
| plus | active | Flow |

1. 是否能用 Dayflow 作為 AI 供應商，只看方案為 pro 且狀態為 active。
2. Dayflow 後端拒絕請求（未登入、未付費、無權限）時，時間軸分析會失敗並提示「Dayflow Pro plan has ended」，不改用其他方式重試。

# 推薦碼

1. 推薦碼是 6 個字元；可以透過 dayflow://referral（或 claim、r）連結帶入、在登入流程中輸入，或在帳號頁輸入。
2. 尚未登入時，推薦碼先保存在本機，登入成功後自動兌換；兌換失敗時顯示「Signed in. Referral code was not applied.」並保留推薦碼。
3. 使用者錄製期間，Dayflow 向後端回報錄製的秒數，供推薦計畫計算使用量。

# 實例化情境

小晴點了朋友分享的 dayflow://referral?code=AB12CD 連結，Dayflow 記下推薦碼並提示「Referral code saved. Sign in to claim it.」。她輸入 email、收到驗證碼並登入，推薦碼自動兌換，帳號權益更新。之後她購買 Pro，回到 App 時 Dayflow 每 5 秒重新讀取帳號，Stripe 通知後端完成後，供應商設定中的 Dayflow 就可以被選為主要供應商。
