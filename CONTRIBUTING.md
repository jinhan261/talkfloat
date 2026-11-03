# 贡献说明

欢迎修复与现有英中字幕流程相关的问题。提交前先阅读 README、docs/architecture.md 与 docs/development.md，保持改动聚焦。

1. 用合成内容复现问题，避免把真实会议、账号或凭据加入仓库。
2. 为存档、字幕配对、音频队列等行为改变补充有意义的测试；纯文字或配色改动检查实际原生界面即可。
3. 运行 `swift test --package-path native --scratch-path .build-talkfloat`，核对受影响交互。未实测设备、最低系统或云端额度时明确说明。
4. 暂存后运行 `python3 scripts/check-repository.py` 和 `git diff --cached --check`。新增对外文档需同步检查器的允许范围。
5. PR 描述说明问题、最终行为和验证结果。不要更改 Bundle ID、钥匙串标识或用户数据路径来解决显示名称问题。

不要提交构建缓存、签名产物、私人截图、会议记录或密钥；第三方代码保留原许可。贡献的项目代码按 MIT 许可证提交。作者保留是否合并的判断。
