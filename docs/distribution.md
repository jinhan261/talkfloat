# TalkFloat 发布方案与当前差距

核查日期：2026-11-02。范围：原生 macOS 菜单栏英中字幕工具。本文是发布方案；当前没有公开仓库、Release、Homebrew 包或 App Store 上架。

## 推荐顺序

先完成 **Developer ID 签名与公证 → GitHub Releases 下载 → 自建 Homebrew Tap**，验证新用户安装和长期稳定性，再做 Mac App Store。是否开源是另一项决定：二进制下载、Homebrew 和 App Store 均不以开源为前提。

| 方式 | 用户如何安装 | 适合阶段 | 本项目还缺什么 |
| --- | --- | --- | --- |
| GitHub / 官网下载 | 下载 ZIP 或 DMG，拖到 Applications | 第一批公开试用 | Developer ID、Apple 公证、可公开下载的版本、首次安装验证 |
| Homebrew Cask | 一条 brew 命令安装或升级 | 技术用户、开源社区 | 上述签名包、固定版本 URL、SHA256、自建公开 Tap |
| Mac App Store | 商店搜索安装、商店更新 | 更广泛普通用户 | Sandbox 适配、商店构建、隐私和商品资料、审核与实机验证 |
| 源码自编译 | git clone 后构建、签名 | 开发者 | 合适的 Xcode、自有签名身份、构建说明；正式开源还要选择许可证 |

## 当前代码审查结论

| 项目 | 当前事实 | 发布前动作 |
| --- | --- | --- |
| 品牌 | TalkFloat；0.8.1 改用石墨灰/银白、黑白双行字幕标志，保留关于入口、权限说明与新导出标题 | 域名注册仍未执行；补公开支持页与正式品牌素材 |
| 签名 | 本机只有 Apple Development 身份；已启用 Hardened Runtime | 新建/取得 Developer ID Application，配置公证凭据；开发签名不能冒充正式分发签名 |
| 平台 | 只打包 arm64；声明最低 macOS 14.2；本地模式代码要求 macOS 26.4+ | 首发明确限定 Apple Silicon；在最低云端系统和本地支持系统分别实测，或收紧支持范围 |
| 功能 | 本地免费、豆包自带凭据；系统声 / Chrome + 麦克风；双语存档 | 新用户准备模型、拒绝权限、离线、切换输入设备、长会与停止尾句需发布回归 |
| 源码 | 当前私有；应用代码没有 LICENSE；SpeexDSP 有 BSD 许可并随 App 附带 | 作者选 MIT / Apache-2.0 等；逐项保留第三方声明，审计全部 Git 历史与可发布素材 |
| Sandbox | 当前 entitlements 只有 audio-input，没有 app-sandbox | 商店分支启用 Sandbox、出站网络及必要设备/文件权限；实测两路采音、模型下载、钥匙串与导出 |
| 隐私 | 模式说明、采音状态、无录音落盘；本地保存中英文本；豆包模式上传所选音频 | 首次云端使用明确说明接收方并征得同意；提供隐私政策、记录删除/保留设置和商店隐私填写 |
| 身份与升级 | 沿用 app.saylori.mac、钥匙串 service 与 Saylori/Recordings | 保持稳定，避免品牌改名触发数据分裂；若正式更换身份，先做迁移与旧安装升级测试 |
| 更新 | 无应用内更新器 | 首版可以手动下载 / brew upgrade；后续给直发版增加可信更新流程，商店版使用商店更新 |
| 质量边界 | 音量门限不是声纹识别；本地与豆包不承诺相同质量；已知仍可能误收附近人声 | 对外准确写支持范围，不宣传“只识别本人”“零漏译”或未经验证的延迟数字 |

## 路线一：直接下载与 Homebrew

