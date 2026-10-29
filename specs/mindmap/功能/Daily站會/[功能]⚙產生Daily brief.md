---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題一（還原困難）：一天結束時很難還原自己做了什麼"
    description: 每天早上把前一天完成的事、值得回顧的畫面整理成簡報。
triggers:
  - App 變成前景時
  - 每 5 分鐘（與 Daily 自動產生同一個計時）
  - 簡報頁的重試按鈕
sources:
  _feature:
    - Dayflow/Dayflow/Core/DailyBrief/DailyBriefStore.swift
    - Dayflow/Dayflow/Core/DailyBrief/DailyBriefGenerator.swift
  A-1:
    - Dayflow/Dayflow/Core/DailyBrief/DailyBriefStore.swift:24-38
  C-1:
    - Dayflow/Dayflow/Core/DailyBrief/DailyBriefStore.swift:263-280
---
Feature: 產生 Daily brief

Daily brief 是每天一份的簡報（前一天完成的事、相關畫面、建議待辦），由本機的 Claude 命令列工具產生，目前只對少數帳號開放。

# 前置

## A. 權限

1. [A-1（限量開放）] 只有以 Dayflow 帳號登入、且帳號在程式內建的開放名單中時才提供；其他使用者完全看不到 Daily brief，也不會自動產生。

## B. 參數合法條件

無

## C. 使用此功能的系統前置狀態條件

1. [C-1（自動產生的條件）] 自動產生時：今天（以 4:00 為界）還沒有簡報、今天的自動嘗試未滿 2 次、前一天的卡片時間至少 60 分鐘、目前沒有正在產生的簡報；否則不產生。重試按鈕不受次數與時數限制。
2. [C-2（需要 Claude）] 本機的 Claude 命令列工具必須可用；不可用時這次產生失敗。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（簡報已準備好）] 自動產生成功且簡報未開啟時，右上角顯示「簡報已準備好」的提示；打開時間軸時，若今天的簡報還沒看過會自動開啟。
2. [D-2（取代每日目標提示）] 能使用 Daily brief 的使用者不會收到每日目標的主動詢問。

## E. 完成後系統狀態應如何更新

1. [E-1（保存簡報）] 保存今天的簡報（含簡報引用的畫面複本，讓它在錄影被清除後仍在）；重試時取代內容，但保留使用者今天已經勾選、略過、新增的項目。
2. [E-2（使用者的操作）] 使用者勾選、略過項目、新增或移除待辦、收藏或取消收藏畫面時，立即保存；勾選、略過與收藏另記為回饋，供之後產生簡報參考（最多保留 2000 筆）。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（產生失敗）] 產生失敗時簡報頁顯示失敗原因與重試按鈕。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（產生失敗）] 失敗時不保存新簡報，已計的自動嘗試不退還。
