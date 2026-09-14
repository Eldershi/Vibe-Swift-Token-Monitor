# 时间跨度动画对照

独立诊断入口复用正式顶部 NSToolbarItemGroup，固定 320×500 pt，不启动计时器/网络，不保存页面、窗口或应用偏好。仅使用合成样本；日志路径必须不存在，避免覆盖已有证据。

```sh
'TokenMonitorNative/dist/Token Monitor Native Beta.app/Contents/MacOS/TokenMonitorNative' --verify-period-animation --preview-fixture /tmp/period-fixture/stats.json --period-log /tmp/period-comparison.jsonl
```

以上从仓库根目录运行，fixture 目录需同时包含合成的 history.json。⌘1 为 A（固定纯色正文），⌘2 为 B（完整正文但不随周期更新），⌘3 为 C（正常周期更新）；每次回到本月。⌘⇧L / ⌘⇧D 切换浅深外观。模式切换保持顶部控件实例；不要将 A/B 中选中项与正文周期不同误认为数据错误。日志记录本窗口事件、选中次数、实例是否保持和外观/激活状态，不采集屏幕或其他窗口输入。诊断结束使用 ⌘Q。

需分别观察悬停、停留后点击、快速切换和原生键盘操作。辅助工具的 AX 点击不能替代物理鼠标悬停；静态截图和事件日志不能证明短动画的视觉表现。只有 A 也复现相同明度过渡，才能说明现象无需正文更新即可出现，仍不等于苹果确认的 Bug。

macOS 27 取消横移候选：启动参数增加 `--period-value-selection`，仅在诊断入口设置公开 `role = .valueSelection`，保持 `.selectOne`。⌘4 恢复 automatic，⌘5 切回 valueSelection；不重建工具栏或改变正文模式，日志增加 role。先在 A 和 C、浅深外观各重复五轮，由用户观察横移与明度衔接；确认前不用于正式入口。若仍滑动，再验证显式 `.rounded` 原生 NSSegmentedControl。

第二候选启动参数为 `--period-rounded`（同时保留 `--verify-period-animation`、fixture 与新日志路径）。工具栏持有显式 NSSegmentedControl，rounded/selectOne，macOS 27 默认 valueSelection，无额外玻璃。⌘1/2/3 和浅深快捷键不变；此入口中 ⌘4/5 **只切换分段控件的 role**，不切回原 NSToolbarItemGroup。日志 control 字段区分实现。


当前仅保留隔离诊断入口，正式顶部控件未采用候选实现。历史观察见 [0.5.2 beta 验收](0.5.2-beta.1/验收.md)，不将候选参数描述为已修复的动画行为。
