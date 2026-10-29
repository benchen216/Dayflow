---
document_type: Spec
references:
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題一（還原困難）：一天結束時很難還原自己做了什麼"
    description: 讓使用者在終端機或自己慣用的 AI agent（Claude、Codex、Cursor 等）裡直接取用工作日誌，例如寫站會或週回顧。
  - from: "#寫入的開關"
    to: "../[Problem]還原一天的工作.md#問題三（隱私）：螢幕畫面含大量敏感資訊"
    description: 寫入預設關閉，由使用者明確開啟；只有本機同一個使用者能連上寫入通道。
sources:
  _mechanism:
    - Dayflow/Dayflow/Core/AgentAccess/AgentBridgeServer.swift
    - Dayflow/Dayflow/Core/AgentAccess/AgentWriteHandlers.swift
    - tools/dayflow-cli/Sources/dayflow/main.swift
    - tools/dayflow-cli/Sources/dayflow/Bridge.swift
    - tools/dayflow-cli/Sources/dayflow/MCPServer.swift
  寫入的開關:
    - Dayflow/Dayflow/Core/AgentAccess/AgentBridgeServer.swift:16-23
    - Dayflow/Dayflow/Core/AgentAccess/AgentBridgeServer.swift:144-149
    - tools/dayflow-cli/Sources/dayflow/MCPServer.swift:174-246
  寫入通道:
    - Dayflow/Dayflow/Core/AgentAccess/AgentBridgeServer.swift:46-196
  破壞性操作的確認:
    - tools/dayflow-cli/Sources/dayflow/WriteCommands.swift:47-60
---

# 範圍

Dayflow 隨附一個 `dayflow` 命令列工具，可以在終端機使用，也可以作為 MCP server 讓 AI agent 使用。本機制定義讀取與寫入走的不同路徑、寫入的開關、寫入通道的規則，以及破壞性操作的確認。各操作的條件與結果見本資料夾的功能規格，介面契約見 API 文件。

# 讀取與寫入走不同路徑

| | 讀取 | 寫入 |
|---|---|---|
| 怎麼取得資料 | 命令列工具直接讀本機的 Dayflow 資料庫 | 交給正在執行的 Dayflow App 處理 |
| Dayflow 關閉時 | 照常可用 | 失敗：「Dayflow isn't running. Reads work offline; edits need the app open.」 |
| 需要開啟寫入 | 否 | 是 |
| 可用的操作 | 狀態、時間軸、單一活動、Daily、週報、分類、搜尋、時間分布 | 新增／修改／刪除分類、修改／刪除活動、設定每日目標 |

寫入必須經過 App，因為分類保存在 App 這邊，而且 App 的畫面要在資料變更後立即更新。寫入使用與 App 介面相同的處理（分類、卡片、目標），不是任意修改資料庫。

# 寫入的開關

1. 「允許編輯」預設關閉，由使用者在設定中開啟。
2. 開關關閉時：App 不開啟寫入通道；命令列工具拒絕寫入指令；MCP server 不提供寫入工具。
3. 即使命令列工具沒有先檢查，App 收到寫入時仍會再檢查一次開關；關閉時回覆 edits_disabled。

# 寫入通道

1. 寫入通道是本機的一個檔案端點，只有同一個系統使用者能連線；App 啟動且開關開啟時才建立，關閉開關時移除。
2. 每次連線只送一個請求、回一個結果，請求大小上限 1 MB；請求必須帶協定版本 1，版本不符時回覆 protocol_mismatch，提示更新 Dayflow。
3. 每次成功的寫入會在本機記錄時間、操作與參數（不記錄回傳的資料），供使用者事後查看 agent 做了什麼。
4. 寫入完成後通知 App 重新整理時間軸畫面。

# 破壞性操作的確認

1. 刪除分類與刪除活動屬於破壞性操作。
2. 命令列在互動式終端機中會先詢問確認（y/N），回答不是 y 時取消；非互動式執行時必須加上 --yes，否則拒絕。
3. MCP 工具在說明中標示為破壞性，要求 agent 先向使用者確認；Dayflow 本身不再另外確認。

# 一天與一週的範圍

命令列與 MCP 的日期都以早上 4:00 為界；一週從週一 4:00 到下週一 4:00。Daily 例外：`daily` 未指定日期時用一般的日曆日期查詢。

# 實例化情境

小安在 Claude Code 裡問「我昨天做了什麼」。Claude 透過 MCP 呼叫 get_timeline 讀到昨天的活動（Dayflow 沒開也可以）。小安接著說「把 214 號活動改成 Code Review」，但「允許編輯」是關的，MCP 沒有提供 update_activity，Claude 回覆無法修改。小安在設定中開啟「允許編輯」並重開對話後，Claude 呼叫 update_activity，Dayflow App 更新卡片、時間軸畫面立即刷新，並記下這次寫入。
