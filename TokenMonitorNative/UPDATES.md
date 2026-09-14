# GitHub 更新与发布签名

设置 → 关于 → 软件更新：支持手动检查；自动检查默认关闭，开启后启动时检查一次，应用运行期间每 6 小时检查。仅使用本仓库 GitHub 最新正式 Release，不选择草稿或预发行，也不从较新 Beta 降级。用户确认查看更新后进入 Sparkle 界面，再确认下载/安装；不会自动下载或静默安装。

0.5.1 及更早版本没有应用内更新入口，首次升级至 0.5.2 需手动下载。0.5.2 开始随正式 Release 提供签名 appcast.xml，后续版本可通过应用内检查后确认安装。缺少清单的版本保留 GitHub 手动下载入口。

## 身份与签名

- Sparkle 固定 2.10.0，依赖校验在 Package.resolved 和上游二进制 checksum 中；许可随应用分发。
- 公钥：Resources/UpdatePublicKey.txt，随源码与应用发布。
- 私钥：仓库根目录 `.local-private/update-signing/ed25519.seed`，base64 Ed25519 seed，0600，已被 Git 忽略。**请离线备份原私钥**。不要上传、粘贴进日志或提交；丢失后不能随意生成新钥匙继续给已有客户端更新。
- 首次身份已生成。新开发机应恢复原私钥，或用 `UPDATE_SIGNING_KEY` 指向受保护的备份文件。build-beta 不会生成或轮换密钥；没有私钥仍能构建客户端，但不会生成可发布的清单，并移除旧清单避免误用。
- 启用签名清单验证及归档解压前 EdDSA 验证。不能仅凭下载成功、GitHub SHA256 或 ad-hoc 代码签名放行更新。

## 构建发布附件

从仓库根目录运行：

```sh
bash TokenMonitorNative/scripts/build-beta.sh
```

有原私钥时，此命令生成对应 ZIP 和 `TokenMonitorNative/dist/appcast.xml`，验证归档签名与清单签名。清单中的 URL 指向 `releases/download/v<展示版本>/<ZIP名称>`，构建号来自包中 CFBundleVersion，最低系统为 macOS 26。发布者必须递增版本/构建，上传该次匹配的 ZIP 和 appcast.xml 到同一个 GitHub Release；签名之后不能修改 ZIP 或清单。Beta Release 不会被自动检查选中。

发布前仍需执行根目录要求的公开检查。私钥不进包，appcast 也不包含本机路径。只有公钥、许可证及 Sparkle 运行框架随包。

## 安装行为及验证边界

Sparkle 在当前应用路径替换包，因此原先带版本号的安装文件名可能保持不变；关于页元数据展示实际版本。更新不改用户数据目录、Bundle ID、后台 LaunchAgent 身份。更新退出阶段沿用等待持久化的流程，注销原后台服务；新应用启动后按用户已有的后台启用偏好注册。若注销失败则取消退出并恢复界面连接；若 Sparkle 报错则尝试恢复原已启用后台。

版本/HTTP/持久化、构建与签名验证结果以对应版本验收记录为准。尚未做真实用户安装副本的升级/权限失败/服务恢复端到端验收；不得把生成清单视为已经发布或已经升级。
