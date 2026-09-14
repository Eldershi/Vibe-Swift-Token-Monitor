# 项目维护摘要

更新：2026-09-14。只记录当前状态；过程按需阅读版本验收，不复制对话或凭据。

## 当前版本

- 当前版本 **0.5.0（30）**，来自已清理的 `main` 历史；**Codex 优先的基础功能验证版本，暂不适合普通用户直接下载使用**；发布标签 `v0.5.0`，主分支 `main`。原生旧版 **0.4.1（21）** 保留。
- 为现有安装原位升级，沿用 `Token Monitor Native Beta.app`、`local.tokenmonitor.native.beta`、beta 数据目录和 LaunchAgent；版本页显示 0.5.0。名称兼容不代表覆盖旧稳定客户端。
- 本项目独立维护，复用原版 Token Monitor v0.56.0 的部分 MIT 后台模块，未捆绑 Electron。关系见[主页](README.md#与原版项目的关系)，固定来源及修改见[后台来源](TokenMonitorNative/Backend/UPSTREAM.md)。
- 开发规则集中在[工程说明](TokenMonitorNative/README.md#开发须知)，界面规格只在[UI 约束](TokenMonitorNative/AGENTS.md)，操作与回退只在[管理说明](TokenMonitorNative/BETA.md)。

本次仅更新 README、GitHub 简介/Release 文案及[路线图](ROADMAP.md)、[现有问题](docs/CURRENT_ISSUES.md)，不修改运行代码、版本、标签或附件。后续功能均为计划；工程规则按需读，不要求接手时通读路线图。

## 不可丢失的决策

- 本机采集与共享 Hub 分开：同一设备一个上传者、既有身份与持久历史基线、绝对快照幂等重试。保留原版供参考，接替时只关闭其 Hub 同步，不卸载或清除数据。
- 独立目录、锁、随包 Node/Tokscale；原工具凭据只读，禁止隐式刷新/模型会话。Hub 手动输入，独立 0600 明文文件原子保存，不访问 Hub 钥匙串，不输出密钥。
- Hub 协议与偏好 schema 3 兼容；未知 schema 不覆盖。原生视口管理宽度/偏移，秒级计时不触发全量筛选，用户浏览不被普通同步拉回。
- 设置主题色限定在控件，文字黑灰；手柄原生拖动并保留 AX 操作及持久化。保留官方导出 gear，不用近似符号。
- 公开发布只沿清理后的历史前进；旧本地 beta 分支不得合并或推送。按根 AGENTS 运行暂存与全部祖先检查，构建产物单独作为 Release 附件，不提交个人数据。

## 验证与后续

- 本次仅文档变更；暂存与全量公开检查通过，运行代码与原发布基线一致；未据此宣称完成新的运行或算法验收。
- 0.5.0：完整 Swift **55** 项、后台 **30** 项通过；发布包与扫描结果见[发布记录](TokenMonitorNative/verification/0.5.0/发布记录.md)。
- 构建 29 已检查各设置页颜色、顺序重开保留与 AX 入口；物理事件观察与坐标自动化的限制分别记录。性能和真实生命周期以[构建 23](TokenMonitorNative/verification/0.5.0-beta.2/验收.md)为既有基线，不能视为本次全部复测。
- 优先技术债：Hub 上传版本残留、同步写盘、退出/在途同步、SSE 背压、历史字段合并语义与依赖边界。下一阶段先可靠采样，重置预报与换算分别验证；5 个百分点是换算目标，不是预报概率。
- 当前 ad-hoc 签名、未公证、没有在线更新。后续优先补 macOS 26 真机、Codex 长期采样、实际注销登录、完整 VoiceOver、物理滚动/拖窗及长期资源验收；报告未测项，不宣称帧率。

## 常用验证

从根目录执行，更多参数见管理说明与工程说明。

```sh
swift test --build-system native --package-path TokenMonitorNative
TokenMonitorNative/Backend/runtime/node --test TokenMonitorNative/Backend/tests/*.test.cjs
bash TokenMonitorNative/scripts/build-beta.sh
python3 scripts/check-publication.py --staged
python3 scripts/check-publication.py
```

安装会替换同名独立应用并保留旧副本；`verify-beta-service.py --lifecycle` 会暂停/重启真实后台，仅在需要该验收时运行。
