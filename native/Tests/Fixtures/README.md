# 英语系统音频联调样本

本机 macOS say / Samantha 生成，145 词/分钟。不是用户会议录音。

原文：The meeting starts on Tuesday at ten. The budget is three thousand dollars, not thirteen thousand. Please send the revised proposal by Friday.

核对点：星期二十点；预算三千美元而不是一万三千美元；周五前发送修改后的提案。允许自然措辞差异，不允许金额/否定关系反转。

第一轮注意：原文只说 ten，豆包加译为“上午 10 点”，没有依据；by Friday 译成“周五前”可能缩窄截止范围。因此第二版样本显式说清上下午，避免把歧义当成准确性通过。

第二版 english-meeting-v2.aiff：The meeting starts on Tuesday at ten in the morning. The budget is three thousand dollars, not thirteen thousand. Please send the revised proposal before five on Friday afternoon.

第二版核对点：星期二上午十点；预算 3000 美元而非 13000 美元；周五下午五点前发送修订提案。

播放文件时，Saylori 音源选所有系统声音，开始翻译；该测试会按实际音频量请求豆包。真实译文验收结果另见 docs/verification.md。


`raining-question.aiff/.wav`：2026-11-02 使用 macOS Alex 声音合成，165 wpm；“Do you think” 后 800 ms 静音，再接 “tomorrow will be raining?”；后附一句完整长句。用于复现断句问题，不是用户录音、不是实际会议。Chrome 播放页为 `prototype/raining-question-test.html`；最终播放验收待 Mac 解锁。
