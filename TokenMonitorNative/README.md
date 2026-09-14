# Token Monitor Native

macOS 26+ 的 SwiftUI / AppKit 用量统计应用。0.5 为 Codex 优先的基础验证版本，尚不适合普通用户直接使用；内置本机采集后台，并可同步到现有 Hub；0.4.1 为旧的 Hub 查看客户端。当前版本与验证状态见[维护摘要](../MAINTENANCE.md)，beta 安装、后台管理与安全回退见 [BETA.md](BETA.md)。

## 使用与数据

- 同一小窗展示总览、设备、模型、每日趋势及栏目详情；顶部选择今天／本月／总计。模型排序持久化，历史范围独立于顶部统计周期。当前版本无实时速率和额外日／月切换。
- 0.5.1 设置按通用、布局、数据、关于排列；数据页合并本机后台与 Hub。支持简体中文和英语，默认跟随系统；单应用语言在系统“语言与地区”指定，应用只保留入口。
- 0.5.1 的布局设置支持首页额度定制，默认显示实际报告的 Codex 常规额度；额外模型额度在详情及动态可选列表中展示，自定义至少保留一项。
- 设置支持任意主题色、首页栏目显隐与右侧手柄拖拽排序。主题不覆盖连接绿色、过期橙色等语义颜色；设备栏目默认隐藏。
- 关闭窗口后可从菜单栏重开；`⌘,` 设置、`⌘R` 刷新、`⌘W` 关窗、`⌘Q` 退出界面。Beta 后台单独管理，退出界面不停止采集。
- 旧 0.4.1 在连接设置填写 Hub 地址及共享密钥，先测试再保存；这不是 OpenAI API Key。Beta 的本机查看与共享 Hub 汇总分开，后台管理始终连接本地服务。
- 费用是 API 等价估算，不是订阅账单；额度来自当前有效账号报告，不由 token 推算，不随统计周期累加。缺失、真实零值、过期与离线分别处理；断连保留最后快照，缺失历史不补零。

## 构建与维护入口

需要完整 Xcode、macOS 26 SDK 或更高版本；交付验证使用 SDK / macOS 27，最低部署 26。无第三方 Swift 依赖。

