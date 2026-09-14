# Token Monitor Native

macOS 26+ 的 SwiftUI / AppKit 用量统计应用。0.5 为 Codex 优先的基础验证版本，尚不适合普通用户直接使用；内置本机采集后台，并可同步到现有 Hub；0.4.1 为旧的 Hub 查看客户端。当前版本与验证状态见[维护摘要](../MAINTENANCE.md)，beta 安装、后台管理与安全回退见 [BETA.md](BETA.md)。

## 使用与数据

- 同一小窗展示总览、设备、模型、额度及活动详情；顶部选择今天／本月／总计。模型排序持久化，历史范围独立于顶部统计周期。当前版本无实时速率和额外日／月切换。
- 设置按通用、布局、数据、关于排列；数据页合并本机后台与 Hub。支持简体中文和英语，默认跟随系统；单应用语言在系统“语言与地区”指定，应用只保留入口。
- 布局设置支持首页额度定制，默认显示实际报告的 Codex 常规额度；额外模型额度在详情及动态可选列表中展示，自定义至少保留一项。
- 设置支持任意主题色、首页栏目显隐与右侧手柄拖拽排序。主题不覆盖连接绿色、过期橙色等语义颜色；设备栏目默认隐藏。
- 关闭窗口后可从菜单栏重开；`⌘,` 设置、`⌘R` 刷新、`⌘W` 关窗、`⌘Q` 退出界面。Beta 后台单独管理，退出界面不停止采集。
- 旧 0.4.1 在连接设置填写 Hub 地址及共享密钥，先测试再保存；这不是 OpenAI API Key。Beta 的本机查看与共享 Hub 汇总分开，后台管理始终连接本地服务。
- 费用是 API 等价估算，不是订阅账单；额度来自当前有效账号报告，不由 token 推算，不随统计周期累加。缺失、真实零值、过期与离线分别处理；断连保留最后快照，缺失历史不补零。

## 构建与维护入口

需要完整 Xcode、macOS 26 SDK 或更高版本；交付验证使用 SDK / macOS 27，最低部署 26。更新框架依赖固定为 Sparkle 2.10.0（MIT），其余 Swift 功能使用系统框架。

