---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Daily站會.md#解鎖"
    description: 解鎖門檻與步驟依 Daily 站會機制。
triggers:
  - Daily 分頁未解鎖時的解鎖流程
sources:
  _feature:
    - Dayflow/Dayflow/Views/UI/DailyView+Access.swift
    - Dayflow/Dayflow/Views/UI/DailyAccessLockedViews.swift
  C-1:
    - Dayflow/Dayflow/Core/Access/FeatureAccessRequirements.swift:3-58
    - Dayflow/Dayflow/Core/Recording/StorageManager+Reprocessing.swift:228-240
  C-2:
    - Dayflow/Dayflow/Views/UI/DailyView+Access.swift:142-191
---
Feature: 解鎖 Daily

# 前置

## A. 權限

無

## B. 參數合法條件

1. [B-1（選擇產生方式）] 解鎖的最後一步必須選擇一種 Daily 產生方式（Dayflow 後端、Claude、ChatGPT、Gemini、本機模型或不產生）。

## C. 使用此功能的系統前置狀態條件

1. [C-1（累積錄製門檻）] 分析成功的批次（狀態為 analyzed 或 completed）至少 20 批才能開始解鎖；未達時解鎖按鈕不可用，畫面顯示累積進度（以每批 15 分鐘換算，例如「3h 15m / 5h」，超過 5 小時仍顯示 5h）。
2. [C-2（必須允許通知）] 解鎖過程中必須允許 Dayflow 的系統通知（狀態為「已允許」）；使用者拒絕或尚未決定時，不前進到下一步，改為開啟系統通知設定。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（解鎖完成）] 完成後顯示「Daily Unlocked」並進入 Daily 頁面。

## E. 完成後系統狀態應如何更新

1. [E-1（記錄已解鎖）] 記錄 Daily 已解鎖，之後依[Daily 站會](<[機制]Daily站會.md>)的「自動產生」每天產生 Daily。
2. [E-2（保存產生方式）] 保存選擇的 Daily 產生方式。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（中途離開）] 使用者在完成最後一步前離開，下次進入 Daily 分頁仍顯示解鎖流程。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（中途離開）] 未完成最後一步時不記錄已解鎖，不自動產生 Daily。
