---
type: Command
document_type: Spec
triggers:
  - 主視窗出現時檢查是否有適合的問卷
endpoints:
  - GET {問卷後端}/v1/surveys/live
  - POST {問卷後端}/v1/surveys/events
sources:
  _feature:
    - Dayflow/Dayflow/Core/Surveys/SurveyCenter.swift
    - Dayflow/Dayflow/Core/Surveys/SurveyEventReporter.swift
  C-2:
    - Dayflow/Dayflow/Core/Surveys/SurveyCenter.swift:150-175
  C-3:
    - Dayflow/Dayflow/Core/Surveys/SurveyCenter.swift:99-118
---
Feature: 回答 App 內問卷

問卷清單由後端提供（最多每 15 分鐘重新取得一次）；誰該看到哪份問卷完全在本機依本機資料判斷。

# 前置

## A. 權限

無

## B. 參數合法條件

無

## C. 使用此功能的系統前置狀態條件

1. [C-1（基本條件）] 已完成新手引導、時間軸上至少有一張卡片、目前沒有其他問卷或提示卡在畫面上。
2. [C-2（對象）] 問卷指定的 AI 供應商為「any」或等於目前的主要供應商，且使用者符合對象：everyone（使用超過後端指定的新使用者保護天數）、new_users（使用不到 7 天）、regulars（使用至少 14 天且最近一週至少 2 天有活動）、gone_quiet（總共至少 5 天有活動但最近一週最多 1 天）、pre_redesign（第一張卡片早於 2026-09-07）。不認得的對象一律不符合。
3. [C-3（頻率）] 已回答完或關閉過的問卷不再出現；距上一份問卷未滿後端指定的天數、或 20 小時內出現過 GitHub 星星提示時不出現。標示「立即詢問」的問卷第一次出現時不受頻率限制。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（顯示問卷）] 一次顯示一份符合條件的問卷；回答完顯示感謝後關閉。

## E. 完成後系統狀態應如何更新

1. [E-1（記錄進度）] 記錄問卷出現的時間；回答完或關閉後記為已結束，不再出現。
2. [E-2（回報）] 回報出現、每題的回答、完成、關閉給問卷後端。關閉使用分析的使用者只回報自己主動做的事（回答、關閉），不回報被動的「符合條件」與使用細節。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（取不到問卷）] 問卷清單取不到時不顯示問卷，沿用先前取得的清單。

## G. 執行沒有完成時，系統狀態應如何更新

無
