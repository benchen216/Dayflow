---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題二（分心難察覺）：很難及早察覺自己開始分心"
    description: 專注時段中由 AI 看畫面，偏離目標時當下提醒，而不是事後才發現。
  - from: "#A-1"
    to: "./[功能]取得Flow使用資格.md#C-1"
    description: 能否使用 Flow 依取得 Flow 使用資格的判斷。
triggers:
  - Flow 頁面開始、暫停、結束專注時段
  - 專注時段中約每 15 秒一次
sources:
  _feature:
    - Dayflow/Dayflow/Core/Flow/FlowDistractionAgent.swift
    - Dayflow/Dayflow/Core/Flow/FlowAgentSettings.swift
    - Dayflow/Dayflow/Core/Flow/FlowOverlayController.swift
  B-1:
    - Dayflow/Dayflow/Core/Flow/FlowDistractionAgent.swift:62-80
  E-1:
    - Dayflow/Dayflow/Core/Flow/FlowAgentSettings.swift:66-100
---
Feature: 進行 Flow 專注時段

# 前置

## A. 權限

1. [A-1（已開放且有方案）] 帳號必須已開放 Flow，且方案為 Plus 或 Pro 並有效。

## B. 參數合法條件

1. [B-1（看畫面的 AI）] 看畫面的 AI 跟隨時間軸的主要供應商：ChatGPT（本機 Codex）、Claude（本機 Claude，用 haiku 模型）或 Dayflow Pro；其他供應商不支援，Flow 說明無法開始而不啟動。
2. [B-2（時段設定）] 使用者在 Flow 頁面設定時段長度、目標清單與提醒方式。

## C. 使用此功能的系統前置狀態條件

1. [C-1（看畫面開關）] 「看畫面」的總開關關閉時，時段照常計時但完全不擷取畫面。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（偏離時提醒）] AI 判斷使用者偏離目標時，在桌面上以小角色的方式提醒（提醒的位置與樣式可選）；回到專注時給予鼓勵；休息時顯示休息畫面。
2. [D-2（時段時間軸）] 時段中顯示這段時間的專注與分心紀錄，以及 AI 判斷已完成的目標。

## E. 完成後系統狀態應如何更新

1. [E-1（每次檢查）] 時段開始時把目標、時段長度與提醒方式交給 AI；之後約每 15 秒擷取一次目前螢幕的畫面（預設 1080p，壓縮後）交給 AI，連同目前時間與剩餘時間；AI 回覆是否偏離、看到什麼、要不要提醒；約每 60 秒另外請 AI 更新時段時間軸。使用 Dayflow Pro 時每次檢查另附最近 12 輪的文字（不含畫面）。
2. [E-2（看不懂的回覆）] AI 的回覆無法解析時視為專注、不提醒，避免誤報。
3. [E-3（擷取失敗）] 擷取畫面失敗時依 30 秒、1 分、2 分、5 分逐步延後再試，不計入失敗次數。
4. [E-4（紀錄同步）] 偏離與回到專注的轉換記錄到時段的分心紀錄，並同步到 Dayflow 後端。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（連續失敗）] AI 連續 3 次（可調）回覆失敗或逾時（每次 60 秒），這個時段停止看畫面並在 Flow 頁面顯示狀態；時段本身繼續計時。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（連續失敗）] 停止看畫面後不再擷取畫面，已記錄的時段紀錄保留。
