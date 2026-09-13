# 项目维护摘要

最后更新：2026-09-13（Asia/Shanghai）

## 当前状态

- GitHub公开仓库：[Eldershi/Vibe-Swift-Token-Monitor](https://github.com/Eldershi/Vibe-Swift-Token-Monitor)，本目录为Git根目录，默认分支`main`，`origin`指向该仓库并跟踪`origin/main`。2026-09-13已创建并推送首次源码提交，核验归属、`PUBLIC`可见性及远程/本地提交一致。
- 工作源码：本目录 `TokenMonitorNative/`，Swift Package / SwiftUI / AppKit，最低macOS26；后续以此目录为准，原Documents目录未修改。
- 已构建、签名并安装 **0.4.1（构建21）** 至 `~/Applications/Token Monitor Native.app`；产物在 `TokenMonitorNative/dist/`。
- 旧版0.4.0（构建20）在 `~/Applications/Token Monitor Native.previous.app`；设置保留 `settings.json.pre-upgrade-backup`。Hub未停止。
- 安装后真实小窗已显示“已连接 · 实时同步”，数据时间持续更新（最终包19:15）；实际点击本月/今天正常更新，已恢复原来的今天视图。自定义颜色、栏目顺序/可见性及来源选择保留。

## 关键决策

- 公开推送隐私检查：移除历史文档中的本机用户名路径和对话分享链接，保留应用源码与原作者信息。新增 Gitleaks + 文件/链接检查，钩子扫描待推送提交及所有祖先；本机已启用 `.githooks` 并安装 Gitleaks 8.30.1 至不被追踪的 Git 工具目录。缺少扫描器或检查失败即停止推送。

- 仓库保留`TokenMonitorNative/`结构，根README提供构建入口；提交源码、合成测试样本和文档，忽略构建产物、缓存、本地设置与凭证。保留第三方声明，未新增项目许可证或Release；本轮不修改应用代码、不重建应用。
- 通用开发经验简要收录于 [README 开发须知](TokenMonitorNative/README.md#开发须知)，涵盖采样、缓存失效、局部观察、后台保存、尺寸/滚动归属及验收；开发约束已链接该节。此轮仅更新文档，并校正过时的图表、玻璃和基准说明，未改代码或重建应用。

- 已观察热点：真实主线程 `sections → quotaProviders → tools → Device.hasUsableData → ISO8601DateFormatter`。两个日期解析器复用、加锁，最多512条正/负缓存；工具/额度/设备清单和模型排序按快照、来源、周期及过期边界准备。
- RuntimePreferences独立观察各字段，持久化仍用兼容的Preferences schema3。每秒时钟不触发整页历史/筛选重算；普通偏好150ms合并保存，缓存编码和写盘在独立actor，修订号防旧写覆盖。连接确认保存后启用；退出等待最终保存。钥匙串读取移至后台。
- 根NSHostingView关闭额外尺寸推导，窗口最小320×400 pt、不设最大宽度。页面由自有NSScrollView管理，AppKit约束宽度、SwiftUI回报内容高度。
- 右缘原生滑块视觉5pt浅灰、操作区14pt、无常驻轨道；滚动/拖动/右缘悬停显示，停用离开后淡出。不修改系统滚动条设置。
- 历史横向滚动偏移由AppKit管理。首次有效布局、页面/小窗重新进入、来源切换跟随最新；手动浏览后同步更新保留位置。
- 热力图7pt方块/3pt间距/104pt高度，宽窗口向左补无数据日期；未来不绘制。基础历史投影与扩展日期分开缓存，16…190周连续变化不会重新解析历史。Canvas批量绘制并保留AX图表数据。
- 每日趋势5pt柱宽，月份边界标签，圆角边框包含纵轴。主题任意颜色/系统ColorPicker、首页右侧拖拽手柄及持久化沿用0.4.0。

## 验证与结果

- 50项测试通过；release签名、构建与安装启动自检通过。最终安装二进制与dist产物SHA-256一致，设置与升级前备份按语义一致（隐藏栏目按集合比较）。Hub协议和偏好schema兼容。
- 完整实际小窗（工具栏、玻璃操作、ticker、快照接收）对照，320/600/1000/1920pt、真实110日快照与1095天合成历史。真实周期同步工作中位数300.33→8.65ms；resize额外调度延迟P95 75.73→4.08ms、最大294.03→4.12ms。
- 三年历史同步resize P95 32.02→10.26ms。同步工作与节拍等待分开记录，**不是屏幕FPS**；未宣称所有工作达到5ms或所有高刷新率帧预算。
- 宽窗口画面、最新日期、完整月份/边框、原生滚轮与无障碍滑块操作已检查。仅预览进程参数`-AppleShowScrollBars Always`下静止滑条隐藏；系统全局偏好未改。
- 详情和原始数字在 `TokenMonitorNative/verification/0.4.1/性能与验收.md`；旧0.4.0简化基准不能代表真实交互，应以本轮完整小窗结果为准。

## 后续与已知验证限制

- 隐私清理会改变主线提交ID。基于旧历史的本地开发分支必须将独立改动移到清理后的 `main` 上，再通过检查；不得将旧历史合并回公开仓库。历史重写不保证清除 GitHub 的旧提交缓存或他人已有副本；自动扫描也不能证明不存在所有隐私信息。

- Instruments记录已得到25,251条Time Profiler样本，但多次尝试（完整签名包、预热、布局追踪）仍报告无SwiftUI数据，**更新因果图尚未完成验收**。记录与主线程样本保留 `/tmp/token-monitor-041-*`，未推断为确定系统缺陷。
- 自动鼠标拖窗被Computer Use `windowNotFoundAtPosition`阻断；真实物理拖窗/滑块和完整VoiceOver导航仍需人工体验复核。程序化真实窗口resize及数据/偏移回归已有验证。
- Swift native构建驱动仍有弃用提示；默认Xcode后端在同步目录曾因签名扩展属性失败。本轮沿用可用的native驱动。

## 已验证命令

在项目根目录运行：

- Gitleaks 8.30.1 对原有两次提交和清理后的 `main` 全历史扫描均未发现凭证；GitHub 密钥告警列表为空，密钥扫描与推送保护已开启。发布文件不含应用真实配置/缓存；3个JSON夹具与合成生成脚本逐字一致。
- `python3 scripts/check-publication.py --ref main`（历史隐私及凭证检查通过）；8项隐私规则检查、正常暂存放行/伪造凭证拦截与脱敏/本地设置拦截/扫描器缺失拦截共4类隔离集成检查通过。

- `git init -b main`、`git add .`、`git diff --cached --check`（首次暂存59个文件，格式检查通过）。
- `git check-ignore TokenMonitorNative/.build/ TokenMonitorNative/dist/ .env settings.json`（均被忽略）。
- `gh repo create Eldershi/Vibe-Swift-Token-Monitor --public`（创建公开仓库）。
- `gh repo view Eldershi/Vibe-Swift-Token-Monitor --json nameWithOwner,visibility,url`（归属与公开状态正确）。
- `git push -u origin main`（首次推送成功）；`git ls-remote origin refs/heads/main`与`git rev-parse HEAD`一致，`git status --short --branch`确认工作区干净且跟踪`origin/main`。
- `gh repo view Eldershi/Vibe-Swift-Token-Monitor --json defaultBranchRef`（默认分支`main`）；GitHub tree API确认根README、维护说明与工程目录已上传。暂存文件凭证模式检查的唯一命中为普通错误提示文字，未发现凭证，构建产物未纳入提交。

在 `TokenMonitorNative/` 运行：

- `swift test --build-system native`（50项通过）。
- `bash scripts/build.sh`（默认0.4.1/build21；release、签名、启动自检）。
- `bash scripts/install.sh`（用户应用升级及备份）。
- `python3 scripts/make-resize-fixtures.py /tmp/token-monitor-resize`。
- `.build/release/TokenMonitorNative --preview-fixture /tmp/token-monitor-resize/stats.json --benchmark-resize`。
- Instruments入口附加 `--benchmark-profile` 可在记录前预热10秒、结束前保留5秒；正常基准不含这些等待。

Swift编译及Instruments缓存需要用户目录写权限。预览/基准为临时数据模式，不保存用户偏好、不读取密钥、不连接Hub。