- 当前 0.5 独立通道：按 [BETA.md](BETA.md#构建安装和回退) 准备固定依赖、构建与安装，使用独立安装包更新。
- 旧 0.4.1 客户端：在对应源码版本中运行 `swift test --build-system native`、`bash scripts/build.sh`、`bash scripts/install.sh`；更新须递增版本/构建号。`bash scripts/rollback.sh` 恢复上一应用和升级前设置。当前 0.5 正式版本使用 build-beta.sh；build.sh 仅保留旧客户端入口。
- 安装脚本保留回退副本并执行启动自检；开发时避免同时运行安装副本与 dist 副本。当前为 ad-hoc 签名，未公证、支持 GitHub 正式版检查与用户确认后的签名更新；涉及原工具账号读取时应验证权限。

旧 0.4.1 Bundle ID 为 `local.tokenmonitor.native`，设置位于 `~/Library/Application Support/Token Monitor Native/`；beta 独立命名空间见 BETA。旧客户端共享密钥仍使用 Keychain；beta Hub 改为用户手动输入、保存在独立 0600 文件（详见 BETA），不访问旧钥匙串。密钥不得进入日志或状态响应。偏好 schema 3 迁移先备份，拒绝覆盖未来 schema；升级保留 `settings.json.pre-upgrade-backup`。

缓存仅保留建模的统计字段，不保存完整账号、订阅、项目或会话响应。HTTP 不带 Cookie，不跟随重定向转发密钥；HTTPS 保留证书校验。

## 架构

- `MonitorCore`：Hub DTO、校验、HTTP / SSE、历史与偏好兼容。
- `AppStore`：共享连接、展示数据预计算、缓存及睡眠唤醒；`TokenMonitorNative`：SwiftUI / Canvas、NSPanel、原生工具栏与滚动容器。
- `TokenMonitorBackend` 与 `Backend/`：随包辅助程序、独立采集、本地 Hub 和可选远端同步。第三方来源与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- `Tests/`、`Backend/tests/`：合成契约和回归；`verification/`：逐版本验收证据，按需读取。

Hub 基线为 Token Monitor v0.56.0：使用 `/api/health`、`/api/stats`、`/api/stats/stream`、`/api/history`；`snapshot` / `stats` SSE 事件携带 `stats` 字段。按字段与能力判断兼容性，不能把 storage schema 当应用版本。参考[上游 API](https://github.com/Javis603/token-monitor/blob/main/docs/API.md)。具体 UI 尺寸与操作约束只维护在 [AGENTS.md](AGENTS.md)。图标须对照实际渲染；系统同名符号与参考不一致时，使用官方导出资源，不能仅靠字重近似。本地化资源位于 MonitorCore，应用从随包资源读取，SwiftPM 开发构建使用模块资源。`python3 scripts/check-localization.py` 检查两种语言键与插值；beta 构建自动执行。构建脚本显式编译符号资产并检查资源包，普通 SwiftPM native 构建只复制目录。

## 开发须知

1. **验证真实入口。** 使用完整安装包、窗口和同步链路；NSEvent/拖拽必须实际操作，单元测试不代表交互验收。报告主线程工作耗时与 P95，不把等待时间当 FPS。
2. **减少主线程重算。** `body` 不做全量筛选/排序或创建格式器；正负解析缓存有界，展示数据按快照、来源、周期及过期边界失效。秒级时钟只驱动必要内容。
3. **尺寸与交互状态归属明确。** 原生视口负责宽度与滚动，标题栏留白只有一个所有者，正文可滚入玻璃后方；绘图缓存依赖尺寸，热力图跨周数边界才扩展。普通刷新保留历史偏移，稳定拖动会话使用窗口坐标。
4. **后台与保存有顺序。** 扫描、编码、磁盘和网络离开主线程；扫描禁止重叠，保存合并且防止旧写覆盖，退出完成末次保存；连接验证和保存成功再启用。
5. **独立后台可复现。** 命名空间、进程锁、数据目录隔离；锁定运行时/依赖并校验文件。确认真实后台进程、登录恢复及新采集时间，不能用终端成功或缓存代替。
6. **凭据与同步有边界。** 原工具凭据只读，不隐式刷新或启动模型会话；Hub 私有文件原子保存，状态/日志不含凭据或会话正文。同一设备一个上传者，先存历史基线和待传绝对快照，再发送并确认。
7. **保留数据语义与可访问性。** 原始观测、确认事件和预测分开；修正不删历史，验证按当时可见信息回放。缺失不等于零、未来日期不画，模型/日期聚合测试使用原始格式的合成日志。Canvas 保留 AX 描述，控件主题色不扩散到普通文字；可见性、排序及偏好重开验证。
8. **图形与输入共用几何。** 绘制、命中和高亮使用同一轮廓；短柱、圆角边缘、缺失值和控件遮挡同时检查。可见像素与命中状态分别验收；浮层不消费控件点击，不能把整条控件行屏蔽。原生宿主响应 effectiveAppearance，避免缓存整份 SwiftUI 环境导致颜色冻结。
9. **资源按平台工具编译。** SwiftPM复制资产不代表可被系统读取；应用图标与界面符号分别编译到正确bundle，合并工具生成的元数据，再按嵌套顺序签名。验证最终ZIP解压副本，避免同步目录的Finder扩展属性污染被误判为代码签名问题。
10. **交付前检查。** 分别列明自动测试、实际验收及未测项；源码与全部待推送历史通过公开检查，安装包不带真实配置或开发路径。来源、固定版本及许可证随第三方代码保留。

计划与现有技术债分别见[路线图](../ROADMAP.md)和[问题清单](../docs/CURRENT_ISSUES.md)，需要对应工作时再读取。

文档也保持单一职责：本节只写共性规则，维护摘要只写当前状态与待办，版本细节留在验收记录。修改既有条目并删除失效说明，不按版本反复追加经验，不要求接手者通读全部历史。

## 性能复现

在工程目录构建后运行；预览模式使用临时数据，不保存用户偏好、不读取密钥、不连接 Hub。

```sh
python3 scripts/make-resize-fixtures.py /tmp/token-monitor-resize
.build/release/TokenMonitorNative --preview-fixture /tmp/token-monitor-resize/stats.json --benchmark-resize
```

覆盖完整小窗、工具栏、玻璃操作、计时与快照接收；同步耗时和节拍额外延迟分开记录。Instruments 可加 `--benchmark-profile` 预热；具体结果见 [0.4.1](verification/0.4.1/性能与验收.md) 和 [Beta 2](verification/0.5.0-beta.2/验收.md)，不据此宣称屏幕帧率。

隔离的工具栏动画诊断及快捷键见[对照入口](verification/period-animation.md)，不属于正式产品设置。

## GitHub 更新

设置 → 关于 → 软件更新：手动检查、默认关闭的自动检查（应用运行时每 6 小时），安装必须确认。仅接收本仓库正式 Release，开发 Beta 不会降级至旧正式版；没有 appcast.xml 的旧 Release 提供 GitHub 手动下载入口。预览、冒烟及隔离验证入口不启动更新请求。

使用 Sparkle 标准下载/安装界面，Ed25519 校验清单及归档、验证后解压；不发送系统资料。更新在原安装路径替换应用，文件名可能保留旧版本号，关于页版本以包元数据为准；数据目录与后台身份保持不变。更新退出阶段先等待偏好写盘并注销原后台，重启后按已有用户偏好恢复；此服务生命周期尚需在实际安装副本中验收。

发布签名与密钥备份见 [更新发布说明](UPDATES.md)。

### 活动用量明细

图表保持连续历史，下面以原生 DisclosureGroup 展示年→月→日；默认仅最近有记录年份展开。年月小计来自日数据，缺失日期显示无数据，小计标记已记录。展开状态按来源地址和 Agent 在内存保持，刷新/切页不重置，重启恢复默认。ActivityRecords 为纯分组模型，ActivityExpansion 独立管理会话展开，年份/月份使用不同标识。

### 应用图标打包

Resources/Token Monitor.icon 为用户提供的原始 Icon Composer 图标，保留全部 SVG 图层和材质。两个构建入口都调用 scripts/compile-app-icon.py，使用 Apple actool 为 macOS 26.0 编译主包 Assets.car 与 Token Monitor.icns，并将工具生成的图标元数据合并到主 Info.plist，之后签名。主包图标目录与界面 SF Symbols 资源 bundle 分开；构建检查浅色、深色和着色 IconImageStack。参考 [Apple Icon Composer 文档](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。
