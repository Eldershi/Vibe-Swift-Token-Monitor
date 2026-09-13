# UI constraints

- Use Apple SF Symbols for all interface icons unless the user explicitly requests an exception. No third-party icons or custom SVG icons.
- Use system native controls. Glass belongs to floating navigation/actions; no content glass cards or nested glass.
- Bottom navigation uses plain native buttons with NSMenu popups with one explicit system glassEffect per control inside a non-rendering GlassEffectContainer. No system glass button style underneath.
- Bottom navigation has direct menu actions, never a nested page/tool Picker menu. Labels stay available to accessibility and tooltips.
- Activity cells are fixed 7 pt squares (1.5 pt corners) with 3 pt gaps; the horizontal viewport stays 104 pt high, including month-only labels; horizontal scroll indicators stay hidden. Wider windows reveal more history.
- Trend bars are fixed 5 pt capsules with approximately 7 pt date slots. Wider viewports reveal more dates, without stretching bars.
- Keep explanatory prose out of the main statistics sections; retain genuine error, missing-data and offline states.

- All three bottom actions are single-icon circles, 44×44 pt; icons are 19–20 pt. NSMenu popups keep a 10 pt gap. Page menu rows show SF Symbols; all tool menu rows, including 全部工具, are text-only. Minimum content width is 320 pt; height remains independent. Preserve zero labels on the right y-axis but do not draw a zero baseline.

- Horizontal history containers use scrollIndicators(.never); .hidden can leave legacy scrollers visible under macOS system preferences.

- Connected/valid-report status is green; expired device reports are orange. Filter unavailable or unreported sources, but preserve actual zero usage and historical cache when the Hub disconnects.

- History viewports use AppKit-owned offsets and explicit content widths. Reset to the latest end on entry/source changes and late initial data; do not write SwiftUI scroll-position state for each viewport-width change. Manual history browsing must not be reset by live updates.

- Home sections (usage, rate, quota, devices, models, activity, trends) have persisted visibility and ordering in preferences schema 3. Upgrade keeps the previous layout, with devices initially hidden. Every section has a detail destination.
- Theme colors support the native ColorPicker and persisted custom sRGB components, with system as the default. Explicit green/orange connection/report states must remain semantic colors.

- Home ordering uses right-hand drag handles and native drag/drop; retain accessibility move actions and persist order/visibility independently.
- Cache history projections by snapshot/tool/calendar day. Trend bars use a single Canvas path with native AXChartDescriptor support; do not reintroduce thousands of independently laid-out marks during resize.

- General development notes and performance verification principles: [README.md — 开发须知](README.md#开发须知).
