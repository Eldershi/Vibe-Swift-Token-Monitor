# Token Monitor Native

独立的 macOS 26+ SwiftUI 统计界面，读取现有 Token Monitor Hub。原 Electron 应用继续负责采集、上传、价格计算与 Hub 托管。本工程不安装采集器，不接管官方更新。

## 使用

打开 `Token Monitor Native.app` → 设置 → 连接，填写 Hub 地址与共享密钥，先测试，再保存。本机默认 `http://127.0.0.1:17321`。不要填写 OpenAI API Key。密钥以 Hub URL 为账号保存在本应用专用的 Keychain 服务中，不写入 JSON、源码或日志。

- 小窗口顶部透明区域右侧的原生工具栏选择今天／本月／总计；底部左侧单图标圆形按钮直接选择总览、设备、模型、趋势；脑形图标圆形按钮选择工具，圆形齿轮按钮打开设置。标题文字隐藏，标题栏仍可拖动；正文数字可复制。置顶只在设置 → 通用中开启，默认关闭。
- 总览可滚动查看总 token、API 等价费用、当前额度、前三个模型、可横向滚动的活动热力图和每日细柱图。热力图格子固定 7 pt（圆角 1.5 pt、间距 3 pt），零用量和未报告均用浅灰填充，悬停显示精确用量或无数据，框内底部仅显示月份；细柱固定 5 pt，日期槽位约 7 pt。拉宽窗口会显示更多日期，不放大图形或增加视图高度。首次显示及切换工具后，按实际内容和窗口宽度校正到最新端；手动向前浏览后不会被实时刷新拉回。
- 底部三个入口统一为 44×44 pt 圆形 Liquid Glass，SF Symbols 为 19–20 pt；页面菜单含 SF Symbols，工具菜单所有条目均为纯文字；菜单与按钮保留约 10 pt 留白。窗口最小内容宽度为 320 pt，按参考截图的 Retina 比例设置；高度可独立调整。
- 来源菜单只列出有真实统计且仍有有效设备上报的来源；明确缺失、禁用或过期来源隐藏，正常报告的零用量保留。Hub 整体断连时保留最后有效快照。连接成功和有效上报用绿色，过期上报用橙色，并保留文字状态。
- 关闭窗口后应用留在菜单栏。菜单栏显示所选工具的今日简写用量，可重新打开窗口或设置。
- 设置 → 首页：开关用量、实时速率、额度、设备、模型、活动、每日趋势，按住右侧手柄上下拖拽排序；可恢复默认布局，允许全部关闭。设备默认不加入首页，以保留升级前布局。隐藏栏目不删除数据，也不影响详情入口。
- 点击首页栏目标题进入详情；底部页面菜单也可打开全部详情。新增用量分项、实时速率、额度和每日活动详情，并可返回总览。
- 设置 → 通用 → 主题色：跟随系统或通过系统颜色选择器选择任意颜色，以 sRGB 持久化保存，即时用于图表和交互强调；成功／过期仍保留绿色／橙色状态。
- 所有统计页面都在同一小窗，无独立统计窗口。模型可按 token 或估算费用排序；趋势可选择按日／按月，并横向查看 Hub 已有历史，其时间范围独立于顶部用量周期。
- `⌘,` 设置，`⌘R` 刷新，`⌘W` 关闭窗口，`⌘Q` 退出原生应用。
- “打开 Token Monitor”进入原应用管理采集、账号或订阅。退出原生界面不会停止 Hub；退出原 Token Monitor 会停止它托管的 Hub。

额度表示 Hub 报告的当前剩余额度，与统计周期独立；不同账号分别显示，不叠加。保留原始百分比、单位、重置时间与过期状态，不根据 token 估算额度。原 Hub 未提供有效额度窗口时隐藏该区块；额度缓存不含账号姓名、邮箱或账号标识。

