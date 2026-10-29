---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]Agent存取.md#寫入的開關"
    description: 開關開啟與關閉的效果依 Agent 存取機制。
triggers:
  - 設定「MCP / CLI」分頁
  - dayflow link / unlink
  - App 啟動時修復過期的用戶端設定
sources:
  _feature:
    - Dayflow/Dayflow/Views/UI/Settings/SettingsAgentAccessTabView.swift
    - Dayflow/Dayflow/Core/AgentAccess/AgentClientRegistration.swift
  E-1:
    - Dayflow/Dayflow/Views/UI/Settings/SettingsAgentAccessTabView.swift:270-285
  E-2:
    - Dayflow/Dayflow/Core/AgentAccess/AgentClientRegistration.swift
  E-3:
    - tools/dayflow-cli/Sources/dayflow/main.swift:303-345
---
Feature: 設定 Agent 存取

本功能包含：開關「允許編輯」、把 Dayflow 連接到 AI 用戶端（Codex、Claude Code、Claude Desktop、Cursor、VS Code）、把 `dayflow` 指令加入系統路徑。

# 前置

## A. 權限

1. [A-1（加入系統路徑）] 把 `dayflow` 加入 /usr/local/bin 需要寫入該資料夾的權限；沒有時失敗並提示改用 sudo 或手動建立連結。

## B. 參數合法條件

無

## C. 使用此功能的系統前置狀態條件

1. [C-1（移除連結）] 移除連結時，/usr/local/bin/dayflow 必須是一個連結；否則回覆「Nothing to remove…」，結束碼 3。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（用戶端狀態）] 設定頁顯示每個用戶端是否已安裝、是否已連接；不支援直接設定的用戶端提供可複製的設定片段。

## E. 完成後系統狀態應如何更新

1. [E-1（允許編輯）] 開啟時保存開關並建立寫入通道；關閉時保存開關並移除寫入通道，之後的寫入一律被拒。
2. [E-2（連接用戶端）] Claude Code 與 Claude Desktop 由 Dayflow 直接在它們的設定檔中寫入名為 dayflow 的項目（只動這一項），指向 App 內附的 `dayflow` 並以 MCP 模式執行；Cursor 與 VS Code 透過它們自己的安裝連結，由用戶端在使用者同意後寫入設定。App 搬移位置後，啟動時自動修正先前寫入的項目。
3. [E-3（加入系統路徑）] 在 /usr/local/bin 建立指向 App 內附 `dayflow` 的連結（已存在時取代）；不下載任何東西，也不修改 shell 設定。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（建立連結失敗）] 無法寫入 /usr/local/bin 時顯示錯誤，並提供可自行執行的 sudo 指令。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（建立連結失敗）] 失敗時不建立連結。
