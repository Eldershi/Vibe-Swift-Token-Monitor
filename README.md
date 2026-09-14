# Vibe Swift Token Monitor

**简体中文 · [English](README.en.md)**

macOS 原生用量监视器，集中查看 Codex 用量、账号额度与活动历史。内置独立后台，无需安装 Node.js 或运行原 Electron 应用。

## 下载

### [⬇ 下载最新版 0.5.2 · Apple Silicon](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.5.2/Token-Monitor-Native-0.5.2-35-arm64.zip)

**macOS 26+ · Apple Silicon · 构建 35**

[更新说明](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/latest) · [SHA-256 校验文件](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.5.2/SHA256SUMS)

当前主要针对 Codex，其他工具仅实验适配。项目仍处于基础验证阶段，尚未公证，暂不推荐普通用户直接使用；目前实际测试系统为 macOS 27。

## 功能

- **用量与额度**：今天、本月、总计，模型与设备明细，以及账号报告的可用额度。
- **活动历史**：热力图、趋势和按年/月展开的每日记录，缺失数据与真实零值分别显示。
- **可定制首页**：栏目显隐与排序、额度选项、主题色；支持简体中文与英语。
- **独立采集与 Hub**：关闭界面后后台可继续采集，也可接入已有 Hub 查看多设备汇总。
- **确认后更新**：支持 GitHub 正式版本检查；自动检查默认关闭，下载安装由用户确认。

费用为 **API 等价估算**，不是订阅账单。本项目并非 OpenAI 官方应用。

## 开始使用

1. 下载并解压，将应用移入“应用程序”文件夹；升级前退出旧界面并保留旧副本。
2. 打开应用，按需允许后台运行，等待首次扫描。
3. 在设置 → 数据选择本机采集，或配置已有 Hub。账号额度失效时，在原工具重新登录。

0.5.1 及更早版本请手动下载升级；0.5.2 起可在设置 → 关于检查后续更新。

[使用与卸载](docs/USAGE.md) · [从源码构建](docs/BUILDING.md) · [反馈问题](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/issues)

## 来源与许可

本项目是独立维护的 macOS 原生衍生实现，复用 [Javis603/token-monitor](https://github.com/Javis603/token-monitor) v0.56.0 的部分 MIT 后台，以及 Node.js、Tokscale 和 Sparkle；不包含 Electron 前端，也不是上游官方客户端。

[第三方声明](TokenMonitorNative/THIRD_PARTY_NOTICES.md) · [后台来源](TokenMonitorNative/Backend/UPSTREAM.md)

上游版权与许可证保留；本仓库尚未为新增代码另行指定统一开源许可证。
