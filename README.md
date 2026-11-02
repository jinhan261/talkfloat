# Saylori

Swift + SwiftUI / AppKit 原生 macOS 菜单栏英中实时翻译工具。支持所有系统声音或 Chrome，另一路收听当前系统麦克风；大字当前字幕、可拖动与八方向缩放的前文窗口、本地中英文字档案。

## 运行与构建

- Apple Silicon Mac，运行底线 macOS 14.2；开发需支持本项目 API 的最新 Xcode / Swift 6 工具链。
- 本机快速中文预览需要 macOS 26.4+ 及已安装英语识别与中英翻译模型；不可用时使用豆包定稿字幕。
- 豆包 AST 同声传译服务需要自己的 API Key，或 App ID + Access Token。在 App 的设置中填写，可仅本次使用或保存到 macOS 钥匙串。
- 授予系统音频和麦克风权限；凭据、录音和真实会议记录均不进入源码仓库。

```sh
swift test --package-path native --scratch-path .build-saylori
scripts/build-app.sh
open dist/Saylori.app
```

打包脚本使用本机 Apple Development 签名，或显式设置 `SAYLORI_SIGN_IDENTITY`。为保持录音授权与钥匙串身份稳定，不会偷偷退回临时签名。没有证书时仍可用 `swift build --package-path native --scratch-path .build-saylori` 检查编译。

## 当前行为与限制

- 系统声与麦克风分别采集、分别连接豆包，来源标签表示采音通道，不代表说话人身份。
- Apple 语音突显、参考回声消除与可调麦克风门限共同减少干扰。门限默认 −28 dBFS，可调 −50～−12；不是声压计，也不能区分同样响亮的两个人。
- 本机中文预览可修订，豆包随后定稿；不等待整段文字后再做逐字播放动画。
- 仅在本机保存已收到的中英文字，不保存录音。网络中断、未定稿和未收到译文会标注，不能保证零漏译。
- 普通启动不执行自动播放、采音或联调；集成测试必须显式启动并使用自己的凭据，会消耗 API 额度。

## 工程

`native/` 是当前原生工程；`scripts/` 是构建与验证工具。历史 HTML 品牌原型、真实会议文字、诊断日志、截图和签名产物保留在开发机，默认不跟踪。

- [架构与数据流](docs/architecture.md)
- [构建、验证与提交检查](docs/development.md)
- [本轮代码审查与优化](docs/code-review.md)

SpeexDSP 代码及其 BSD 许可证位于 `native/Sources/SpeexDSP/`，来源及版本见 `ORIGIN.md`。应用代码尚未指定开源许可证。
