---
type: Command
document_type: Spec
references:
  - from: "#"
    to: "./[機制]分析批次與活動卡片.md#AI 供應商"
    description: 各供應商需要的設定、主要與備援如何接手依機制。
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題三（隱私）：螢幕畫面含大量敏感資訊"
    description: 使用者自行決定畫面交給本機模型或哪個雲端服務。
triggers:
  - 設定「供應商」分頁
  - 新手引導的供應商設定步驟
sources:
  _feature:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:319-660
    - Dayflow/Dayflow/Core/AI/LLMProviderRouting.swift
  A-1:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:636-651
  C-1:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:577-606
  C-2:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:319-342
  E-1:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:441-495
  E-2:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:496-562
  E-3:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift:612-625
  E-4:
    - Dayflow/Dayflow/Core/AI/LLMOutputLanguagePreferences.swift
  E-5:
    - Dayflow/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel+PromptOverrides.swift
---
Feature: 設定 AI 供應商

本功能包含：設定某個供應商（API key、服務網址、模型、命令列工具檢查）、指定主要供應商、指定或清除備援供應商、選擇 AI 輸出語言、自訂卡片標題／摘要／詳細說明的提示詞。

# 前置

## A. 權限

1. [A-1（Dayflow 供應商需要 Pro）] 只有 Dayflow 帳號的方案為 Pro 且狀態有效時，才能把 Dayflow 設為主要或備援供應商；否則不改變設定，改為開啟帳號頁面讓使用者升級。

## B. 參數合法條件

1. [B-1（各供應商的必要設定）] 設定供應商時必須填齊該供應商需要的設定：Gemini 需要非空白的 API key；本機模型需要服務網址與模型；OpenAI 相容服務需要完整的服務設定，非自訂服務另需 API key；ChatGPT 與 Claude 需要偵測到本機的命令列工具並完成設定流程。未填齊時不能完成設定。

## C. 使用此功能的系統前置狀態條件

1. [C-1（只能指定已設定好的供應商）] 指定主要或備援時，該供應商必須已設定好（見 B-1）；尚未設定時先進入該供應商的設定流程，完成後才依原本要指定的角色（主要或備援）套用。設定流程取消時不改變任何指定。
2. [C-2（設定必須能讀取）] 目前保存的供應商指定讀取失敗時，畫面顯示「Dayflow couldn't load your provider routing. Your saved providers were left unchanged.」，所有指定操作停用，保存的設定不變。
3. [C-3（清除備援的前提）] 清除備援時，必須目前有備援；沒有時不做任何事。

# 後置

## D. 完成後使用者應該要看見什麼/得到什麼回應

1. [D-1（目前的指定）] 使用者看見目前的主要供應商與備援供應商；沒有備援時顯示「Not configured」。

## E. 完成後系統狀態應如何更新

1. [E-1（指定主要供應商）] 指定新的主要供應商時，若它原本是備援，原本的主要改為備援（兩者交換）；否則備援不變。指定的就是目前主要時不做任何事。新指定從下一批分析開始生效。
    1. Example: 主要與備援交換

        | 操作前主要 | 操作前備援 | 指定主要 | 操作後主要 | 操作後備援 |
        |---|---|---|---|---|
        | Claude | Gemini | Gemini | Gemini | Claude |
        | Claude | Gemini | ChatGPT | ChatGPT | Gemini |
2. [E-2（指定備援供應商）] 指定備援時，若指定的是目前主要且已有備援，兩者交換；若指定的是目前主要但沒有備援，不做任何事；其他情況直接設為備援。
3. [E-3（清除備援）] 清除備援後只剩主要供應商。
4. [E-4（AI 輸出語言）] 使用者可指定 AI 撰寫卡片與摘要時使用的語言；未指定時，介面語言為簡體中文、繁體中文、韓文、德文、俄文、法文、日文時採用該語言，其他介面語言不另外指定。
5. [E-5（自訂提示詞）] 使用者可分別為 Gemini、本機模型、命令列工具類供應商（ChatGPT／Claude）自訂卡片的標題、摘要、詳細說明三段提示詞，或還原為內建的提示詞；未啟用或空白的段落使用內建提示詞。

# 前置成立，但執行沒有完成 的後置狀態

## F. 執行沒有完成時，使用者應該要看見什麼/得到什麼回應

1. [F-1（保存失敗）] 保存新的指定失敗時，畫面維持原本的指定。

## G. 執行沒有完成時，系統狀態應如何更新

1. [G-1（保存失敗）] 保存新的指定時寫入後會立即讀回驗證；驗證失敗時還原為保存前的值，主要與備援都不變。
