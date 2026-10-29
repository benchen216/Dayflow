---
document_type: Spec
references:
  - from: "#"
    to: "../[Problem]還原一天的工作.md#問題一（還原困難）：一天結束時很難還原自己做了什麼"
    description: 每天早上自動把前一天的時間軸整理成站會更新（昨日重點、今日待辦、阻礙），使用者不必憑記憶寫。
  - from: "#產生方式與交給 AI 的內容"
    to: "../[Problem]還原一天的工作.md#問題三（隱私）：螢幕畫面含大量敏感資訊"
    description: 使用者另外選擇 Daily 由哪個 AI 產生；非 Dayflow 的方式只交出卡片，不交出觀察與過去的 Daily。
sources:
  _mechanism:
    - Dayflow/Dayflow/Core/AI/DailyRecapScheduler.swift
    - Dayflow/Dayflow/Core/AI/DailyRecapModels.swift
    - Dayflow/Dayflow/Core/Recording/StorageManager+DailyStandup.swift
  解鎖:
    - Dayflow/Dayflow/Core/Access/FeatureAccessRequirements.swift:3-8
    - Dayflow/Dayflow/Views/UI/DailyView+Access.swift:142-200
  來源日:
    - Dayflow/Dayflow/Core/AI/DailyRecapModels.swift:298-340
    - Dayflow/Dayflow/Core/AI/DailyRecapScheduler.swift:302-327
  產生方式與交給 AI 的內容:
    - Dayflow/Dayflow/Core/AI/DailyRecapModels.swift:3-160
  自動產生的次數上限:
    - Dayflow/Dayflow/Core/AI/DailyRecapAttemptBudget.swift
---

# 範圍

Daily 是每天一份的站會文件：「昨日重點」「今日待辦」「阻礙」三段。本機制定義 Daily 的解鎖、每份 Daily 依據哪一天的活動（來源日）、由哪個 AI 產生、交給 AI 什麼內容，以及自動產生的時機與次數。功能見[解鎖 Daily](<[功能]解鎖Daily.md>)、[⚙自動產生 Daily 站會](<[功能]⚙自動產生Daily站會.md>)、[查看與編輯 Daily 站會](<[功能]查看與編輯Daily站會.md>)。Daily brief 是另一份限量開放的每日簡報，見[⚙產生 Daily brief](<[功能]⚙產生Daily brief.md>)。

# 名詞

| 名詞 | 意思 |
|---|---|
| 目標日 | 這份 Daily 屬於哪一天（時間軸上的一天，以早上 4:00 為界） |
| 來源日 | 這份 Daily 的「昨日重點」依據哪一天的活動 |
| Daily 產生方式 | 使用者為 Daily 另外選的 AI：Dayflow 後端、Claude、ChatGPT、Gemini、本機模型，或「不產生」 |

# 解鎖

1. 累積分析成功的批次達 20 批（約 5 小時的錄製）後，使用者才能開始解鎖 Daily；未達時顯示進度（例如「3h 15m / 5h」）。
2. 解鎖流程：開始 → 允許系統通知（必須是「已允許」，否則引導到系統通知設定） → 選擇 Daily 產生方式 → 完成解鎖。
3. 解鎖狀態保存在這台 Mac；未解鎖時不自動產生 Daily。

# 來源日

1. 從目標日的前一天開始往回找，最多找 3 天，取第一個同時符合以下條件的日子：
    1. 那一天的卡片時間加總達到門檻：自動產生至少 180 分鐘，使用者手動重新產生至少 120 分鐘。
    2. 那一天還沒有被其他目標日的 Daily 當成來源日。
2. 找不到時這一天不產生 Daily，畫面顯示「Not enough captured activity in the previous 3 days to generate a standup.」。
    1. Example: 週一的 Daily 依據上週五

        週六、週日沒有使用電腦。週一早上自動產生 Daily 時，週日、週六都不足 180 分鐘，週五有 6 小時且尚未被用過，於是週一的 Daily 依據週五。

# 產生方式與交給 AI 的內容

| 產生方式 | 交給 AI 的內容 |
|---|---|
| Dayflow 後端 | 來源日的卡片、來源日的觀察、最近 3 份其他日子的 Daily、三段的標題 |
| Claude、ChatGPT、Gemini、本機模型 | 只有來源日的卡片 |
| 不產生 | 不產生 Daily，畫面提示「No Daily provider is selected…」 |

第一次讀取產生方式時，已解鎖 Daily 者預設為 Dayflow 後端；其餘依時間軸的主要 AI 供應商對應（OpenAI 相容服務沒有對應，預設為不產生）。

# 自動產生

1. 每 5 分鐘檢查一次（App 啟動時也檢查一次），同一時間只跑一次檢查。
2. 條件：Daily 已解鎖、現在已過早上 4:00、目標日（今天）還沒有 Daily、找得到來源日、產生方式不是「不產生」且目前可用。
3. 每個目標日最多自動嘗試 3 次（含重新啟動 App 之後）；嘗試在呼叫 AI 前就計數，失敗不退還。
4. 成功時保存這一天的 Daily（含產生方式、模型、來源日與產生時間），並發送「Daily 已準備好」的通知。

# 實例化情境

小晴在週三早上 9:00 打開 Mac。9:00 的檢查發現週三還沒有 Daily，週二有 7 小時的卡片且尚未被用過，產生方式為 Claude。Dayflow 只把週二的卡片交給 Claude，取得重點、待辦與阻礙後保存為週三的 Daily，並跳出通知。Claude 當時若登入過期，這是第 1 次嘗試；9:05、9:10 再各試一次，三次都失敗後週三不再自動產生，小晴仍可手動按「重新產生」。
