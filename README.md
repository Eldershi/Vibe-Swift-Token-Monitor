# Vibe Swift Token Monitor

macOS 26+ 的原生 SwiftUI / AppKit 用量监视器。**0.5.0** 内置独立后台，读取本机 Codex、Claude Code 日志，展示 token 用量、模型、每日历史、API 等价费用和可获取的账号额度；也可连接现有 Token Monitor Hub 查看多设备汇总。

无需原 Electron 应用常驻，也无需用户安装 Node.js。退出界面后，后台可继续采集。

## 下载与使用

从 [Releases](https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/latest) 下载 Apple Silicon 安装包。最低 macOS 26，实际验证使用 macOS 27；当前使用 ad-hoc 签名，**尚未公证，也没有自动更新**。Gatekeeper 可能要求用户在系统设置中确认打开。

0.5.0 保留 `Token Monitor Native Beta.app` 的安装名称、Bundle ID 和数据目录，供已有 beta 原位升级；这是兼容性安排，不会覆盖旧的 0.4.1 客户端。

- 本机用量：允许应用后台运行，等待首次历史扫描；额度失效时在原工具重新登录。
- 共享 Hub：在设置手动填写地址和密钥、验证并绑定已有设备。选择“共享 Hub”或“仅本机”，两者不会重复相加。
- 与原版并存：可以保留原版作为参考；同一设备向同一 Hub 上传时，只启用一个上传者。接替及回退步骤见[安装与后台管理](TokenMonitorNative/BETA.md)。

费用是 **API 等价估算**，不是订阅账单；本机已删除且未归档的日志无法凭空恢复。缺失、真实零值、过期和离线分别呈现。

## 与原版项目的关系

原版是 [Javis603/token-monitor](https://github.com/Javis603/token-monitor)，本项目是**独立维护的 macOS 原生衍生实现**，不是原作者的官方客户端，也不是上游仓库的 GitHub fork。

- 原生界面、窗口、图表、设置及后台生命周期由本项目实现，使用 SwiftUI / AppKit。
- 独立采集并非全部重写为 Swift：0.5 复用了原版 **v0.56.0** 的部分共享采集、额度读取及 Hub 模块，固定到提交 [`2f60827`](https://github.com/Javis603/token-monitor/tree/2f60827e3028d283969dd74cde5b3f5664220442)，并增加隔离运行、凭据只读和原生桥接等修改。
- 安装包包含固定版本的 Node.js、Tokscale 及必要依赖，**不包含 Electron 前端**；保持既有 Hub 接口兼容，其他设备可继续使用原版。
- 原版 MIT 版权及许可证随源码和安装包保留。来源、修改范围和其他许可见[第三方声明](TokenMonitorNative/THIRD_PARTY_NOTICES.md)及[后台来源](TokenMonitorNative/Backend/UPSTREAM.md)。本仓库尚未为新增代码另行指定统一开源许可证。

感谢原版作者及 Tokscale 项目提供采集与同步基础。原生界面和本项目修改的问题请提交到本仓库。

## 界面与数据

- 总览、设备、模型、用量、额度、活动及每日趋势；支持今天／本月／总计。
- 自定义主题色；首页栏目显隐、手柄拖拽排序及模型排序持久化。
- 固定小方块热力图随宽度补日期；每日趋势横向浏览，默认定位最新端。
- 本机采集、共享 Hub、设置与缓存独立；Hub 密钥手动保存到独立 **0600 明文文件**，不访问 Hub 钥匙串。原工具登录信息只读，详见管理说明。

## 从源码构建

需要 Apple Silicon Mac、完整 Xcode（macOS 26 SDK 或更高）及开发机 npm；安装后的应用不依赖系统 Node/npm。

```sh
git clone https://github.com/Eldershi/Vibe-Swift-Token-Monitor.git
cd Vibe-Swift-Token-Monitor/TokenMonitorNative
python3 scripts/prepare-beta.py --download
swift test --build-system native
Backend/runtime/node --test Backend/tests/*.test.cjs
bash scripts/build-beta.sh
bash scripts/install-beta.sh
```

脚本沿用 beta 名称以兼容独立安装通道。构建默认使用 Xcode-beta；其他 Xcode 路径可通过 `DEVELOPER_DIR` 指定。

## 开发文档

- [工程说明](TokenMonitorNative/README.md)：架构、共性规则、测试入口。
- [安装与后台管理](TokenMonitorNative/BETA.md)：数据位置、同步接替、升级与卸载。
- [0.5.0 发布记录](TokenMonitorNative/verification/0.5.0/发布记录.md)：本次验证及已知限制。
- [维护摘要](MAINTENANCE.md)：当前状态和接手事项；[UI 约束](TokenMonitorNative/AGENTS.md)仅维护界面规格。

公开推送前安装 [Gitleaks](https://github.com/gitleaks/gitleaks)，启用 `git config core.hooksPath .githooks`，运行 `python3 scripts/check-publication.py --staged` 和 `python3 scripts/check-publication.py`。检查失败不得推送。构建包通过 Release 分发；凭据、真实统计、轨迹、个人笔记和缓存不入库，测试夹具仅使用合成数据。
