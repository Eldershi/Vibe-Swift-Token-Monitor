# 使用说明 / Usage

[首页](../README.md) · [English](#english)

## 中文

**安装与更新**：解压下载包，将应用移入“应用程序”。升级前退出旧界面，保留旧副本；不要同时运行多个安装副本。0.5.2 起可在设置 → 关于检查正式版本；自动检查默认关闭，开启后启动时及运行期间每 6 小时检查，安装始终需要确认。应用当前未公证。

**本机采集**：按系统提示允许后台运行。首次扫描可能需要等待；退出界面不会停止后台采集。额度读取原工具的有效登录状态，失效时在原工具重新登录。本机已删除且从未采集的日志无法恢复。

**范围与额度换算**：“今天”显示滚动过去 24 小时，“本月”显示含今天在内的最近 30 个自然日，“总计”显示最近 24 个自然月。额度换算只估算当前额度窗口内各设备和模型的已用额度占比，不预测剩余 Token。结果按额度读数、已记录 Token 分类和适用价格加权；数据不完整时会使用明确标记的近似或最近成功结果。

**Hub 同步**：在设置 → 数据手动填写地址和密钥，验证并绑定已有设备。本机用量与 Hub 汇总分开；同一设备向同一 Hub 只保留一个上传者。接替原应用前先停用其同步，回退前先停用本应用同步，避免重复上传。不要直接删除同步基线。

**数据与隐私**：统计和账号额度是不同来源；费用只是 API 等价估算。原工具凭据只读，不自动续期或启动模型会话。启用兼容 Hub 的额度换算同步时，上传匿名设备、模型、事件时间、Token 分类计数、覆盖记录和匿名账号摘要；不上传正文、提示词、文件路径、邮箱或凭据。Hub 密钥存于仅当前用户可访问的 0600 明文文件，不写入日志；请按敏感数据保护本机账户。

**跨平台 Node 采集器**：Release 中的 `Token-Monitor-Conversion-0.6.0-node.zip` 需要 Node.js 24.19 或更新的 24.x 版本。它与 Mac 应用共用解析、去重和换算代码，没有第三方 npm 依赖。解压后运行：

```sh
node conversion/cli.cjs --directory /path/to/private-data --device-id EXISTING_DEVICE_ID --logs /path/to/.codex --hub https://YOUR-HUB.example --secret-file /path/to/private-hub-secret --once
```

`--device-id` 必须使用 Hub 中已有设备 ID；`--logs` 指向包含 `sessions` 和 `archived_sessions` 的 Codex 根目录。macOS/Linux 的密钥文件权限设为 `600`，Windows 使用仅当前用户可读的 ACL。去掉 `--once` 后每分钟同步，Ctrl+C 停止。Mac 内置采集和 Node 采集器对同一设备只能启用一个；私有数据目录、队列和检查点不要放进同步文件夹或随意删除。Windows/Linux 尚未真机验证。

**暂停与卸载**：设置 → 数据可暂停采集或停用后台。卸载前先停用 Hub 同步、停用后台并退出，再把应用移到废纸篓；已有数据默认保留。回退时恢复旧应用副本，并先核对该版本的同步能力。

## English

**Install and update:** unzip the download and move the app to Applications. Quit the old interface and keep a backup before upgrading. Do not run multiple copies at once. From 0.5.2, check stable releases in Settings → About. Automatic checks are off by default; when enabled, they run at launch and every six hours while the app is running. Installation always requires confirmation. The app is not notarized.

**Local collection:** allow background activity when macOS prompts you. The first scan may take time; quitting the interface does not stop collection. Quotas use the original tool's valid sign-in state. Sign in again there if access expires. Logs deleted before they were ever collected cannot be recovered.

**Ranges and quota attribution:** Today is a rolling 24-hour window, This Month is the latest 30 calendar days including today, and Total is the latest 24 calendar months. Quota attribution estimates each device and model's share of quota already used in the current quota window; it does not predict remaining tokens. It weights the quota reading with recorded token categories and applicable prices. When inputs are incomplete, the app uses an explicitly approximate or last successful result.

**Hub sync:** enter the address and secret in Settings → Data, validate, and bind the existing device. Local usage and Hub totals are separate. Keep only one uploader per device per Hub. Disable the previous app's sync before switching, and disable this app's sync before switching back. Do not delete the sync baseline.

**Data and privacy:** usage statistics and account quotas come from different sources; costs are API-equivalent estimates. Tool credentials are read-only, with no automatic renewal or model sessions. With quota-conversion sync to a compatible Hub enabled, the app uploads anonymous device and account identifiers, model names, event times, token-category counts, and coverage records. It does not upload content, prompts, file paths, email addresses, or credentials. The Hub secret is stored in a plaintext file with owner-only 0600 permissions and is excluded from logs. Protect your local account accordingly.

**Cross-platform Node collector:** the `Token-Monitor-Conversion-0.6.0-node.zip` release asset requires Node.js 24.19 or a newer 24.x release. It shares parsing, deduplication, and attribution code with the Mac app and has no third-party npm dependencies. After extracting it, run:

```sh
node conversion/cli.cjs --directory /path/to/private-data --device-id EXISTING_DEVICE_ID --logs /path/to/.codex --hub https://YOUR-HUB.example --secret-file /path/to/private-hub-secret --once
```

`--device-id` must be an existing device ID in the Hub. `--logs` points to the Codex root containing `sessions` and `archived_sessions`. Set the secret file to mode `600` on macOS/Linux, or use an owner-only ACL on Windows. Remove `--once` to sync every minute and stop it with Ctrl+C. Run either the Mac collector or the Node collector for a given device, never both. Keep the private data directory, queue, and checkpoints out of synchronized folders and do not delete them casually. Windows and Linux have not been tested on physical systems.

**Pause and uninstall:** pause collection or disable the background service in Settings → Data. Before uninstalling, disable Hub sync and the background service, quit, then move the app to Trash. Existing data is retained by default. To roll back, restore the previous app and check its sync capabilities first.
