<p align="center">
  <img src="docs/assets/app-icon.png" width="128" height="128" alt="Token Monitor app icon">
</p>

# Vibe Swift Token Monitor

**简体中文 · [English](README.en.md)**

专为 Codex 打造的原生 macOS 用量与额度监视器。用一个小窗口查看本机与多设备用量、账号额度、模型分布和活动历史。

0.7.1 新增可点选的额度周期热力图、设备与模型额度 / Token 切换，以及 GPT-6 模型估价。采集后台使用 Swift，无需 Node.js、Tokscale 或 Electron，退出界面后也能继续采集。

## 下载 0.7.1

**[下载 DMG](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.7.1/Token-Monitor-Native-0.7.1-68-arm64.dmg)** · [下载 ZIP](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.7.1/Token-Monitor-Native-0.7.1-68-arm64.zip) · [SHA-256](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/download/v0.7.1/SHA256SUMS) · [更新说明](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/tag/v0.7.1)

Apple Silicon · macOS 26 及以上 · 构建 68 · 简体中文 / English

当前提供 ad-hoc 签名，尚未公证；实际构建与运行验证使用 macOS 27，macOS 26 真机验收尚未完成。

## 你可以看到什么

- **总览**：Codex 用量、额度、设备与模型摘要，可调整栏目顺序、显隐和配色。
- **活动**：模型与设备圆环、热力图、小时 / 日 / 月趋势，以及完整分项和活动明细。
- **额度**：官方窗口的已用与剩余比例、设备和模型三页圆环；点击分类圆环或摘要进度条切换额度比例与周期 Token。
- **周期热力图**：连接支持周期与历史接口的扩展 Hub 后，点选周期同步查看额度、设备和模型；灰度表示最后一次有效观测的已用额度，选中和悬停周期使用强调色。
- **菜单栏**：默认每周剩余额度圆环与百分比，可自选今日 Token、短期额度和显示样式。
- **本机定制**：固定 320 pt 小窗、浅色 / 深色外观、独立图表颜色与显示别名；别名不改变 Hub 设备标识。

圆环和柱图通过描边显示悬停状态，详情保留完整读数。缺失、过期和真实零值分别呈现。

## 开始使用

1. 下载 DMG 或 ZIP，将 **Token Monitor.app** 放入“应用程序”。
2. 打开应用，在设置 → 数据按需启用后台，等待第一次扫描 Codex 日志。
3. 如需多设备汇总，填写已有 Hub 的地址与密钥，验证连接并选择本机已有的设备记录。

**从 0.6 或更早版本升级：先停用旧版 Hub 上传和后台，再退出旧版，手动安装 0.7.1。** 新版使用独立数据目录，需要重新配置连接；不要删除旧同步基线或让同一设备有两个上传者。0.7.0-beta.2 使用者保留原数据目录，替换前同样先停止旧后台。[完整升级说明](docs/USAGE.md#安装与升级)

[使用说明](docs/USAGE.md) · [构建与架构](docs/BUILDING.md) · [反馈问题](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/issues)

## 数据与边界

本机读取 Codex 日志；账号额度读取已有 Codex 登录状态，不自动续期凭据或启动模型会话。Hub 同步为可选功能，发送统计、模型、设备信息及匿名账号额度观测，不发送提示词、会话正文或登录凭据。

当前额度分摊基于近期完整日费用权重，历史周期使用该周期内可用完整日数据，均为近似估算，不是逐次请求的实际额度消耗，也不预测剩余 Token。历史 Token 仅覆盖可用完整日；证据不足时保持缺失。周期推导不代表捕获了每次百分比归零。

GPT-6 Astra / Sol / Luna 估价采用 2026-09-24 的[官方 API 价格](https://developers.openai.com/api/docs/pricing)与[Codex 额度表](https://learn.chatgpt.com/docs/pricing)。仅在本机日志与设备模型 Token 完整匹配时补算；未记录速度档位时按 Standard 估算，未知模型（含 codex-auto-review）不套价。费用为 API 等价估算，不是订阅账单。这些补算只用于界面与分摊，不回填 Hub 上传账本，也不自动修复其他设备的价格。

## 项目关系与许可

受 [Javis603/token-monitor](https://github.com/Javis603/token-monitor) 启发，独立开发和维护原生 Swift 客户端与采集后台，兼容其 **v0.56.0 Hub API 基线**。兼容按实际接口和能力判断，不承诺所有上游版本或扩展均通用。

0.7.0 不再分发原项目的 Node 后台或 Tokscale。旧版本曾复用的 MIT 代码可在历史标签中查阅，其版权声明保留；Sparkle、系统符号和设备图标的来源见[第三方声明](TokenMonitorNative/THIRD_PARTY_NOTICES.md)。本项目非 OpenAI 或原项目作者的官方客户端，新增代码尚未另行指定统一开源许可证。