费用是 Hub 提供的 API 等价估算，不是订阅账单。实时速率使用每台设备匹配的计时计数增量；Hub 当前没有按工具拆分计时，所以明确标注“所有工具”。首次连接或重连样本不足时显示 —。

“上报数据已过期”由上报时间和上传间隔判断，不以用量有没有增加判断。跨日过期的设备显示“上一周期数据”，避免把旧周期分项误认为当前合计。缺失历史不补零；实际报告的 0 保留为 0。

## 构建与本地安装

需要完整 Xcode 和 macOS 26 SDK 或更高版本。可用 `DEVELOPER_DIR` 指定 Xcode；本机验证使用 Xcode-beta、SDK 27，二进制最低系统版本为 26.0。无第三方 Swift 依赖，当前构建输出为本机架构。

```sh
cd /path/to/TokenMonitorNative
swift test --build-system native
./scripts/build.sh
./scripts/install.sh
```

默认安装到 `~/Applications/Token Monitor Native.app`；也可 `INSTALL_DIR=/Applications ./scripts/install.sh`。在 Finder 打开安装后的应用。开发期间不要同时运行安装副本与 dist 副本。

本地更新必须递增构建号：

```sh
VERSION=0.4.1 BUILD_NUMBER=21 ./scripts/build.sh
./scripts/install.sh
```

构建脚本生成独立 app、ad-hoc 签名并执行启动自检。安装脚本检查身份与版本，复制并验证新包，退出**原生应用**，备份设置和上一版 app，再替换。替换后启动自检失败则恢复上一版。安装不修改 `/Applications/Token Monitor.app`，不停止它的后台。

```sh
./scripts/rollback.sh
```

恢复脚本还原上一版 app 和升级前设置，保留当前版为 `restored-from-时间戳.app`。Keychain 不随 app 替换而删除。统计缓存可重建。每次新升级只保留一份 `previous.app`；需要长期留存可自行复制。

本地 ad-hoc 重签后，macOS 可能再次询问 Keychain 访问许可；允许后使用原有密钥，无需重新生成 Hub 密钥。若要稳定分发，可设置 `SIGNING_IDENTITY` 使用自己的固定签名证书；当前交付未公证，不能视为适合公开分发的签名发行版。

## 数据与身份

| 项目 | 位置／规则 |
|---|---|
| Bundle ID | `local.tokenmonitor.native` |
| 设置／缓存 | `~/Library/Application Support/Token Monitor Native/` |
| 窗口位置 | 此 Bundle ID 的系统偏好 `NativeCompactWindow` |
| 共享密钥 | Keychain generic password，service 为 Bundle ID，account 为规范化 Hub URL |
| 设置迁移 | 当前 schema 3；迁移前保留 `.pre-v3-backup`；拒绝覆盖未来 schema |
| 升级设置备份 | `settings.json.pre-upgrade-backup` |
| 更新 | 本地构建；没有在线更新源，不宣称“已是最新” |

缓存只编码明确建模的统计字段，丢弃完整响应里的账号、订阅、项目和会话内容。HTTP 请求不携带 Cookie，不跟随重定向转发密钥。HTTP 可用于本机／受信任网络；跨网 HTTPS 的证书校验沿用系统行为。

## 架构与维护

- `MonitorCore`：Hub DTO、适配与校验、HTTP／SSE、历史缺失语义、速率、设置迁移。
- `AppStore`：全应用唯一 SSE、共享筛选、30 秒上限退避、30 秒轮询回退、缓存、睡眠唤醒与历史修订缓存。
- `TokenMonitorNative`：SwiftUI、Canvas、MenuBarExtra；NSPanel 处理原生窗口行为，NSToolbarItemGroup 提供系统周期选择，自有 NSScrollView 管理页面和历史偏移。
- `LocalUpdateService`：预留更新服务边界，无下载或安装网络逻辑。未来 Sparkle 2 使用自己的 HTTPS appcast、签名更新包与固定身份，勿使用原应用更新源。
- `Tests`：完全合成的 v0.56.0 契约样本、网络与生命周期回归测试，不含用户密钥。

