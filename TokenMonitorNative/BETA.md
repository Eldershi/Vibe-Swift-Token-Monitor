# 0.5.0 安装与后台管理（构建 30）

独立安装 `Token Monitor Native Beta.app`，面向 Apple Silicon，最低 macOS 26；实际验收系统及限制见下方验收记录。Bundle ID 为 `local.tokenmonitor.native.beta`；菜单栏数字后的 `β` 用于区分稳定版。无需运行原 Electron 应用，也无需自行安装 Node.js。

## 数据与后台

- 独立读取本机 Codex、Claude Code 日志，计算用量、模型、历史及 API 等价费用；本机查看与共享 Hub 汇总分开，启用同步后可查看已有其他设备。
- 首次扫描可能需要等待价格下载和历史扫描。仅本机模式不会凭空恢复已删除日志；启用 Hub 接替时保留 Hub 已有历史基线。采集器保留 beta 已经观察到的用量，后续日志截断或删除不会抹掉这部分历史。
- 额度只读取原工具现有有效登录信息。未登录、登录失效或接口不可用不会阻断用量统计；在原工具重新登录后点击“立即刷新”。不使用旧软件的账号设置，不自动刷新登录凭据，不启动模型会话。
- 费用是按模型价格计算的 API 等价估算，并非订阅账单；首轮联网获取价格，之后使用 beta 自有缓存。
- 所有 beta 可写文件在 `~/Library/Application Support/Token Monitor Native Beta/`，采集器状态在其 `Backend/` 子目录。稳定版设置、旧应用数据和工具原始日志保持分离。

设置中的“后台”显示服务、最近成功采集时间和额度来源状态。关闭窗口或退出界面后继续采集，下次登录由系统启动后台。系统如要求允许后台运行，使用设置中的入口进入“登录项与扩展”。

Hub 地址和密钥由用户在设置中手动输入；连接验证成功后，密钥保存于 beta 的 `Backend/hub-credential.json`（0600、明文、仅当前用户权限），后台重启可继续使用。Hub 不读写或迁移钥匙串，旧条目保留但不再使用；状态与诊断不返回密钥。Claude 账号读取仍保持只读且后台禁止弹窗。

“暂停采集”保留本地连接并持久化暂停状态；“恢复采集”重新开始扫描；“重启后台”由系统重启服务。“停用后台”注销后台服务，后续登录不再启动；重新打开 beta 后可点击“启用后台”。

## 构建、安装和回退

在工程目录运行：

```sh
python3 scripts/prepare-beta.py --download
bash scripts/build-beta.sh
bash scripts/install-beta.sh
```

首次准备需要网络和开发机的 npm。Node 24.19.0 官方归档与固定 Tokscale fork 均校验 SHA-256；npm 依赖由 lockfile 固定。运行时完全内置，安装后不依赖 npm、系统 Node 或原应用的文件。

产物为 `dist/Token-Monitor-Native-0.5.0-arm64.zip`。当前使用 ad-hoc 签名，未公证、未配置在线更新。最低系统及实际人工验收限制见[0.5.0 发布记录](verification/0.5.0/发布记录.md)。

从 Release 下载后解压并复制到 `~/Applications/`（已有同名应用时先退出界面、保留旧副本）；也可使用源码安装脚本自动保留回退副本。安装名称与命名空间沿用 beta，以保留现有设置、历史与服务身份。

安装脚本仅替换 beta，并在更新已有 beta 时保留带时间戳的上一应用包。稳定版 0.4.1 不参与替换。后台状态与历史保持兼容；若未来升级修改数据格式，应先备份 beta 数据目录。

卸载前先按下方步骤停用 Hub 同步，再在 beta 设置中点击“停用后台”，然后退出界面，将 beta 应用移到废纸篓即可。数据默认保留，稳定版可以继续使用。需要回退应用包时，同样先停用同步和后台并退出，再把安装脚本留下的上一应用包恢复为 `Token Monitor Native Beta.app`；随后启用后台，核对该版本的同步能力。

## 回归验证

```sh
swift test --build-system native
Backend/runtime/node --test Backend/tests/*.test.cjs
```

另外在工程目录运行：

```sh
python3 scripts/test-beta-logs.py
python3 scripts/test-beta-logs.py --app "$HOME/Applications/Token Monitor Native Beta.app"
python3 scripts/verify-beta-service.py
```

`verify-beta-service.py --lifecycle` **会暂停、重启并模拟崩溃当前 beta 后台**，随后恢复原暂停状态；仅供明确需要生命周期验收时使用。合成日志测试使用 `--home` 指定临时源目录，不修改用户主目录或真实日志。

构建 23 的完整结果与人工验收限制见 [验收记录](verification/0.5.0-beta.2/验收.md)；0.5.0 验证见[发布记录](verification/0.5.0/发布记录.md)。

## 共享 Hub 接替与回退

设置的“Hub”页支持验证连接、绑定已有本机设备、启停同步和查看“仅本机／共享 Hub”。本机采集与界面退出相互独立；Hub 离线继续采集，界面保留上次汇总和真实同步时间。

同一台设备只能有一个上传者：原版应选择 **仅本机**，可以继续打开作为参考。无需卸载原版或关闭其本机采集；其他设备配置与原版开机启动偏好可保持不变。

切换前自行备份原版设置。后台保存 `Backend/hub-sync.json`（无密钥）、`hub-baseline.json` 和切换快照；手动密钥单独保存在上述私有文件，不进入配置响应或历史基线。已有历史与本机数据在日期、工具、模型维度建立基线，覆盖重合部分取已知较完整值，之后加入本机归档的增量。持久化高水位避免截断/重放重复计数；先保存待上传的完整快照，重试发送同一绝对结果。历史统计保留，旧工具的状态时间不伪装成新采集时间。

回退步骤：

1. 在 beta“Hub”设置中停用同步，确认已停用；需要回退整个后台时再停用独立后台。
2. 原版的 Hub 设置恢复为“连接到 Hub”，沿用原地址、密钥及设备身份。不要在 beta 仍上传时恢复原版同步。
3. 如需恢复上一 beta，运行其随附安装流程。旧应用副本与设置/切换快照保留；不要直接删除或重置基线后重新上传。

旧 `--beta-prepare-hub` / `--beta-enable-hub` 入口已停用，统一从设置手动配置，不从稳定版或旧软件导入密钥。
