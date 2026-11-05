# TalkFloat 发布方案与当前差距

核查日期：2026-11-05。范围：原生 macOS 菜单栏英中字幕工具。用户本日明确要求公开仓库，MIT 源码与 0.8.7 预览版 DMG 均可公开获取；无需 GitHub 登录。尚无 Homebrew 包或 App Store 版本。以下早期 private 记录保留为历史，当前状态以本段与末尾公开决定为准。

2026-11-03 用户要求将仓库名统一为 TalkFloat，并希望通过 DMG 简化安装。已将同一仓库改为 [jinhan261/talkfloat](https://github.com/jinhan261/talkfloat)，保留 private 和提交历史；本地 remote 与源码安装地址已同步。优先准备 DMG 直发，不因此自动公开源码或发布未公证成品。来源：用户当前决定；适用当前仓库与站外分发；用户明确公开或取得正式签名条件后再推进发布。

后续同日用户授权继续签名、公证，并先要求通过后上传 Release 草稿、仓库保持私有。`v0.8.4` / build 36 已完成 Developer ID 签名，Apple 返回 Accepted，日志无 issues；公证票据、DMG 与内含 App 的 Gatekeeper、镜像校验、App 完整文件对账均通过。DMG 和 SHA256 文件已加入私有 `v0.8.4` prerelease 草稿，尚未发布或改变仓库可见性。此前 222 个历史文本版本的常见敏感格式扫描无发现，不能替代完整安全审计。随后用户反馈 Releases 为空，要求复查、整理 README 和重复 App，并自行下载 DMG 试装：本轮发布 0.8.5 私有预览版，保留私有仓库。面向公众发布前仍需全新 Mac 安装验收及明确公开下载入口。

## 推荐顺序

先完成 **Developer ID 签名与公证 → GitHub Releases 下载 → 自建 Homebrew Tap**，验证新用户安装和长期稳定性，再做 Mac App Store。是否开源是另一项决定：二进制下载、Homebrew 和 App Store 均不以开源为前提。

| 方式 | 用户如何安装 | 适合阶段 | 本项目还缺什么 |
| --- | --- | --- | --- |
| GitHub / 官网下载 | 下载 ZIP 或 DMG，拖到 Applications | 第一批公开试用 | 签名公证与公开下载入口已完成；待更多全新 Mac 安装与升级验证 |
| Homebrew Cask | 一条 brew 命令安装或升级 | 技术用户、开源社区 | 上述签名包、固定版本 URL、SHA256、自建公开 Tap |
| Mac App Store | 商店搜索安装、商店更新 | 更广泛普通用户 | Sandbox 适配、商店构建、隐私和商品资料、审核与实机验证 |
| 源码自编译 | git clone 后构建、签名 | 开发者 | 合适的 Xcode；已提供自编译安装脚本、显式 ad-hoc 路径与 MIT 许可证 |

## 当前代码审查结论

| 项目 | 当前事实 | 发布前动作 |
| --- | --- | --- |
| 品牌 | TalkFloat；0.8.2 改用石墨灰/银白、黑白双行字幕标志，保留关于入口、权限说明与新导出标题 | 域名注册仍未执行；补公开支持页与正式品牌素材 |
| 签名 | 0.8.7 使用 Developer ID 签名；DMG 已公证并绑定票据，Gatekeeper 接受 | 全新 Mac 与升级验证；开发签名不能冒充正式分发签名 |
| 平台 | 只打包 arm64；声明最低 macOS 14.2；本地模式代码要求 macOS 26.4+ | 首发明确限定 Apple Silicon；在最低云端系统和本地支持系统分别实测，或收紧支持范围 |
| 功能 | 本地模型、豆包自带凭据；系统声 / Chrome + 麦克风；双语存档 | 新用户准备模型、拒绝权限、离线、切换输入设备、长会与停止尾句需发布回归 |
| 源码 | 当前公开；应用代码已采用 MIT；SpeexDSP 保留 BSD 许可，两者随 App 附带 | 已补许可证、隐私、贡献和安全说明；公开前审计全部 Git 历史与可发布素材 |
| Sandbox | 当前 entitlements 只有 audio-input，没有 app-sandbox | 商店分支启用 Sandbox、出站网络及必要设备/文件权限；实测两路采音、模型下载、钥匙串与导出 |
| 隐私 | 模式说明、采音状态、无录音落盘；本地保存中英文本；豆包模式上传所选音频 | 首次云端使用明确说明接收方并征得同意；提供隐私政策、记录删除/保留设置和商店隐私填写 |
| 身份与升级 | 沿用 app.saylori.mac 和钥匙串 service；0.8.7 默认记录位于 TalkFloat/Recordings | 权限身份稳定；不自动导入旧 Saylori 资料，已选自定义目录不变 |
| 更新 | 无应用内更新器 | 首版可以手动下载 / brew upgrade；后续给直发版增加可信更新流程，商店版使用商店更新 |
| DMG | 0.8.7 已公证，包含 App + Applications 链接 + 安装说明；DMG 和 SHA256 为公开预览 Release 附件 | 更多全新 Mac 验收；开发包继续标注 development |
| 质量边界 | 音量门限不是声纹识别；本地与豆包不承诺相同质量；已知仍可能误收附近人声 | 对外准确写支持范围，不宣传“只识别本人”“零漏译”或未经验证的延迟数字 |

## 路线一：直接下载与 Homebrew

Apple 的正式站外分发流程使用 Developer ID Application 和公证；公证是自动安全检查，不等于 App Store 人工审核。当前打包脚本已走通 Developer ID 签名、公证 Accepted、票据绑定和 Gatekeeper 检查。[Developer ID](https://developer.apple.com/developer-id/)，[Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

发布者的步骤：

1. 确认 Apple Developer Program 会员和正式签名证书。当前会员标准价为每年 99 美元，支持地区可用本地币种。[会员说明](https://developer.apple.com/programs/whats-included/)
2. 用 Developer ID Application 签名，检查 Hardened Runtime、时间戳和所有内嵌代码。通过 `notarytool` 提交；成功后用 `stapler` 绑定票据，重新生成最终 ZIP / DMG。
3. 在另一台未安装过的 Mac 验证 Gatekeeper、首次权限、模型准备和字幕；不能让用户关闭 Gatekeeper 或删除 quarantine 来代替签名公证。
4. 发布固定版本附件与 SHA256。源码可独立决定是否公开，也可以创建只放安装包和问题反馈的公开 releases 仓库。
5. 建立例如 `jinhan261/homebrew-tap`，提交 `Casks/talkfloat.rb`。使用固定版本 URL、真实 SHA256、`app "TalkFloat.app"` 和明确的平台限制。升级只更新版本、URL、哈希，不删除用户存档。

### DMG 的当前可执行步骤

本机原有的 0.8.4 App 使用 Apple Development 签名，签名本身验证通过，但 Gatekeeper 评估拒绝，且没有 stapled ticket。随后已取得可用 Developer ID Application 身份，独立分发副本已签名，正式 DMG 已公证并通过完整性、票据与 Gatekeeper 检查；旧开发包的信任状态不会因此改变。当前可生成开发预览来检查安装文件结构：

```sh
scripts/package-dmg.sh --development
```

文件名带 `-development.dmg`，仅用于打包验收，不创建 GitHub Release。正式发布者先取得 Developer ID Application 身份，并通过 Apple 官方流程将公证凭据保存为本机 notarytool Keychain profile；不要把密码或私钥写进仓库。随后：

```sh
# 身份为 Developer ID Application，profile 为已配置的钥匙串配置名。
export TALKFLOAT_SIGN_IDENTITY='你的 Developer ID Application 证书 SHA-1'
export TALKFLOAT_NOTARY_PROFILE='你的公证配置名'
scripts/build-app.sh
scripts/package-dmg.sh --release
```

正式模式只接受 Developer ID 签名的 App，给镜像签名后提交公证；只有 Accepted、票据绑定和 Gatekeeper 检查都通过，才输出正式命名的 DMG 和 SHA256。开发路径及拒绝错误签名的检查已验证；正式分支已实际公证通过，票据与 Gatekeeper 验证成功。脚本不替换正在使用的安装版，也不发布 GitHub Release；全新 Mac 首装与旧版升级仍需单独验收。

通过验收后，把 `.dmg` 和 `.dmg.sha256` 作为 Release 附件，用户下载 DMG、拖到 Applications、从菜单栏使用即可。GitHub 自动附带的 “Source code” ZIP 是源码，不是安装包。[GitHub Releases 说明](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

仓库与已发布的 Releases 现已公开，用户可直接下载 DMG，无需登录 GitHub。旧草稿仍保持草稿，不作为公开下载入口。

**下列是发布后的目标命令，目前尚不可用：**

```sh
brew install --cask jinhan261/tap/talkfloat
brew upgrade --cask talkfloat
```

任何人都可以维护自建 Tap，无需先进入官方 homebrew-cask；实际首次安装可能按用户的 Homebrew 版本显示 Tap 信任提示。[Tap 文档](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)，[Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)。

可从公开仓库 clone 并执行[开发文档](development.md)的构建命令。普通用户优先下载已签名成品，不必安装 Xcode；安装命令无需 GitHub Token。

## 开源需要单独确定的事项

公开可见不自动等于开源；还需要授予使用、修改、分发等权利的许可证。[GitHub 许可证说明](https://docs.github.com/en/enterprise-cloud%40latest/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。

用户于 2026-11-03 明确选择 MIT，已添加 LICENSE 并保留 SpeexDSP BSD 许可证。此决定适用于项目应用代码；Apple 的模型资源不随仓库分发。仓库公开是另一步，本次准备不会将开发签名 ZIP 宣称为正式公证成品。

公开前审计当前文件与整个提交历史：密钥、App ID/个人配置、真实会议文字、诊断截图、证书及测试视频均不能直接随仓库发布。本机的检查器只做常见格式检查，不能替代历史审计。系统语言模型不作为项目附件打包，继续由用户通过 Apple 的模型准备流程下载；豆包费用由用户自己的账号承担，不内置开发者 Token。

## 路线二：Mac App Store

流程为：注册 App ID / App Store Connect 记录，建立 Xcode 可归档的 macOS App 目标，配置商店签名与 Sandbox，上传构建，经 TestFlight 测试后补齐资料并提交审核。Swift Package 的核心代码可以继续复用；当前手工组装的开发签名 ZIP 不能直接当成商店提交包。[提交 App](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)，[TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

当前最大技术差距是 Sandbox，而不是改名。开启后应逐个验证 Core Audio Process Tap 系统声、Chrome 筛选、麦克风、系统语音处理、Apple 模型、钥匙串和归档路径；导出到用户选择的位置使用合适的系统文件面板和授权。不能假定增加一个 entitlement 就全部正常。[Mac App Store 规则 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)

商店材料包括图标、截图、说明、支持 URL、隐私政策 URL、年龄分级、出口合规回答、审核说明及可完整测试的方式。针对本工具，应解释为何需要系统音频权限、两路声音的区别、何时发送豆包、哪些记录保存在本机。采音状态应持续可见。[审核规则 2.5.14 与 5.1](https://developer.apple.com/app-store/review/guidelines/)

隐私标签按实际数据处理及第三方的保留行为填写：本地处理与云端服务分别评估，不能只凭“我们不保存录音”就填写不收集任何数据。Required Reason API / PrivacyInfo.xcprivacy 按当前目标平台、SDK 和上传校验核实；Apple 当前该文的列举平台不含原生 macOS，不机械套用 iOS 的强制要求。[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)，[Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

如果将来销售云端额度或订阅，需要单独设计计费与审核方案；用户自己填写第三方 API Key 不应被当作保证绕开商店支付规则的办法。我的建议是先把本地模型体验做完整，再决定商店版是否开放云端购买。没有必要为了上架先加入账号系统。

## 发布门槛与后续决定

正式证书、公证、MIT 和隐私说明已完成。公开下载及 Issues 支持入口已提供；接下来补齐更多全新 Mac 安装和升级回归，然后做 Homebrew。App Store 另开 Sandbox 与归档适配任务，不与第一批直发试用捆绑。

用户已确定：TalkFloat 品牌；Apple 本地模型＋可选豆包；菜单栏形态；计划开源并采用 MIT。2026-11-03 用户在公开确认中选择“先保留私有”：当前仓库保持 private，MIT 与安装准备保留，不自动切换公开。仅用户后续明确要求时重新讨论公开时点。尚未确定：是否在商店收费、公开发布地区。本文已与 README、开发文档、现有产品规格和品牌规格同步；这些选择变化时再调整发布路线。

## 2026-11-05：预览版与展示资料

用户要求采用 TalkFloat 存储名称，并参考 Mimi 的 README 信息结构制作中英文介绍。0.8.7 实现新默认目录，中文 README 与 `README.en.md` 保持功能、安装、实现与限制一致；MIT 不变。加入本机实际组件导出和用户指定的演示录屏，第三方视频画面单独标注素材范围；公开前核实使用权或替换为自有演示。本文、架构和隐私说明已同步。

0.8.7 DMG 已由 Developer ID 签名、公证 Accepted、绑定票据并通过 Gatekeeper，继续作为现有私有仓库的预览 Release。公开仓库、扩展翻译语言、App 英文界面和路线图均未在本次授权范围内；只有用户后续明确要求时调整。

## 公开决定（2026-11-05）

来源：用户明确要求“把这个仓库设置成公开的”。适用于 jinhan261/talkfloat 的源码、现有提交历史与已发布 Release；覆盖此前“先保留私有”的决定，旧草稿不自动发布。MIT 和开发者预览定位保持不变。中英 README、开发说明、素材说明及 0.8.7 Release 文案同步公开下载口径。276 个历史文本版本的常见凭据/私人路径与文件范围检查无发现；检查器并非完整安全审计。安装包沿用已公证的 0.8.7，不修改二进制或签名。X 文案仅交付用户，不代为发送。仅用户后续明确改变发布范围时再讨论可见性。
