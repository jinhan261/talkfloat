# TalkFloat

轻量的原生 macOS 菜单栏英中同声字幕工具。收听所有系统声音或 Chrome，也可独立收听麦克风；大字当前字幕、可拖动与八方向缩放的前文窗口、自动双语 Markdown 存档。

- **本地模型**：使用 Apple 的设备端语音识别和翻译，无 API 费用；首次下载语言模型后在本机处理。
- **豆包云端**：使用你自己的火山引擎同声传译凭据，服务按账号用量计费，不附赠额度。
- **会议记录**：设置 → 会议记录 → 选择文件夹。每场一个 `.md`，包含中英文本、音源和未定稿/中断提示；不保存录音。

Swift + SwiftUI / AppKit，Apple Silicon。现名 TalkFloat，原名 Saylori；旧应用身份、偏好、钥匙串和默认记录目录保持兼容。

## 从源码安装

需要完整 Xcode 与 Command Line Tools，SDK 必须包含 macOS 26.4 的 Speech / Translation API。本项目实际构建环境为 Swift 6.4.2 / macOS 27 SDK。首次使用 Xcode 请完成其正常初始化。

仓库公开后，任何人都可运行以下命令；当前私有阶段需要仓库访问权限：

```sh
git clone https://github.com/jinhan261/saylori.git
cd saylori
scripts/install-local.sh --ad-hoc
```

脚本在本机编译并安装到 `~/Applications/TalkFloat.app`。`--ad-hoc` 适合没有开发证书的本机源码试用，不是公证分发包；重新构建后 macOS 可能要求重新授予采音/钥匙串权限。不会替换已有证书签名版本，以免破坏原身份。升级前先在 App 中结束会议并退出。

若有稳定开发证书，推荐固定同一签名身份安装：

```sh
security find-identity -v -p codesigning
TALKFLOAT_SIGN_IDENTITY='你的证书 SHA-1' scripts/install-local.sh
```

多个证书时必须显式选择，避免更新意外换身份。也可只构建、不安装：`scripts/build-app.sh --ad-hoc`。签名产物在 `dist/`，不提交仓库。项目不要求关闭 Gatekeeper、SIP 或删除 quarantine。

## 首次使用

1. 打开右上角 TalkFloat 菜单栏图标。选择“本地模型”，点击“准备本地语言模型”，按 Apple 系统提示下载英语识别及英中翻译资源。
2. 本地模式要求 **macOS 26.4+**；不满足条件时可手动选择豆包。云端部署最低声明为 macOS 14.2，较早系统尚缺实机覆盖；首轮使用建议选择已验证的新系统。
3. 豆包模式在设置 → 服务连接中填写你自己的 API Key，或 App ID + Access Token。可仅本次使用或保存到 macOS 钥匙串；不把密钥写入代码。
4. 授予系统声音权限；需要麦克风时开启该开关并授权。Chrome 音源筛选整个 Chrome 进程的音频，不是某一个标签页。
5. 点击开始翻译；结束时点击“结束并存档”。菜单底部“会议记录”打开保存文件夹。首次默认位置是 `~/Library/Application Support/Saylori/Recordings`，可随时在无进行中会议时更改。

## 本地模型是怎样工作的

系统声音由 ScreenCaptureKit 获取，麦克风由 AVAudioEngine 获取；两路独立处理。`SpeechAnalyzer` + `SpeechTranscriber` 的渐进转写先输出英语，再由 `TranslationSession` 的已安装英语 → 简体中文模型翻译，使用低延迟策略。识别修订会更新字幕，最终结果写入记录。

这是 Apple 提供的设备端模型管线，不是项目自带的 Whisper、Qwen 或大语言模型。模型由 Apple 下载和管理，不随源码分发，Apple 未通过这些 API 提供可选择的权重版本。下载资源需要网络；本地模式不调用豆包、不上传音频或文字，不会偷偷回退到付费服务。翻译质量与豆包不同，数字、姓名和术语必须核对。

## 使用边界与隐私

- 目前仅英语 → 简体中文。来源标签表示采音通道，不代表本人声纹；附近较响的人声也可能被麦克风收录。
- 可调麦克风门限、系统语音处理和参考回声消除用于减少干扰，不能保证只保留本人声音或零漏译。
- 暂停/继续属于同一份记录。历史字幕由新到旧显示，文档按会议顺序保存；只保存实际收到的文字，缺译和未定稿有明确提示。
- 用户文件夹仅生成 Markdown；异常退出恢复使用 App 私有目录中的临时检查点，成功结束后移除。旧版本 JSON 原件移入私有备份，旧 Markdown 留在原处。
- 本项目无账号、广告或遥测。豆包模式会将所选音频发送给火山引擎；费用及服务端数据处理遵循你的服务账号条款。
- 使用前向会议参与者说明采音和翻译；选择 iCloud、共享盘等存档目录时，文件会按该目录自己的同步规则处理。

完整说明见 [隐私说明](PRIVACY.md)。不要在 Issue 中发送密钥、未脱敏会议记录或诊断文件。

## 开发与发布

```sh
swift test --package-path native --scratch-path .build-talkfloat
python3 scripts/check-repository.py
python3 scripts/check-repository.py --history
```

- [架构与数据流](docs/architecture.md)
- [构建、测试与清理](docs/development.md)
- [贡献说明](CONTRIBUTING.md)
- [发布方案：直接下载、Homebrew、Mac App Store](docs/distribution.md)
- [安全问题反馈](SECURITY.md)

目前是开发者预览版；没有公开安装包、Homebrew Cask 或 App Store 版本。公开源码与发布公证成品是两个步骤：普通用户的成品安装仍需 Developer ID 签名、公证和全新 Mac 验收。不要把开发签名 ZIP 当作已公证产品分发。

## 许可证

应用代码采用 [MIT](LICENSE)。SpeexDSP 保留其 [BSD 许可证](native/Sources/SpeexDSP/COPYING)，来源和版本见 [ORIGIN.md](native/Sources/SpeexDSP/ORIGIN.md)，两份许可证均随 App 打包。Apple 框架与语言模型、豆包服务不属于本项目的 MIT 授权范围。