Apple 的正式站外分发流程使用 Developer ID Application 和公证；公证是自动安全检查，不等于 App Store 人工审核。当前打包脚本可接收指定身份，但还未提交任何公证任务。[Developer ID](https://developer.apple.com/developer-id/)，[Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

发布者的步骤：

1. 确认 Apple Developer Program 会员和正式签名证书。当前会员标准价为每年 99 美元，支持地区可用本地币种。[会员说明](https://developer.apple.com/programs/whats-included/)
2. 用 Developer ID Application 签名，检查 Hardened Runtime、时间戳和所有内嵌代码。通过 `notarytool` 提交；成功后用 `stapler` 绑定票据，重新生成最终 ZIP / DMG。
3. 在另一台未安装过的 Mac 验证 Gatekeeper、首次权限、模型准备和字幕；不能让用户关闭 Gatekeeper 或删除 quarantine 来代替签名公证。
4. 发布固定版本附件与 SHA256。源码可独立决定是否公开，也可以创建只放安装包和问题反馈的公开 releases 仓库。
5. 建立例如 `jinhan261/homebrew-tap`，提交 `Casks/talkfloat.rb`。使用固定版本 URL、真实 SHA256、`app "TalkFloat.app"` 和明确的平台限制。升级只更新版本、URL、哈希，不删除用户存档。

**下列是发布后的目标命令，目前尚不可用：**

```sh
brew install --cask jinhan261/tap/talkfloat
brew upgrade --cask talkfloat
```

任何人都可以维护自建 Tap，无需先进入官方 homebrew-cask；实际首次安装可能按用户的 Homebrew 版本显示 Tap 信任提示。[Tap 文档](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)，[Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)。

源码开放后，可从公开仓库 clone 并执行 README 的构建命令。普通用户优先下载已签名成品，不应为安装工具而安装 Xcode。保持当前私有仓库时，只有获授权的协作者能 clone；不能把私人 GitHub Token 写进安装命令。

## 开源需要单独确定的事项

公开可见不自动等于开源；还需要授予使用、修改、分发等权利的许可证。[GitHub 许可证说明](https://docs.github.com/en/enterprise-cloud%40latest/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。

建议个人工具优先考虑 [MIT](https://choosealicense.com/licenses/mit/)，简单、便于社区采用；如重视显式专利许可可评估 [Apache-2.0](https://choosealicense.com/licenses/apache-2.0/)。两者都允许商业使用，不能同时声称“开源”又禁止一切商业使用。正式许可由作者决定，本轮没有擅自添加 LICENSE 或改仓库为公开。

公开前审计当前文件与整个提交历史：密钥、App ID/个人配置、真实会议文字、诊断截图、证书及测试视频均不能直接随仓库发布。本机的检查器只做常见格式检查，不能替代历史审计。系统语言模型不作为项目附件打包，继续由用户通过 Apple 的模型准备流程下载；豆包费用由用户自己的账号承担，不内置开发者 Token。

## 路线二：Mac App Store

流程为：注册 App ID / App Store Connect 记录，建立 Xcode 可归档的 macOS App 目标，配置商店签名与 Sandbox，上传构建，经 TestFlight 测试后补齐资料并提交审核。Swift Package 的核心代码可以继续复用；当前手工组装的开发签名 ZIP 不能直接当成商店提交包。[提交 App](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)，[TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

当前最大技术差距是 Sandbox，而不是改名。开启后应逐个验证 ScreenCaptureKit 系统声、Chrome 筛选、麦克风、系统语音处理、Apple 模型、钥匙串和归档路径；导出到用户选择的位置使用合适的系统文件面板和授权。不能假定增加一个 entitlement 就全部正常。[Mac App Store 规则 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)

商店材料包括图标、截图、说明、支持 URL、隐私政策 URL、年龄分级、出口合规回答、审核说明及可完整测试的方式。针对本工具，应解释为何需要系统音频权限、两路声音的区别、何时发送豆包、哪些记录保存在本机。采音状态应持续可见。[审核规则 2.5.14 与 5.1](https://developer.apple.com/app-store/review/guidelines/)

隐私标签按实际数据处理及第三方的保留行为填写：本地处理与云端服务分别评估，不能只凭“我们不保存录音”就填写不收集任何数据。Required Reason API / PrivacyInfo.xcprivacy 按当前目标平台、SDK 和上传校验核实；Apple 当前该文的列举平台不含原生 macOS，不机械套用 iOS 的强制要求。[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)，[Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

如果将来销售云端额度或订阅，需要单独设计计费与审核方案；用户自己填写第三方 API Key 不应被当作保证绕开商店支付规则的办法。我的建议是先把本地免费体验做完整，再决定商店版是否开放云端购买。没有必要为了上架先加入账号系统。

## 发布门槛与后续决定

最先补齐：正式证书/公证、可公开下载的版本、许可证决定、隐私和支持页面、全新 Mac 安装回归；然后做 Homebrew。App Store 另开 Sandbox 与归档适配任务，不与第一批直发试用捆绑。

用户已确定：TalkFloat 品牌；Apple 本地免费＋可选豆包；菜单栏形态。尚未确定：是否公开源码、采用何种许可证、是否在商店收费、公开发布地区。本文已与 README、开发文档、现有产品规格和品牌规格同步；这些选择变化时再调整发布路线。
