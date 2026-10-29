---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]螢幕錄製.md#隱私排除的 App"
    description: 清單在擷取時如何生效（前景遮蔽與視窗排除）依機制。
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題三（隱私）：螢幕畫面含大量敏感資訊"
    description: 讓使用者決定哪些 App 不被記錄。
triggers:
  - 設定「錄製隱私」分頁
sources:
  _feature:
    - Dayflow/Dayflow/Views/UI/Settings/RecordingPrivacySettingsViewModel.swift
    - Dayflow/Dayflow/Core/Recording/RecordingPrivacyPreferences.swift
  C-1:
    - Dayflow/Dayflow/Views/UI/Settings/RecordingPrivacySettingsViewModel.swift:43-56
    - Dayflow/Dayflow/Core/Recording/RecordingPrivacyPreferences.swift:85-98
---
Feature: 設定不錄製的 App

使用者在設定中瀏覽已安裝的 App（可搜尋名稱或識別碼），把 App 加入或移出「不錄製的 App」清單、拖放 App 加入，或一次清空清單。

# 前置

## A. 權限

無

## B. 參數合法條件

1. [B-1（App 識別碼）] 加入的 App 以識別碼記錄，去掉前後空白並轉成小寫；空白的識別碼不加入，清單不變。
2. [B-2（不重複）] 清單中已有相同識別碼（不分大小寫）時不再加入，清單不變。

## C. 使用此功能的系統前置狀態條件

1. [C-1（第一次開啟時自動加入密碼類 App）] 第一次載入已安裝 App 時，把名稱或識別碼符合常見密碼管理器與驗證器的 App 自動加入清單，並記下已加入過；之後再也不自動加入，即使使用者已移除它們。
    1. Example: 移除後不會被加回

        小安的 Mac 裝了 1Password 與 Bitwarden。第一次開啟錄製隱私設定時兩者被加入清單；小安移除 Bitwarden，下次開啟設定時 Bitwarden 仍不在清單中。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（清單顯示）] 使用者看見目前清單中的 App；已不在本機安裝的 App 仍列出，名稱以識別碼最後一段轉成首字大寫顯示。
    1. Example: 已移除安裝的 App

        清單中有 com.agilebits.onepassword7，但這台 Mac 已移除它；畫面顯示名稱「Onepassword7」。

## E. 完成後系統狀態應如何更新

1. [E-1（保存清單）] 加入、移除或清空後立即保存清單；從下一次擷取起依[螢幕錄製](<[機制]螢幕錄製.md>)的「隱私排除的 App」生效。已保存的影格不重新遮蔽。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

無

## G. 執行沒有完成時，系統狀態應如何更新

無
