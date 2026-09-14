# 项目维护摘要

更新：2026-09-15。当前事实与接手事项集中于此；界面规格见 [UI 约束](TokenMonitorNative/AGENTS.md)，共性经验见[工程说明](TokenMonitorNative/README.md#开发须知)，逐项证据见[0.5.2 发布记录](TokenMonitorNative/verification/0.5.2/发布记录.md)。

## 当前状态

- 正式版本 **0.5.2（35）**，由 0.5.2-beta.1（34）收敛：活动详情及年/月明细折叠、图表实际柱形命中和可见高亮、玻璃控件交互优先、Agent 原生勾选、布局功能分组、GitHub 更新和 Icon Composer 应用图标。源码已推送 GitHub main，v0.5.2 已发布为最新正式 Release，附 ZIP、签名清单与 SHA256SUMS；未安装替换本机应用。
- 当前以 Codex 为重点，其他工具仅实验适配；最低 macOS 26，交付验证使用 macOS/Xcode 27，ad-hoc 签名、未公证。正式版本不代表普通用户使用门槛全部通过。
- 沿用 `local.tokenmonitor.native.beta`、既有数据目录与 LaunchAgent；Beta/β 和 build-beta 脚本是兼容通道标识。旧 0.4.1 Hub 客户端身份与构建入口独立。

## 关键决策

- 本机采集与共享 Hub 分开，同一设备一个上传者；凭据只读，不隐式刷新或启动模型会话。Hub 密钥由用户输入、0600 文件原子保存，不访问旧 Hub 钥匙串，不输出凭据。
- 偏好 schema 3 不变，新增字段缺失取默认值，未知 schema 不覆盖。首页热力图与趋势 ID、显隐及排序独立，共用活动详情；年月展开仅按来源/Agent 在本次运行内记忆。普通刷新不重置历史偏移。
- 本地化跟随 macOS；图表共用绘制/命中几何及原生透明浮层，外观从 effectiveAppearance 同步。原生视口负责宽度与滚动，顶部控件之间内容透出，不增加整条遮挡。
- 更新使用固定 Sparkle 2.10.0；自动检查默认关闭，开启后每 6 小时检查正式 Release，下载安装必须确认。原 Ed25519 私钥仅在忽略的 `.local-private/update-signing/ed25519.seed`（0600），须离线备份、不得轮换或公开；发布上传匹配 ZIP、签名 appcast.xml 与校验文件，见[更新说明](TokenMonitorNative/UPDATES.md)。
- 应用图标源为 Resources/Token Monitor.icon；Apple actool 生成主包分层资产、兼容 ICNS 与元数据，界面 SF Symbols 资源包独立。嵌套代码签名后校验最终 ZIP 解压副本，避免 Finder 扩展属性污染干扰。
- 只沿清理后的 main 前进，旧私有 beta 分支不合并。公开检查覆盖暂存内容与全部祖先；私钥、真实数据和个人记录仅放 `.local-private/`，构建包仅通过 Release 分发。

## 待办与验证边界

- 本轮 Swift 101 项、状态回归连续10轮、后台31项、本地化292键、最终包解析器及资源/签名验证通过；发布提交全历史公开检查通过，三个远端附件哈希与本地一致；发布后只读查询确认 latest=v0.5.2、signed-feed=true。ZIP 52,119,788字节，完整校验见发布记录。

- 自动回归、资源/签名检查与实际交互分别报告；本轮最终结果见发布记录，不累计多轮测试数。Beta 阶段已实际检查部分 320 pt 中英/深浅界面、年月折叠保持、图表高亮和顶部透出；未完成全部语言/主题/输入组合。
- 真实更新安装、权限失败、后台注销/恢复，macOS 26 真机、登录恢复、长期采样及完整 VoiceOver 仍需验收。发布回归复现 URLSession 已失效异常，已改为关闭客户端、取消任务并延后 session 失效到析构；迟到请求取消回归通过，后续仍需真实长期启停验收。
- 工具栏动画候选仅在[隔离诊断入口](TokenMonitorNative/verification/period-animation.md)，未替换正式控件；静态截图或 AX 点击不作连续动画证据。
- 后台版本上报、同步写盘、退出/在途同步、SSE 背压及历史合并等技术债见[问题清单](docs/CURRENT_ISSUES.md)。换算与重置预报仍是[路线图](ROADMAP.md)计划，不宣称已实现。

## 常用验证

从根目录运行：

```sh
swift test --build-system native --package-path TokenMonitorNative
TokenMonitorNative/Backend/runtime/node --test TokenMonitorNative/Backend/tests/*.test.cjs
python3 TokenMonitorNative/scripts/check-localization.py
bash TokenMonitorNative/scripts/build-beta.sh
python3 TokenMonitorNative/scripts/test-beta-logs.py --app 'TokenMonitorNative/dist/Token Monitor Native Beta.app'
python3 scripts/check-publication.py --staged
python3 scripts/check-publication.py
```

`verify-beta-service.py --lifecycle` 会操作真实后台，仅在明确需要时运行。版本与构建元数据由 prepare-beta.py 设置，ZIP 文件名从构建包读取，避免多处硬编码不一致。
