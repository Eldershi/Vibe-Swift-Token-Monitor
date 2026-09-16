<p align="center">
  <img src="docs/assets/app-icon.png" width="128" height="128" alt="Vibe Swift Token Monitor 应用图标">
</p>

# Vibe Swift Token Monitor

**简体中文 · [English](README.en.md)**

macOS 原生用量监视器，集中查看 Codex 用量、账号额度与活动历史。内置独立后台，无需安装 Node.js 或运行原 Electron 应用。

## 下载

### [⬇ 下载最新版 0.6.0 · Apple Silicon](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.6.0/Token-Monitor-Native-0.6.0-41-arm64.zip)

**macOS 26+ · Apple Silicon · 构建 41**

[更新说明](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/latest) · [SHA-256 校验文件](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.6.0/SHA256SUMS)

当前主要针对 Codex，其他工具仅实验适配。项目仍处于基础验证阶段，尚未公证，暂不推荐普通用户直接使用；目前实际测试系统为 macOS 27。

## 功能

- **用量与额度**：过去 24 小时、过去 30 天和最近 24 个月的模型与设备明细，以及已配置账号的可用额度。
- **动态活动历史**：小时、日、月趋势随范围切换；热力图与明细保留缺失数据和真实零值的区别。
- **圆环与配色**：模型、设备和额度圆环支持圆角、悬停放大、推荐色板及按对象保存的自定义颜色。
- **额度消耗归因**：结合当前额度窗口、已记录 Token 与价格权重，估算本周期各设备和模型的已用额度占比。
- **可定制界面**：固定 320 pt 内容宽度、栏目显隐与排序、菜单栏指标和主题色；支持简体中文与英语。
- **独立采集与 Hub**：关闭界面后后台可继续采集，也可接入已有 Hub 查看多设备汇总。
- **确认后更新**：支持 GitHub 正式版本检查；自动检查默认关闭，下载安装由用户确认。

费用为 **API 等价估算**，不是订阅账单。本项目并非 OpenAI 官方应用。

## 开始使用

1. 下载并解压，将应用移入“应用程序”文件夹；升级前退出旧界面并保留旧副本。
2. 打开应用，按需允许后台运行，等待首次扫描。
3. 在设置 → 数据选择本机采集，或配置已有 Hub。账号额度失效时，在原工具重新登录。

0.5.1 及更早版本请手动下载升级；0.5.2 起可在设置 → 关于检查后续更新。为兼容已有数据和后台，应用名称及安装身份仍沿用原 Beta 通道。

[使用与卸载](docs/USAGE.md) · [从源码构建](docs/BUILDING.md) · [反馈问题](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/issues)

## 来源与许可

本项目是独立维护的 macOS 原生衍生实现，复用 [Javis603/token-monitor](https://github.com/Javis603/token-monitor) v0.56.0 的部分 MIT 后台，以及 Node.js、Tokscale 和 Sparkle；不包含 Electron 前端，也不是上游官方客户端。

[第三方声明](TokenMonitorNative/THIRD_PARTY_NOTICES.md) · [后台来源](TokenMonitorNative/Backend/UPSTREAM.md)

上游版权与许可证保留；本仓库尚未为新增代码另行指定统一开源许可证。
