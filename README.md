# Vibe Swift Token Monitor

Token Monitor Native 是面向 macOS 26+ 的原生 SwiftUI / AppKit 统计客户端，连接现有 [Token Monitor](https://github.com/Javis603/token-monitor) Hub，展示 token 用量、费用估算、额度和历史趋势。

本项目提供原生界面；采集、上传、价格计算及 Hub 托管由原 Token Monitor 应用负责。

## 构建与使用

需要完整 Xcode 和 macOS 26 SDK 或更高版本。当前版本为 0.4.1（构建 21），无第三方 Swift 依赖。

```sh
git clone https://github.com/Eldershi/Vibe-Swift-Token-Monitor.git
cd Vibe-Swift-Token-Monitor/TokenMonitorNative
swift test --build-system native
bash scripts/build.sh
bash scripts/install.sh
```

默认安装至 `~/Applications/Token Monitor Native.app`。打开应用，在设置中填写 Hub 地址和共享密钥；共享密钥保存在系统钥匙串中。详细要求、连接方式和升级说明见[工程文档](TokenMonitorNative/README.md)。

## 项目内容

- [TokenMonitorNative/](TokenMonitorNative/)：Swift Package、源码、测试、资源及构建脚本。
- [维护摘要](MAINTENANCE.md)：当前状态、关键决策与验证记录。
- [性能与验收](TokenMonitorNative/verification/0.4.1/性能与验收.md)：0.4.1 性能测量及验证限制。
- [第三方声明](TokenMonitorNative/THIRD_PARTY_NOTICES.md)：依赖与参考说明。

构建产物、缓存、本地设置与凭证不纳入版本控制。仓库未添加项目开源许可证。

## 公开推送检查

安装官方 [Gitleaks](https://github.com/gitleaks/gitleaks)，并在每个本地克隆中启用检查：

```sh
git config core.hooksPath .githooks
python3 scripts/check-publication.py --staged
python3 scripts/check-publication.py
```

推送钩子会检查待推送提交及其全部祖先，结合 Gitleaks 排查凭证，并阻止个人目录、对话分享链接及常见本地数据文件。缺少扫描器或检查失败时停止推送；匹配内容不打印到日志。Git hooks 不随克隆自动启用，GitHub 的密钥扫描及推送保护作为额外防线。

真实设置、统计导出、诊断轨迹和个人笔记请保留在仓库之外或被忽略的 `.local-private/` 中。测试夹具仅使用可复现的合成数据。自动检查不能识别所有隐私信息，提交前仍需审阅文件清单及内容。
