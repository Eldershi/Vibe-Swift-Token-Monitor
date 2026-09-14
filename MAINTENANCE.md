# 项目维护摘要

更新：2026-09-15。只记录当前状态、关键决策和接手事项；详细验证见版本记录。

## 当前状态

- 当前正式版本 **0.5.1（33）**，发布标签 `v0.5.1`，主分支 `main`。本次从 Beta2 收敛，新增中英本地化、设置整理、动态额度定制、设备用量条及统一图表悬停，修复外观同步与最小窗口宽度。发布验收见[0.5.1 记录](TokenMonitorNative/verification/0.5.1/发布记录.md)。
- 沿用 `local.tokenmonitor.native.beta`、Beta 数据目录及 LaunchAgent，安装脚本文件名包含版本与构建号；Beta 名称是兼容通道标识，正式版本展示为 0.5.1。旧 0.4.1（21）Hub 客户端身份与构建入口保留。本次不替换本机安装。
- 当前仍是 Codex 优先的基础功能验证应用，其他工具不是重点支持范围；ad-hoc 签名、未公证、无自动更新。正式 Release 不代表所有运行环境已验收。
- 独立维护的原生衍生实现，复用原版 v0.56.0 的部分 MIT 后台，不捆绑 Electron。参见[工程说明](TokenMonitorNative/README.md)、[后台来源](TokenMonitorNative/Backend/UPSTREAM.md)、[安装管理](TokenMonitorNative/BETA.md)和[UI 约束](TokenMonitorNative/AGENTS.md)。

## 关键决策

- 本机采集和共享 Hub 分开，同一设备一个上传者；保留设备身份、历史基线和绝对快照幂等重试。原工具凭据只读，不隐式刷新或启动模型会话。Hub 凭据由用户手动输入，独立 0600 明文文件原子保存，不访问 Hub 钥匙串，不输出密钥。
- 语言由 macOS（含单应用覆盖）选择，支持简体中文与英语，其他语言英语兜底；应用只保留系统设置入口。设置固定为通用、布局、数据、关于，数据页合并后台和 Hub。
- 偏好 schema 3 不变，新字段缺失使用默认值；未知 schema 不覆盖。首页额度默认显示报告中的 Codex 常规窗口，自定义至少一项；选项随有效报告动态增删，不硬编码订阅等级或模型停用日期。
- 首页用量固定顶部；栏目空白不可点击，详情标题和图标可点击，望远镜中性、其他详情图标强调色。设备系统图标 13.5 pt 居中；设备详情显示相对最高用量条，首页默认关闭。首页隐藏采集诊断，详情保留，过期状态不隐藏。
- 窗口最小内容宽 320 pt；原生视口维护宽度与历史偏移。首页与详情热力图/柱状图共用几何、命中和原生透明提示层；胶囊柱内部描边，强调随主题色。外观宿主从 effectiveAppearance 回调同步 SwiftUI，禁止复制整份环境冻结明暗颜色。
- 官方 gear 资源保留；设备 Icons8 素材按其许可署名，不纳入上游 MIT 许可，随包附来源说明。
- 只沿清理后的主分支历史前进，旧私有 beta 分支不得合并或推送。公开检查同时覆盖暂存内容与全部祖先；真实数据、凭据和个人记录只放被忽略的 `.local-private/`，构建包通过 Release 分发。

## 验证与待办

- 本次 Swift **85** 项、后台 **31** 项、**263** 个中英资源键、独立构建、严格签名和应用/后台冒烟通过；最终包真实解析器的合成日志回归通过。界面检查范围和未测项详见发布记录。
- 技术债仍包括后台上传版本来源不统一、同步写盘、退出/在途同步、SSE 背压、历史合并语义和依赖边界，见[问题清单](docs/CURRENT_ISSUES.md)。没有为了本次 UI 发布修改采集协议或后台生命周期。
- 后续补 macOS 26 真机、Codex 长期采样、实际注销登录、完整 VoiceOver、物理滚动/拖窗及长期资源验收。重置预报与换算分别验证；5 个百分点是换算目标，不是预报概率。

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

安装脚本归档唯一顶层旧 Beta 包并保留其版本；`verify-beta-service.py --lifecycle` 会暂停/重启真实后台，仅在需要该验收时运行。Beta 开发版必须有序号，完整展示版本、安装名称和 ZIP 一致；系统数字版本与展示版本分开。
