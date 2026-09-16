# 从源码构建 / Build from source

需要 Apple Silicon Mac、完整 Xcode（macOS 26 SDK 或更新）及 npm。交付构建目前使用 Xcode 27；可通过 `DEVELOPER_DIR` 指定 Xcode。安装后的应用不依赖系统 Node.js 或 npm。

Requires an Apple Silicon Mac, full Xcode with the macOS 26 SDK or newer, and npm. Release builds currently use Xcode 27; set `DEVELOPER_DIR` to choose Xcode. The installed app does not require system Node.js or npm.

```sh
git clone https://github.com/Eldershi/Vibe-Swift-Token-Monitor.git
cd Vibe-Swift-Token-Monitor/TokenMonitorNative
python3 scripts/prepare-beta.py --download
swift test --build-system native
Backend/runtime/node --test Backend/tests/*.test.cjs
bash scripts/build-beta.sh
```

生成的应用和 ZIP 位于 `TokenMonitorNative/dist/`，构建不会安装应用。脚本名称及应用的 Beta 安装身份为兼容已有数据和后台而保留；请使用上述入口构建当前正式版本。

The app and ZIP are written to `TokenMonitorNative/dist/`; building does not install the app. Script names and the app's Beta installation identity are retained for compatibility with existing data and the background service. Use the commands above for the current stable version.

- `MonitorCore`：数据模型、Hub 通信、历史及偏好 / data models, Hub transport, history, preferences.
- `TokenMonitorNative`：SwiftUI / AppKit 界面 / native interface.
- `TokenMonitorBackend` 与 `Backend/`：独立采集及同步 / background collection and sync.

依赖固定版本与许可证随仓库保留。没有原更新签名私钥时仍可构建，但不会生成可用于已有客户端的签名更新清单；不要生成新钥匙冒充原签名身份。

Pinned dependencies and licenses are retained. You can build without the original update-signing private key, but cannot produce an update feed trusted by existing clients. Do not substitute a new signing identity.

公开提交前必须运行 / Before publishing changes:

```sh
python3 scripts/check-publication.py --staged
python3 scripts/check-publication.py
```

以上两条从仓库根目录运行，并需安装 Gitleaks。仅提交合成测试数据，勿提交凭据、真实统计、个人目录或构建产物。

Run these two checks from the repository root with Gitleaks installed. Commit only synthetic fixtures; exclude credentials, real statistics, personal paths, and build products.
