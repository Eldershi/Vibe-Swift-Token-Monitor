# 使用说明 / Usage

[首页](../README.md) · [English](#english)

## 中文

**安装与更新**：解压下载包，将应用移入“应用程序”。升级前退出旧界面，保留旧副本；不要同时运行多个安装副本。0.5.2 起可在设置 → 关于检查正式版本；自动检查默认关闭，开启后启动时及运行期间每 6 小时检查，安装始终需要确认。应用当前未公证。

**本机采集**：按系统提示允许后台运行。首次扫描可能需要等待；退出界面不会停止后台采集。额度读取原工具的有效登录状态，失效时在原工具重新登录。本机已删除且从未采集的日志无法恢复。

**Hub 同步**：在设置 → 数据手动填写地址和密钥，验证并绑定已有设备。本机用量与 Hub 汇总分开；同一设备向同一 Hub 只保留一个上传者。接替原应用前先停用其同步，回退前先停用本应用同步，避免重复上传。不要直接删除同步基线。

**数据与隐私**：统计和账号额度是不同来源；费用只是 API 等价估算。原工具凭据只读，不自动续期或启动模型会话。Hub 密钥存于仅当前用户可访问的 0600 明文文件，不写入日志；请按敏感数据保护本机账户。

**暂停与卸载**：设置 → 数据可暂停采集或停用后台。卸载前先停用 Hub 同步、停用后台并退出，再把应用移到废纸篓；已有数据默认保留。回退时恢复旧应用副本，并先核对该版本的同步能力。

## English

**Install and update:** unzip the download and move the app to Applications. Quit the old interface and keep a backup before upgrading. Do not run multiple copies at once. From 0.5.2, check stable releases in Settings → About. Automatic checks are off by default; when enabled, they run at launch and every six hours while the app is running. Installation always requires confirmation. The app is not notarized.

**Local collection:** allow background activity when macOS prompts you. The first scan may take time; quitting the interface does not stop collection. Quotas use the original tool's valid sign-in state. Sign in again there if access expires. Logs deleted before they were ever collected cannot be recovered.

**Hub sync:** enter the address and secret in Settings → Data, validate, and bind the existing device. Local usage and Hub totals are separate. Keep only one uploader per device per Hub. Disable the previous app's sync before switching, and disable this app's sync before switching back. Do not delete the sync baseline.

**Data and privacy:** usage statistics and account quotas come from different sources; costs are API-equivalent estimates. Tool credentials are read-only, with no automatic renewal or model sessions. The Hub secret is stored in a plaintext file with owner-only 0600 permissions and is excluded from logs. Protect your local account accordingly.

**Pause and uninstall:** pause collection or disable the background service in Settings → Data. Before uninstalling, disable Hub sync and the background service, quit, then move the app to Trash. Existing data is retained by default. To roll back, restore the previous app and check its sync capabilities first.
