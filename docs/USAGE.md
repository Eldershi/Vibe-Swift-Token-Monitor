# 使用说明 / Usage

[首页](../README.md) · [English](#english)

## 安装与升级

0.7.1 适用于 Apple Silicon、macOS 26 及以上。打开 DMG 后将 **Token Monitor.app** 拖到“应用程序”，或解压 ZIP 后移动应用。当前未公证；若系统拦截，请先核对下载来源及 SHA-256，再按 macOS“隐私与安全性”中的提示处理，不要全局关闭系统保护。

### 从 0.6 或更早版本升级

1. 在旧应用中停用 Hub 上传，再停用后台，最后退出界面。单独退出窗口不会停止后台。
2. 保留旧应用及数据备份，安装并打开 0.7.1。
3. 在设置 → 数据启用原生后台；首次扫描需要等待。本机历史以仍保留的 Codex 日志为依据，已删除且从未采集的日志不能恢复。
4. 如使用 Hub，重新输入地址与密钥、验证连接，选择此 Mac 原有的设备记录，再启用同步。

0.7 使用独立后台身份与数据目录，不自动搬移 0.6 的设置或同步账本。已有 Hub 记录在交接时保留，本机新增量按保存的交接基线续传。不要删除基线、随意改设备标识或同时运行两个上传者；交接验证失败时先保留数据并检查错误，不要通过清空文件强行绕过。

0.7.0-beta.2 与正式版共享数据目录；停止实验版后台并退出后替换应用，避免保留两个运行副本。显示名称已改为 Token Monitor，内部历史标识保持兼容。

### 后续更新

设置 → 关于可检查 GitHub 正式 Release。自动检查默认关闭，启用后应用运行期间每 6 小时检查；下载与安装需要确认。0.7 使用独立的 `appcast-native.xml` 签名清单，0.6 的旧更新器不会把它当作同身份替换包，首次迁移请手动下载。预发行不进入正式更新通道。

## 页面与统计口径

| 内容 | 口径 |
|---|---|
| 今天 / 本月 / 总计的用量摘要 | 本机按当地自然日、自然月和已采集累计统计；Hub 模式采用来源设备的周期与有效性 |
| 今天的趋势和活动明细 | 滚动过去 24 个小时槽 |
| 本月的趋势和活动明细 | 含今天在内的最近 30 个自然日 |
| 总计趋势 | 最近 24 个自然月；累计总量本身不受这 24 个月限制 |
| 官方额度 | 独立账号窗口，不随用量范围相加，也不按设备简单累加 |
| 设备额度分摊 | 近期最多 7 个完整日的模型费用权重外推，属于估算 |
| 历史周期分摊与 Token | 使用所选周期内可用完整日；额度按费用权重近似分摊，Token 仅覆盖这些可用日期 |

总览的模型、设备、热力图和趋势入口进入活动页。活动卡片可打开完整模型 / 设备详情或热力图与趋势明细。额度页顶部热力图可选择历史周期，额度、设备与模型一起切换；首页仍显示当前额度。圆环有概览、设备、模型三页，点击分类圆环的整个圆形区域切换额度百分比与 Token。并列设备 / 模型卡片的进度条区域也可独立切换。切周期保留图表页与显示口径；统计依据位于设置 → 数据的折叠项。

额度读数约每 5 分钟只读采集一次，手动刷新可发起新读取。登录失效时在 Codex 中重新登录。过期额度不假定已重置；缺失数值不当作零。费用字段来自已有价格依据，是 API 等价估算，不是订阅费用。

## Hub 与周期记录

地址与共享密钥由用户配置，密钥不是 OpenAI API Key。可以只读查看 Hub；绑定本机设备并启用上传后才续传本机统计。当前客户端只采集和展示 Codex，但同步保留其他客户端 / Agent 的历史字段。

基础兼容目标为 Token Monitor v0.56.0 Hub API。周期热力图需要 Hub 提供 `/api/quota/cycles`、`/api/quota/history` 及对应能力声明；上游基础 Hub 不自动具备本项目的扩展。缺少能力时保留基本统计，窗口区间仅作预计值。支持扩展但尚无匹配确认周期时，分摊估算暂停。

周期起点根据稳定截止时间减去窗口长度推导，并需多次观测确认。它不是百分比归零的精确发生时间，也不保证捕获轮询间的每次变化。热力图灰度表示最后一次有效观测的已用比例，不代表周期结束时的精确最终值；无读数为未知，无确认周期的日期显示普通灰色活动格。首个周期视觉补至当天零点，统计边界不变。本版不提供剩余 Token 预测、重置通知或逐请求严格归因；历史分摊需要该周期完整日费用数据。

GPT-6 Astra / Sol / Luna 的估价使用 2026-09-24 官方价格快照，仅在本机日志与设备模型 Token 完整匹配时补算。API Fast 倍率为 2，Codex Fast 额度倍率为 2.5；API 长上下文倍率不直接套用到 Codex。缺速度档位按 Standard 估算，未知模型不套价。补算仅用于界面与分摊，不写回上传账本，也不自动补齐其他设备价格；来源见设置中的统计依据。

## 隐私与本机数据

- 本机采集读取 Codex 日志，额度读取已有登录状态；不自动续期、不启动模型会话。
- 启用 Hub 上传后发送设备标识 / 名称 / 系统信息、版本、模型及 Token 汇总、日月历史和匿名账号额度观测；不上传提示词、会话正文、日志路径、邮箱或登录凭据。
- Hub 密钥保存在当前用户专用的 0600 明文文件。匿名账号摘要是关联标识，并不意味着所有统计都不可识别；请信任你配置的 Hub。
- 当前数据目录仍为 `~/Library/Application Support/Token Monitor Native Beta 2/`，用于兼容已有原生版本。不要公开该目录或将其中基线、队列放进同步文件夹。

## 定制、暂停与卸载

设置支持栏目显隐和排序、主题色、菜单栏指标、图表配色与本机别名。别名不更改服务端标识；恢复配色不清除名字。语言跟随 macOS，可在系统中设置单应用语言。

`⌘,` 打开设置，`⌘R` 刷新，`⌘W` 关窗，`⌘Q` 退出界面。后台单独管理：卸载前先停用 Hub 上传和后台，再退出并移除应用；本机数据默认保留。回退时先停止新版后台，再恢复旧应用和对应数据，不让同设备双写。

## English

### Install and migrate

Requires Apple Silicon and macOS 26 or later. Drag **Token Monitor.app** from the DMG into Applications, or extract the ZIP and move the app. The app is not notarized. If macOS blocks it, verify the source and checksum, then use the system's Privacy & Security prompts without disabling protection globally.

For 0.6 or earlier, disable Hub uploads and the old background service before quitting. Keep the old app and data backup, install 0.7, enable the native service, and wait for the initial Codex scan. Configure the Hub again and select the Mac's existing device record. The new version has a separate data directory; it does not automatically migrate old preferences or ledgers. It preserves the remote record during handoff and sends subsequent local increments against a saved baseline. Keep one uploader per device and never clear a baseline to bypass a failed handoff.

Users of 0.7.0-beta.2 retain their existing data directory. Stop that service and quit before replacing the app. The display name changes to Token Monitor while internal identifiers remain compatible.

Settings → About checks stable GitHub releases. Automatic checks default to off and run every six hours while enabled and running. Download and installation require confirmation. The separate signed `appcast-native.xml` feed prevents the 0.6 updater from attempting to replace an app with a different identity; the first migration requires a manual download.

### Reading the data

Usage summaries mean the local calendar day, calendar month, and collected lifetime total. Hub summaries follow the source devices' period windows and validity. Trends and activity details use rolling 24 hours, the latest 30 calendar days including today, and a 24-month trend; lifetime totals are not limited to 24 months.

Overview entries open Activity or Quota. Activity cards lead to full model / device breakdowns and heatmap / trend records. The quota heatmap selects a cycle and updates quota, devices, and models together, while Overview keeps current readings. Its three donut pages show quota, devices, and models. Click a distribution donut, including its center, to toggle quota shares and cycle tokens; the side-by-side cards offer independent toggles on their progress bars. Cycle changes preserve the selected page and metric. Historical tokens cover available complete days within the selected cycle.

Official quota is read roughly every five minutes; manual refresh can request a fresh reading. Sign in again in Codex if credentials expire. Quota windows remain separate from usage ranges and are not added across devices. Stale quota is not assumed reset, and missing data is not zero.

Current quota allocation extrapolates model cost weights from up to seven recent complete days. Historical allocation uses available complete-day weights within that cycle; insufficient evidence stays missing. Costs are API-equivalent estimates, not subscription charges. This version does not predict remaining tokens, attribute individual requests precisely, or send reset notifications.

### Hub compatibility and privacy

Enter an existing Hub address and shared secret in Settings → Data. Read-only viewing is available; bind the existing device and enable uploads to send local increments. The client collects and displays Codex while preserving other clients' historical fields during synchronization.

The baseline is the Token Monitor v0.56.0 Hub API. The cycle heatmap requires extended `/api/quota/cycles` and `/api/quota/history` endpoints and the capability declaration; a basic upstream Hub does not automatically include it. Older Hubs retain basic statistics and estimated windows. When the capability exists but no matching cycle is confirmed, attribution pauses. Cycle starts are inferred from stable deadlines minus window lengths, not exact observations of percentage resets. Gray intensity shows last observed usage, not an exact final value. Missing readings remain unknown; uncovered dates retain ordinary gray activity cells. The first recorded cycle visually extends to midnight without changing statistical boundaries.

GPT-6 Astra / Sol / Luna estimates use the September 24, 2026 official pricing snapshot and require complete local-log matches to device model token totals. API Fast uses a 2× multiplier and Codex Fast a 2.5× credit multiplier; API long-context surcharges are not applied to Codex. Missing speed tiers assume Standard, and unknown models remain unpriced. Repricing affects display and allocation only, never the upload ledger or automatic repair of other devices. Sources are available in Settings.

Local logs and existing Codex credentials are read without credential renewal or model sessions. Optional Hub uploads include device identifiers, names, system information, versions, model/token summaries, daily/monthly history, and pseudonymous quota observations. They exclude prompts, conversation content, log paths, email addresses, and sign-in credentials. The Hub secret is an owner-only 0600 plaintext file; trust the Hub you connect to.

Data remains under `~/Library/Application Support/Token Monitor Native Beta 2/` for compatibility. Keep it private, including upload queues and baselines. Deleted, never-collected logs cannot be recovered.

### Customize and remove

Customize section visibility/order, colors, menu bar metrics, and local display names in Settings. Display names do not change Hub identifiers, and resetting colors does not remove them. Language follows macOS, including per-app language settings.

Use `⌘,` for Settings, `⌘R` to refresh, `⌘W` to close the window, and `⌘Q` to quit the interface. Collection continues independently. Before uninstalling or rolling back, disable uploads and the background service, then quit. App removal retains local data by default. Restore the matching previous app/data only after stopping the new uploader.