系统提供标题栏、工具栏、菜单与原生控件材质；内容使用标准背景。底部普通原生按钮在 `GlassEffectContainer` 中各使用一次 `.glassEffect()`，避免叠加玻璃按钮样式。状态配文字，列表、额度、热力图和图表保留辅助功能信息。

## 开发须知

- **先采样再优化**：用真实数据、完整窗口和实际交互复现，查看主线程调用栈。测试通过、简化页面流畅，都不能替代真实体验验收；工具缺失的证据要明确记录。
- **让 `body` 保持轻量**：避免在栏目判断、列表行中嵌套筛选、排序或创建日期格式器。复用解析器时保证线程安全；缓存有容量上限，失败解析也可缓存，并明确快照、来源、日期和过期边界等失效条件。
- **缩小更新范围**：独立观察周期、来源、主题和布局。每秒计时只驱动需要计时的视图；尺寸变化只更新几何，不重新解析历史或生成整份展示数据。
- **把阻塞工作移出主线程**：JSON编码、磁盘和钥匙串操作放到后台；仅包进继承主线程隔离的 `Task` 并不够。连续设置修改合并保存，防止旧写覆盖新写；连接确认落盘后启用，退出完成最终保存。
- **明确尺寸与滚动归属**：桥接 SwiftUI/AppKit 时分清视口宽度、内容高度由谁决定，避免双向测量和逐像素回写状态；仅关闭确实不需要的 hosting 尺寸推导。首次定位、数据晚到、重新进入和用户手动浏览分别处理，同步不得重置浏览位置。
- **优化时保留语义与操作**：缺失值不补成零，不画未来数据；批量绘图保留无障碍描述。视觉尺寸与点击区域分开，兼顾鼠标、触控板和键盘；验证系统滚动条偏好差异，不修改全局设置。
- **记录可比较的结果**：覆盖真实快照与长历史、窄窗与宽窗、周期切换和同步刷新。区分同步耗时、额外调度延迟与屏幕呈现，报告P95/最大值，不把含等待的循环当FPS；为失效边界、保存顺序和滚动定位补回归。

具体实现与测量见 [0.4.1性能与验收](verification/0.4.1/性能与验收.md)。

## 协议基线与参考

实现基于本机安装的 Token Monitor v0.56.0 源码契约，使用 `GET /api/health`、`/api/stats`、`/api/stats/stream`、`/api/history`。`snapshot` 和 `stats` SSE 事件携带 `stats` 字段。兼容性按字段和能力检查，不能把 Hub 的 storage schema `version` 当作 Electron 应用版本。

- [Token Monitor API](https://github.com/Javis603/token-monitor/blob/main/docs/API.md)
- [Apple Liquid Glass 设计](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Apple 系统组件采用指南](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Sparkle 文档](https://sparkle-project.org/documentation/)

界面图标统一使用 Apple SF Symbols；后续维护约束见 AGENTS.md。

热力图和柱状图隐藏横向滚动条，但仍可用鼠标／触控板横向滚动。打开时默认定位最近日期。

底部三个操作按钮固定 44×44 pt 圆形。趋势右侧保留零标注，零值不绘制水平基线。

## Resize 性能复现

```bash
python3 scripts/make-resize-fixtures.py /tmp/token-monitor-resize
.build/release/TokenMonitorNative --preview-fixture /tmp/token-monitor-resize/stats.json --benchmark-resize
```

基准使用实际小窗、工具栏、玻璃操作、每秒刷新和快照接收路径，加载三年合成历史；从320 pt到屏幕可用宽度（至少1000 pt）往返调整120次，并切换周期60次。同步主线程耗时与超出16 ms节拍的额外调度延迟分别记录，不能当作屏幕FPS。真实快照及长历史对照见 `verification/0.4.1/`。
