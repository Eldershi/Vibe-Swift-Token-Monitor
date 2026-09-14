# 0.5.0 现有问题与技术债

检查日期：2026-09-14。0.5.2 发布时复核：下列后台技术债仍待处理，当前测试数见 [0.5.2 发布记录](../TokenMonitorNative/verification/0.5.2/发布记录.md)。基线为 `v0.5.0` / 构建 30。本次为源码与发行包检查，**没有修改运行代码，也不是完整性能或安全审计**。下表区分已见代码事实与仍需实测的影响；开发顺序见[路线图](../ROADMAP.md)。

## 后台优先事项

| 已确认的代码事实 | 影响与后续验证 |
|---|---|
| [HubSync.advance](../TokenMonitorNative/Backend/hub-sync.cjs) 对非排除项的数值通用地做高水位增量合并 | 计数、费用修正、派生统计和数值元数据应分开定义。现有样本通过，不代表新字段或历史价格修正已覆盖；先补固定样本，不直接改写现有 Hub 历史。 |
| [HubSync.advanceRecord](../TokenMonitorNative/Backend/hub-sync.cjs) 仍将上传版本写为 `0.5.0-beta.2`，入口与包版本是 `0.5.0` | 已确认版本来源不一致，可能误导排障；统一来源并增加上传版本断言。 |
| [HubSync.close](../TokenMonitorNative/Backend/hub-sync.cjs) 只清定时器，最新 `pending` 在内存中；已进入上传流程的绝对快照才持久化 `pendingUpload` | 退出未等待或取消在途同步；需要验证退出期间的新快照、失败重试及恢复顺序。不能笼统说“没有持久化”或据此断言已发生数据丢失。 |
| [main](../TokenMonitorNative/Backend/main.cjs)、[HubSync](../TokenMonitorNative/Backend/hub-sync.cjs)、[Hub server](../TokenMonitorNative/Backend/vendor/src/hub/server.js) 使用同步 JSON 编码/写盘；主入口每次转换用量还读写会话归档 | 会阻塞 Node 后台事件循环；计划串行异步化与合并保存。实际延迟和资源影响须测量，不能直接认定这是 SwiftUI 拖窗卡顿的原因。 |
| [Hub SSE](../TokenMonitorNative/Backend/vendor/src/hub/server.js) 及 [远端汇总 SSE](../TokenMonitorNative/Backend/main.cjs) 没有根据 `res.write()` 返回值控制背压 | 慢客户端可能积压缓冲；补慢读、断连和退出测试，再选择合并快照或重连策略。尚未做内存增长实测。 |
| [主入口](../TokenMonitorNative/Backend/main.cjs) 集中了生命周期、HTTP 控制、采集转换、SSE 与同步连接 | 目前仍能定位职责，但新算法继续堆在入口会增加耦合；先抽清边界，避免全盘重写。 |
| [打包脚本](../TokenMonitorNative/scripts/prepare-beta.py) 整体复制 vendor 与 node_modules；保留了更新、切换等上游模块 | 有收敛空间，但不能视为全部可删。`semver` 也被采集器使用、`undici` 承担网络代理等职责；需做真实入口/动态加载/安装包测试后裁剪。 |
| [resetBoundary](../TokenMonitorNative/Backend/vendor/src/shared/limits/resetBoundary.js) 已为官方重置时间安排刷新 | 当前缺的是异常重置事件、原始采样历史、校准与预报；不是再实现一套倒计时。 |

## 体积与代码规模

构建 30 的 ZIP 为 **49,084,449 字节（49.08 MB）**；解包应用逻辑文件总大小约 **148.62 MB**，其中 Node 运行时约 **120.74 MB**，占应用约 81%。MB 按十进制计算，文件系统占用可能不同；这是当前附件的测量，不是未来构建保证。

主体体积来自运行时，删几段源码不会明显缩包。依赖裁剪与减小运行时是不同工作，应先保证独立采集与可复现，再评估收益。

原生侧已有 Core、展示状态、视图及原生滚动边界，后台也有独立模块和回归测试，**目前没有证据表明必须整体推倒重写**。但原生入口/视图与上游采集器仍较集中，后台混合职责、通用合并和依赖边界属于实际技术债。“文件少/行数短”不等于可维护，也不能据此保证没有其他缺陷。

## 使用成熟度

- 目前主要针对 Codex；其他工具仅有实验适配，不作为正式支持承诺。
- 基础功能已验证，0.5.2 已接入 Icon Composer 图标；菜单栏自定义等体验尚未完善；暂无额度换算、不规则重置识别/预报、饼图或 Widget。
- 当前为 ad-hoc 签名、未公证、无在线更新；实际验证系统是 macOS 27，最低部署 macOS 26 不等于已完成 macOS 26 真机验收。
- 现有自动回归与构建自检数量见当前发布记录；长期运行、真实登录恢复、完整辅助功能与升级回退等门槛仍需补齐。详见[发布记录](../TokenMonitorNative/verification/0.5.2/发布记录.md)。

- 更新安装的真实权限失败、回退及后台服务恢复仍待端到端验收；0.5.2 已实现检查与签名更新流程，不把清单生成视为安装成功。0.5.2 发布回归复现 URLSession 失效异常，已修复取消与任务创建竞态并增加关闭客户端的迟到请求测试；长期启停仍需验证。
