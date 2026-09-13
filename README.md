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
