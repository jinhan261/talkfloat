# TalkFloat

原生 macOS 菜单栏实时字幕工具，将英语会议、视频和麦克风发言翻译成简体中文。

- 收听全部系统声音或 Chrome，可同时开启麦克风，并区分字幕来源。
- 悬浮字幕显示当前句和最近内容，支持拖动、缩放、透明度与字号调整。
- 在 Apple 本地模型和豆包云端之间切换，每场会话自动保存中英 Markdown。

## 如何实现

使用 **Swift、SwiftUI 和 AppKit** 构建。系统声音通过 ScreenCaptureKit 获取，麦克风通过 AVAudioEngine 获取，两路独立处理。

| 模式 | 处理流程 | 费用与数据 |
| --- | --- | --- |
| 本地模型 | SpeechAnalyzer / SpeechTranscriber 转写英语，再由 TranslationSession 的低延迟策略翻译 | 无 API 费用；首次下载 Apple 语言资源后在本机处理 |
| 豆包云端 | 通过 WebSocket 将所选音频发送至火山引擎同声传译服务 | 使用自己的凭据，按服务用量计费 |

字幕随识别结果更新，停止时收尾并保存已收到的中英文本。不保存录音。本地模式不会自动切换到付费服务。

## 安装

**Apple Silicon（M 系列）Mac。** 本地模式需要 **macOS 26.4+**；豆包模式声明最低 macOS 14.2，较早系统仍待完整实机验证。暂不提供 Intel 版本。

1. 在 [Releases](https://github.com/jinhan261/talkfloat/releases) 下载 `TalkFloat-版本号-macOS-arm64.dmg`。
2. 打开 DMG，将 **TalkFloat** 拖入 **Applications**。
3. 从 Applications 启动，点击屏幕右上角的菜单栏图标。

发布的 DMG 使用 Developer ID 签名并通过 Apple 公证，附有 SHA256 校验文件。当前仓库保持私有，下载需要登录有访问权限的 GitHub 账号。

升级前先结束并保存会话、退出旧版，再替换原 App。只保留一个安装位置；如果旧版位于 `~/Applications`，请替换那里或先移除旧版。

## 使用

1. **选模式**：本地模式点击“准备本地语言模型”；豆包模式在“设置 → 服务连接”填写 API Key，或 App ID 与 Access Token。
2. **选音源**：选择全部系统声音或 Chrome；需要自己的发言时开启麦克风。按 macOS 提示授予相应采音权限。
3. **开始翻译**：播放英语或开始会议，悬浮窗口显示中英字幕；可暂停和继续。
4. **结束并存档**：每场会话生成一个 `.md` 文件。保存位置可在“设置 → 会议记录”更改。

目前仅支持英语 → 简体中文。来源标签表示采音通道，麦克风过滤不能保证只识别本人；数字、姓名及专业术语请核对。使用前请告知会议参与者。

[隐私说明](PRIVACY.md) · [源码构建](docs/development.md) · [架构](docs/architecture.md) · [反馈问题](https://github.com/jinhan261/talkfloat/issues)

## 许可证

应用代码采用 [MIT](LICENSE)，SpeexDSP 保留其 [BSD 许可证](native/Sources/SpeexDSP/COPYING)。Apple 语言模型和豆包服务遵循各自条款，不随项目分发。
