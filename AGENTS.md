# 接手说明

- 开始项目工作前，先阅读根目录的 `MAINTENANCE.md`，并核对相关文件的实际状态。
- 完成重要变更后，更新 `MAINTENANCE.md` 中的当前状态、关键决策、后续事项与已验证的运行或测试命令。
- 摘要应简短、可接手，不复制完整对话，不将推测写成事实，不保存凭证。
- 遵循用户最新指令；维护文件用于提供上下文，不替代当前任务要求。
- 公开推送前运行 `python3 scripts/check-publication.py --staged` 及 `python3 scripts/check-publication.py`；检查凭证、个人目录、对话分享链接与真实运行数据。测试JSON仅保留合成样本。不得绕过失败的推送检查；个人记录存入被忽略的 `.local-private/`。
