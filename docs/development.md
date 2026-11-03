# 开发与验证

## 环境与构建

本机验证环境：Apple Silicon、macOS 27.0.1、Swift 6.4.2 / macOS 27 SDK。Swift Package 最低部署 macOS 14.2，Swift 5 language mode。本地模型模式及快速预览需 macOS 26.4+ 和已下载的系统模型；较早系统的运行路径尚需实机验证。

```sh
swift test --package-path native --scratch-path .build-talkfloat
scripts/build-app.sh
```

构建脚本从 `native/Resources/AppIcon.png` 制作图标，输出 `dist/Build.noindex/TalkFloat.app` 和版本 ZIP，不依赖历史 HTML 原型目录。签名使用 `TALKFLOAT_SIGN_IDENTITY`，未设置时仅在本机恰有一个 Apple Development 证书时自动选择；兼容旧环境变量 `SAYLORI_SIGN_IDENTITY`；没有唯一可用证书会明确失败；开发者可以显式传入 `--ad-hoc` 做本机源码试用，绝不静默退回临时签名。证书私钥、钥匙串、签名 ZIP 不提交 Git。

需要签名安装才能稳定检验系统录音权限和钥匙串读取。更换签名身份可能触发重新授权；在同一开发机上应显式固定原身份。0.8.5 分发版已完成 Developer ID 签名，DMG 公证 Accepted、票据和 Gatekeeper 验证通过，作为私有预览 Release 提供下载。

### 从源码安装

需要完整 Xcode 与包含 macOS 26.4 Speech / Translation API 的 SDK。当前私有阶段还需仓库访问权限。

```sh
git clone https://github.com/jinhan261/talkfloat.git
cd talkfloat
scripts/install-local.sh --ad-hoc
```

脚本编译并安装到 `~/Applications/TalkFloat.app`。临时签名仅供本机试用，重新构建可能要求再次授权，且脚本拒绝覆盖已有证书签名版。持有开发证书时用 `TALKFLOAT_SIGN_IDENTITY='你的证书 SHA-1' scripts/install-local.sh` 固定签名。不要关闭系统安全检查来替代签名。

### DMG 打包

已有 `dist/Build.noindex/TalkFloat.app` 后运行 `scripts/package-dmg.sh --development`，得到带 `-development.dmg` 后缀的开发预览及 SHA256 文件。内容仅有签名 App、Applications 链接及安装说明；不打包本机会议记录、模型、密钥、诊断文件。脚本核对签名和 arm64、拒绝覆盖已有产物、校验镜像并自动清理项目内临时打包目录，不重签或替换已安装 App。

正式模式为 `scripts/package-dmg.sh --release`：需要源 App 已有 Developer ID Application 签名，并设置同类 `TALKFLOAT_SIGN_IDENTITY` 和已配置的 `TALKFLOAT_NOTARY_PROFILE`。它给 DMG 签名，提交公证，验证 Accepted 后绑定票据并检查 Gatekeeper，最后生成 SHA256。不会自动创建证书、索取密码或上传 GitHub Release。开发证书不能走正式模式；0.8.5 已实际走通正式分支：Apple Accepted、票据绑定/验证、DMG 与内含 App 的 Gatekeeper 检查均通过。详细顺序见发布文档。

可用 `TALKFLOAT_APP_PATH` 指向独立的签名 App 副本；脚本仍将 DMG 和校验文件输出到项目 `dist/`，不修改源 App。额外构建副本应放在 `.noindex` 目录内或保存为 ZIP，避免被应用搜索收录。

## 自动与实机验证

单元测试覆盖协议编码、两路字幕配对、暂停后历史、存档修订、疑似回声、门限、布局与发送策略。DSP 样本是合成信号；`native/Tests/Fixtures` 中英语素材由 macOS `say` 生成，不是会议录音。

可选实机集成检查需要 App 已安装到 `~/Applications/TalkFloat.app`，退出当前实例，本地模式先准备语言模型；豆包模式配置自己的凭据，然后执行：

```sh
python3 scripts/run-native-test.py docs/local-integration --engine local
python3 scripts/analyze-engine-test.py docs/local-integration
python3 scripts/check-meeting-archive.py docs/local-integration
```

使用一个全新的输出目录，防止上轮 marker/status 被复用。此测试自动播放合成英语，经真实系统采音和所选引擎验证暂停、恢复、隐藏字幕、窄窗、存档、停止与取消；`--engine doubao` 会消耗少量 API 额度；`--engine local` 无 API 调用。默认关闭麦克风，显式加 `--with-microphone` 才收听现场。退出测试后恢复原音源、麦克风开关和字幕位置尺寸。