- 当前 0.5 独立通道：按 [BETA.md](BETA.md#构建安装和回退) 准备固定依赖、构建与安装，使用独立安装包更新。
- 稳定通道：在对应稳定源码版本中运行 `swift test --build-system native`、`bash scripts/build.sh`、`bash scripts/install.sh`；更新须递增版本/构建号。`bash scripts/rollback.sh` 恢复上一应用和升级前设置。不要把当前 beta 分支直接打包为旧稳定版本。
- 安装脚本保留回退副本并执行启动自检；开发时避免同时运行安装副本与 dist 副本。当前为 ad-hoc 签名，未公证、未配置在线更新；涉及原工具账号读取时应验证权限。

旧 0.4.1 Bundle ID 为 `local.tokenmonitor.native`，设置位于 `~/Library/Application Support/Token Monitor Native/`；beta 独立命名空间见 BETA。稳定版共享密钥仍使用 Keychain；beta Hub 改为用户手动输入、保存在独立 0600 文件（详见 BETA），不访问旧钥匙串。密钥不得进入日志或状态响应。偏好 schema 3 迁移先备份，拒绝覆盖未来 schema；升级保留 `settings.json.pre-upgrade-backup`。

缓存仅保留建模的统计字段，不保存完整账号、订阅、项目或会话响应。HTTP 不带 Cookie，不跟随重定向转发密钥；HTTPS 保留证书校验。

## 架构

- `MonitorCore`：Hub DTO、校验、HTTP / SSE、历史与偏好兼容。
- `AppStore`：共享连接、展示数据预计算、缓存及睡眠唤醒；`TokenMonitorNative`：SwiftUI / Canvas、NSPanel、原生工具栏与滚动容器。
- `TokenMonitorBackend` 与 `Backend/`：随包辅助程序、独立采集、本地 Hub 和可选远端同步。第三方来源与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- `Tests/`、`Backend/tests/`：合成契约和回归；`verification/`：逐版本验收证据，按需读取。

Hub 基线为 Token Monitor v0.56.0：使用 `/api/health`、`/api/stats`、`/api/stats/stream`、`/api/history`；`snapshot` / `stats` SSE 事件携带 `stats` 字段。按字段与能力判断兼容性，不能把 storage schema 当应用版本。参考[上游 API](https://github.com/Javis603/token-monitor/blob/main/docs/API.md)。具体 UI 尺寸与操作约束只维护在 [AGENTS.md](AGENTS.md)。图标须对照实际渲染；系统同名符号与参考不一致时，使用官方导出资源，不能仅靠字重近似。本地化资源位于 MonitorCore，应用从随包资源读取，SwiftPM 开发构建使用模块资源。`python3 scripts/check-localization.py` 检查两种语言键与插值；beta 构建自动执行。构建脚本显式编译符号资产并检查资源包，普通 SwiftPM native 构建只复制目录。

图表悬停统一由 `HeatmapHover.swift` 的原生透明浮层处理：首页与详情共用几何、命中和清除逻辑，柱形绘制及内描边共用胶囊半径。`LiveAppearanceHostingView` 直接响应原生外观变化，禁止缓存整份 SwiftUI 环境。设备条比例由 `DeviceUsageComparison` 统一计算；新偏好缺失使用默认值，保持 schema 3。

## 开发须知

1. **验证真实入口。** 使用完整安装包、窗口和同步链路；NSEvent/拖拽必须实际操作，单元测试不代表交互验收。报告主线程工作耗时与 P95，不把等待时间当 FPS。
2. **减少主线程重算。** `body` 不做全量筛选/排序或创建格式器；正负解析缓存有界，展示数据按快照、来源、周期及过期边界失效。秒级时钟只驱动必要内容。
3. **尺寸与交互状态归属明确。** 窗口负责标题栏、原生视口负责宽度，内容顶部对齐；绘图缓存依赖尺寸，热力图跨周数边界才扩展。普通刷新保留历史偏移，稳定拖动会话使用窗口坐标。
4. **后台与保存有顺序。** 扫描、编码、磁盘和网络离开主线程；扫描禁止重叠，保存合并且防止旧写覆盖，退出完成末次保存；连接验证和保存成功再启用。
5. **独立后台可复现。** 命名空间、进程锁、数据目录隔离；锁定运行时/依赖并校验文件。确认真实后台进程、登录恢复及新采集时间，不能用终端成功或缓存代替。
6. **凭据与同步有边界。** 原工具凭据只读，不隐式刷新或启动模型会话；Hub 私有文件原子保存，状态/日志不含凭据或会话正文。同一设备一个上传者，先存历史基线和待传绝对快照，再发送并确认。
7. **保留数据语义与可访问性。** 原始观测、确认事件和预测分开；修正不删历史，验证按当时可见信息回放。缺失不等于零、未来日期不画，模型/日期聚合测试使用原始格式的合成日志。Canvas 保留 AX 描述，控件主题色不扩散到普通文字；可见性、排序及偏好重开验证。
8. **交付前检查。** 分别列明自动测试、实际验收及未测项；源码与全部待推送历史通过公开检查，安装包不带真实配置或开发路径。来源、固定版本及许可证随第三方代码保留。

计划与现有技术债分别见[路线图](../ROADMAP.md)和[问题清单](../docs/CURRENT_ISSUES.md)，需要对应工作时再读取。

文档也保持单一职责：本节只写共性规则，维护摘要只写当前状态与待办，版本细节留在验收记录。修改既有条目并删除失效说明，不按版本反复追加经验，不要求接手者通读全部历史。

## 性能复现

在工程目录构建后运行；预览模式使用临时数据，不保存用户偏好、不读取密钥、不连接 Hub。

```sh
python3 scripts/make-resize-fixtures.py /tmp/token-monitor-resize
.build/release/TokenMonitorNative --preview-fixture /tmp/token-monitor-resize/stats.json --benchmark-resize
```

覆盖完整小窗、工具栏、玻璃操作、计时与快照接收；同步耗时和节拍额外延迟分开记录。Instruments 可加 `--benchmark-profile` 预热；具体结果见 [0.4.1](verification/0.4.1/性能与验收.md) 和 [Beta 2](verification/0.5.0-beta.2/验收.md)，不据此宣称屏幕帧率。
