# 构建与架构 / Build and architecture

当前源码生成 macOS 0.7.0 原生应用，目标为 Apple Silicon、macOS 26+。需要完整 Xcode，包含 macOS 26 或更新 SDK；本次使用 Xcode / macOS 27 验证。SwiftPM 固定 Sparkle 2.10.0，首次构建需要下载依赖；运行应用不需要 Node.js。

The current source builds the native macOS 0.7.0 app for Apple Silicon and macOS 26+. Full Xcode with the macOS 26 SDK or newer is required. This release was verified with Xcode / macOS 27. SwiftPM pins Sparkle 2.10.0 and downloads it on first build. Node.js is not an app runtime dependency.

## 构建 / Build

```sh
git clone https://github.com/Eldershi/Vibe-Swift-Token-Monitor.git
cd Vibe-Swift-Token-Monitor
export DEVELOPER_DIR="$(xcode-select -p)"
swift test --build-system native --package-path TokenMonitorNative
python3 TokenMonitorNative/scripts/check-localization.py
bash TokenMonitorNative/scripts/build.sh
bash TokenMonitorNative/scripts/package-dmg.sh
```

`dist/` 位于 `TokenMonitorNative/` 下，包含 `Token Monitor.app`、ZIP，以及可选 DMG。构建不会安装应用或部署 Hub。`build-beta.sh` 仅保留为同一构建入口的兼容别名。默认 ad-hoc 签名；可用 `SIGNING_IDENTITY` 指定本机已有签名身份，公证是独立流程。

Outputs are under `TokenMonitorNative/dist/`: `Token Monitor.app`, ZIP, and optional DMG. Building neither installs the app nor deploys a Hub. `build-beta.sh` is a compatibility alias for the same build. Signing defaults to ad-hoc; `SIGNING_IDENTITY` can select an existing local signing identity. Notarization is a separate process.

## 结构 / Structure

| 目录 / Directory | 职责 / Responsibility |
|---|---|
| `TokenMonitorNative/Sources/MonitorCore` | Hub 数据模型、通信、统计与偏好 / Hub models, transport, statistics and preferences |
| `TokenMonitorNative/Sources/NativeBackendCore` | Codex 日志、快照、交接基线、额度观测与估算 / log parsing, snapshots, handoff, quota observations and estimates |
| `TokenMonitorNative/Sources/TokenMonitorBackend` | 原生后台生命周期、本机服务、Hub 同步 / native service lifecycle, local API and Hub sync |
| `TokenMonitorNative/Sources/TokenMonitorNative` | SwiftUI / AppKit 界面、窗口、图表、更新 / native UI, windows, charts and updates |
| `HubQuotaCycles` | 可选 Hub 周期推导模块及合成测试 / optional Hub cycle reducer and synthetic tests |
| `TokenMonitorNative/release.json` | 发布版本与构建号 / release version and build number |

`HubQuotaCycles` 是扩展模块，不是完整 Hub 服务或一键部署包。其集成脚本要求匹配的额度历史 Worker 源码；不要直接对任意上游版本执行补丁。macOS 基础统计不依赖这个扩展，客户端按 Hub 能力降级。

`HubQuotaCycles` is an extension, not a complete Hub server or deployment package. Its integration script expects a matching quota-history Worker source tree; it is not a universal patch for upstream releases. Basic macOS statistics work without the extension, with capability-based fallback.

旧 Node 后台、Tokscale 与旧客户端安装脚本已从当前源码移除，历史实现可从 0.6.0 等标签查阅。[来源与许可证](../TokenMonitorNative/THIRD_PARTY_NOTICES.md)继续保留。

The old Node backend, Tokscale, and legacy install scripts are removed from the current tree. Historical implementations remain in tags such as v0.6.0, with [attribution and licensing](../TokenMonitorNative/THIRD_PARTY_NOTICES.md) retained.

## 检查 / Checks

从仓库根目录运行 / Run from the repository root:

```sh
swift test --build-system native --package-path TokenMonitorNative
python3 TokenMonitorNative/scripts/check-localization.py
node --test HubQuotaCycles/tests/*.test.js
python3 TokenMonitorNative/scripts/verify-beta2-upload.py \
  --backend TokenMonitorNative/.build/arm64-apple-macosx/debug/TokenMonitorBackend
python3 TokenMonitorNative/scripts/verify-beta2-quota.py \
  --backend TokenMonitorNative/.build/arm64-apple-macosx/debug/TokenMonitorBackend
python3 scripts/check-publication.py --staged
python3 scripts/check-publication.py
```

Node.js 仅用于可选 Hub JavaScript 模块的开发测试，不打包进应用。完整生产合并契约验收可为验证脚本传入兼容 Worker 的 `--usage-module`；本仓库不包含生产配置。公开检查需要 Gitleaks，覆盖暂存内容和全部祖先。只提交合成测试数据。

Node.js is used only for optional Hub JavaScript development tests, never bundled in the app. Verification scripts accept `--usage-module` for a compatible Worker's full merge-contract checks; production configuration is not included. Publication checks require Gitleaks and cover staged content and every ancestor. Use synthetic fixtures only.

## 更新签名 / Update signing

构建读取 `release.json` 并校验 Swift 上报版本一致。`UPDATE_SIGNING_KEY` 可指向原发布 Ed25519 私钥；匹配时生成并验证 `appcast-native.xml` 与 ZIP 签名，无私钥仍可构建应用。私钥不得提交或打包，不要生成新钥匙冒充已有客户端信任的身份。

The build reads `release.json` and checks that Swift-reported versions agree. Set `UPDATE_SIGNING_KEY` to the original release Ed25519 key to generate and verify `appcast-native.xml` and the ZIP signature. Builds work without the private key. Never commit or bundle the key, or substitute a new identity for existing clients.

0.7 保留原生实验版的内部 Bundle ID、后台标识和数据目录；面向用户显示 Token Monitor。独立签名清单用于后续同身份更新，0.6 用户首次升级手动安装，详见[使用说明](USAGE.md)。

Version 0.7 retains the native development channel's internal bundle/service identifiers and data path while displaying Token Monitor. Its separate feed supports subsequent same-identity updates; users of 0.6 migrate manually as explained in the [usage guide](USAGE.md#english).