`--chrome` 只切换采音目标，不自动播放浏览器；使用该模式需自行安排测试页和两个播放结束 marker。诊断输出包含字幕文字，只保存在本机，不上传仓库。启动参数中的 `--self-test`、`--meeting-test` 与 `--ui-review` 用于测试，普通启动不会主动采音。

## 提交检查与清理

```sh
git add native scripts README.md .gitignore docs/architecture.md docs/development.md docs/code-review.md
python3 scripts/check-repository.py
git diff --cached --check
git diff --cached --stat
```

上传前还需人工审阅新增文本。扫描器检查 Git index 的范围、常见凭据格式、绝对用户路径；不能检测所有无前缀 Token。禁止提交真实文字记录、测试日志、截图、个人配置和密钥。历史原型及本机产品决策资料保留在开发机。

完成开发、构建与测试后，核实本项目 `.build-talkfloat`、`native/.build` 以及有项目归属证据的 DerivedData/临时打包目录，再清理旧缓存。保留源代码、签名 App、版本 ZIP/DMG、当前 dSYM、已安装 App 和 App 数据。禁止笼统清空全部 DerivedData。

## 引擎对照

`--meeting-test OUTPUT --engine local|doubao --with-microphone` 等待 OUTPUT/start，再开始真实采音；OUTPUT/finish 结束并存档。默认 Chrome，`--system-test` 改为所有系统声音。`--no-cloud-preview` 仅用于测量豆包原生返回，普通豆包模式仍保留本地快速预览。测试结束恢复原音源、模式和麦克风偏好。

`analyze-engine-test.py OUTPUT` 分引擎、分音源计算模型时间轴至文字可用的耗时，不能当作人工标注声学延迟或屏幕显示延迟。两个引擎断句不同，汇总不能直接当成相同句子的速度差；应补充同文匹配样本。`check-meeting-archive.py OUTPUT [REFERENCE]` 对账定稿事件与测试目录的 `archive.plist` 快照、用户 Markdown（兼容历史 JSON 测试输出），参考文稿用于定位差异，不生成未经验证的准确率。

## TalkFloat 改名兼容

0.8.0 对外名称、可执行文件、App/ZIP 和错误提示均为 TalkFloat。为了沿用已有授权、偏好和记录，Bundle ID `app.saylori.mac`、钥匙串 service `app.saylori.credentials`、内部通知名以及 `Saylori/Recordings` 保持稳定；源码的 SayloriCore 模块名同样保留。SPM 主可执行目标改为 TalkFloat，源文件目录通过 path 显式指定。后续若改这些持久化标识，必须先实施并验证迁移。

2026-11-03 按用户要求将 GitHub 仓库从 `jinhan261/saylori` 改为 `jinhan261/talkfloat`，README 和当前 Git remote 同步。此为同一仓库改名，历史和 private 状态保留；不改变上述 App 持久化身份，也不移动开发者现有工作目录。

## 品牌图标

`BrandArtwork.swift` 是菜单标志与 App 图标的共用轮廓。打包脚本在生成 icns 前调用可执行文件的 `--render-brand-icon` 入口，将确定性的纯色 PNG 输出到 `native/Resources/AppIcon.png`；此入口不启动窗口、采音或读取钥匙串。0.8.1 使用石墨色底与浅色字幕标志，原 imagegen 选定方案作为形状来源。

0.8.2 增加 `scripts/install-local.sh [--ad-hoc]`，安装到用户 Applications 并保留旧安装备份；正在运行时拒绝替换。安装命令见本文。仓库公开前额外执行 `python3 scripts/check-repository.py --history`，检查所有可达历史中的文本与文件范围。


## 构建与本机安装清理（0.8.5）

展开的构建 App 存入 `dist/Build.noindex/`，版本 ZIP/DMG 仍位于 `dist/`。构建先在项目临时目录组装全新 Bundle，签名验证后才替换构建输出，避免旧资源混入。安装脚本将旧版压缩为 ZIP 并验证归档，替换失败时恢复原安装；不再产生会被启动器收录的 `.app.backup` 目录。正常退出或失败时清理自己的临时安装目录。

不要同时保留 `~/Applications/TalkFloat.app` 与 `/Applications/TalkFloat.app`。DMG 用户保留自己选择的一个安装位置即可；源码安装脚本默认使用前者。移动或卸载 App 不应删除钥匙串、偏好及会议记录。
