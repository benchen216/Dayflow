---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Daily站會.md#自動產生"
    description: 檢查時機、條件、來源日與次數上限依 Daily 站會機制。
triggers:
  - App 啟動時，之後每 5 分鐘
sources:
  _feature:
    - Dayflow/Dayflow/Core/AI/DailyRecapScheduler.swift:22-298
  C-4:
    - Dayflow/Dayflow/Core/AI/DailyRecapAttemptBudget.swift
  E-2:
    - Dayflow/Dayflow/Core/Notifications/NotificationService.swift:157-208
---
Feature: 自動產生 Daily 站會

# 前置

## A. 權限

無

## B. 參數合法條件

無

## C. 使用此功能的系統前置狀態條件

1. [C-1（已解鎖且已過 4:00）] Daily 已解鎖，且現在的時鐘時間已過早上 4:00；否則這次檢查不做任何事。
2. [C-2（今天還沒有 Daily）] 目標日（時間軸上的今天）還沒有 Daily；已有時不產生。
3. [C-3（找得到來源日）] 依[Daily 站會](<[機制]Daily站會.md>)的「來源日」找得到來源日（門檻 180 分鐘）；找不到時不產生。
4. [C-4（產生方式可用、未超過次數）] 產生方式不是「不產生」且目前可用，而且這個目標日的自動嘗試未滿 3 次；否則不產生。檢查通過後先計一次嘗試再呼叫 AI。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（Daily 已準備好）] 產生成功後，使用者收到系統通知告知今天的 Daily 已準備好；打開 Daily 分頁可看到內容。

## E. 完成後系統狀態應如何更新

1. [E-1（保存 Daily）] 以今天為目標日保存 Daily：昨日重點、今日待辦（各為去除空白與重複後的條列）、阻礙，以及產生方式、模型、來源日與產生時間。
2. [E-2（排定通知）] 排定「Daily 已準備好」的系統通知。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（產生失敗）] AI 呼叫失敗、結果無法保存或保存後讀不到時，不通知使用者；打開 Daily 分頁顯示尚未產生的提示。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（產生失敗）] 失敗時不保存 Daily，已計的嘗試次數不退還；下一次檢查若仍未滿 3 次會再試一次。
