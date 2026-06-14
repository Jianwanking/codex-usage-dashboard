# PROJECT_NOTES

## Project Overview

- 项目名称：`CodexQuotaDesktop`
- 目标：在 macOS 上提供一个原生宿主 App + Widget，展示 Codex `5 小时` 与 `1 周` 的剩余额度。
- 当前仓库同时包含：
  - 共享 Swift 核心代码：`Sources/CodexQuotaWidget`
  - 可执行验证靶子：`CodexQuotaWidgetVerification`
  - 宿主 App 源码：`App`
  - Widget 源码：`Widget`
  - Xcode 工程生成脚本：`scripts/generate_xcodeproj.rb`

## Start / Build

- 共享核心验证：
  - `swift run CodexQuotaWidgetVerification`
- 重新生成 Xcode 工程：
  - `ruby scripts/generate_xcodeproj.rb`
- 打开项目：
  - `open CodexQuotaDesktop.xcodeproj`

## Data Source

- 本地数据来源已验证为：
  - `~/.codex/sqlite/state_5.sqlite`
  - `threads.rollout_path`
  - rollout `jsonl` 中 `type == "event_msg"` 且 `payload.type == "token_count"` 的最后一条事件
  - `payload.rate_limits.primary.used_percent`
  - `payload.rate_limits.primary.resets_at`
  - `payload.rate_limits.secondary.used_percent`
  - `payload.rate_limits.secondary.resets_at`
- 映射规则：
  - `window_minutes == 300` -> `5 小时`
  - `window_minutes == 10080` -> `1 周`
  - 剩余百分比 = `100 - used_percent`

## Notes

- Widget 不直接读取 `~/.codex`，由宿主 App 读取本地状态后，把快照写到 App Group 共享 JSON。
- App Group 常量目前写在共享代码里：
  - `group.com.ck.codexquota`
- 共享快照文件名：
  - `quota-snapshot.json`

## Issues

Issue: 当前机器只有 Command Line Tools，没有完整 Xcode，也没有内置 Apple 测试运行时。  
Cause: `xcodebuild` 不能正常用于 App/Widget 构建，`swift test` 环境里也缺少 `Testing` / `XCTest`。  
Solution: 用 Swift Package 承载共享核心，并额外提供一个可执行验证靶子 `CodexQuotaWidgetVerification`；原生工程通过 Ruby `xcodeproj` 脚本生成。  
Verification: `swift run CodexQuotaWidgetVerification` 可以在当前环境通过；`ruby scripts/generate_xcodeproj.rb` 可生成 `CodexQuotaDesktop.xcodeproj`。  
Avoid next time: 如果要直接编译和运行 Widget UI，先安装完整 Xcode；在只有 CLT 的机器上，优先验证共享核心和工程生成脚本。

Issue: Codex 额度字段不在单独 API 中，而是在本地 rollout `jsonl` 的事件流里。  
Cause: CLI 本地状态把额度信息作为 `token_count` 事件的一部分写入会话文件，而不是写进一个单独配置文件。  
Solution: 先从 `state_5.sqlite` 找最新非归档线程的 `rollout_path`，再倒序读取对应 `jsonl` 中最后一条有效 `token_count`。  
Verification: 当前机器上已实际读到 `300` 分钟和 `10080` 分钟窗口，以及对应 `used_percent` 和 `resets_at`。  
Avoid next time: 不要先猜测固定 JSON 文件位置；优先查 `threads.rollout_path` 再追到具体 rollout 文件。

Issue: 生成原生 Xcode 工程时，本机没有 `xcodegen`。  
Cause: 仓库从零开始，环境中也没有预装项目生成器。  
Solution: 安装 Ruby `xcodeproj` gem，并通过 `scripts/generate_xcodeproj.rb` 稳定生成 `.xcodeproj`。  
Verification: 运行脚本后已生成 `CodexQuotaDesktop.xcodeproj/project.pbxproj`。  
Avoid next time: 空仓开始做 Apple 平台项目时，尽早确认是否有 `xcodegen` / `tuist`；没有就尽快固定一种可重现的生成方式。

Issue: 需要确认宿主 App 是否真的跑起来并把额度快照写给 Widget。  
Cause: 仅有编译通过并不能证明运行链路成立，尤其是 App Group / 共享 JSON 这类运行时行为。  
Solution: 安装完整 Xcode 后，用 `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 编译，再直接启动构建产物；随后检查 `~/Library/Group Containers/group.com.ck.codexquota/quota-snapshot.json`。  
Verification: 宿主 App 已成功启动，进程名为 `CodexQuotaDesktop`；共享快照已实际写入 `~/Library/Group Containers/group.com.ck.codexquota/quota-snapshot.json`，内容包含 `fiveHourRemainingPercent`、`weekRemainingPercent`、`planType` 和 `sourceRolloutPath`。  
Avoid next time: 对 Widget 类项目，始终把“构建成功”和“运行后产物落盘/共享”分开验证，不要只停留在 `BUILD SUCCEEDED`。

Issue: Widget 编译通过、App 也能启动，但在 macOS Widget 列表里完全搜不到。  
Cause: 扩展最初没有 `com.apple.security.app-sandbox`，`pkd` 会直接拒绝注册这类 Widget 扩展；日志里会出现 `rejecting; Ignoring mis-configured plugin ... plug-ins must be sandboxed`。  
Solution: 给 `Widget/CodexQuotaDesktopWidget.entitlements` 增加 `com.apple.security.app-sandbox = true`，并使用已登录的 Xcode Apple 账号对应 Team `G9K4MNXX8G` 做正式开发签名；随后安装签名后的 App 到 `/Applications` 并用 `pluginkit -a` 重新注册扩展。  
Verification: `pluginkit -m -A -D -p com.apple.widgetkit-extension` 现在能看到 `com.ck.CodexQuotaDesktop.widget(1.0)`；签名版宿主 App 启动后，`~/Library/Group Containers/group.com.ck.codexquota/quota-snapshot.json` 仍会刷新。  
Avoid next time: 如果 Widget “能编译但搜不到”，先查 `pluginkit` 和 `log show`，不要先怀疑搜索框或 Xcode 缓存；macOS 上 Widget 扩展没开 sandbox 会被系统静默忽略。

Issue: 宿主 App 能显示实时额度，但桌面 Widget 一直显示 `暂无数据`。  
Cause: Widget 扩展虽然能解析到 App Group 路径，但实际读取 `~/Library/Group Containers/group.com.ck.codexquota/quota-snapshot.json` 时会报“没有查看权限”；宿主 App 是非 sandbox 的，本地直读 `~/.codex` 没问题，但 Widget 的 sandbox 不能稳定消费这份由宿主写入的 App Group 文件。  
Solution: 保留 App Group 作为第一读取路径，同时让宿主 App 额外把同一份快照写进 Widget 自己容器内的 fallback 路径：`~/Library/Containers/com.ck.CodexQuotaDesktop.widget/Data/Library/Application Support/CodexQuotaDesktop/quota-snapshot.json`。Widget 先尝试 App Group，失败后自动回退到自己容器内的同名快照。  
Verification: 宿主 App 刷新后，Widget 容器内的 fallback JSON 会跟着更新；Widget 日志已验证在 App Group 继续报权限错误时，fallback 可以成功读取并得到 `state: ok`。  
Avoid next time: 对“非 sandbox 宿主 App + sandbox Widget 扩展”这种组合，不要假设 App Group 文件一定能双向读通；优先给 Widget 预留自己容器内的可读 fallback 快照。

Issue: 宿主 App 需要持续刷新本地 Codex 文件，但常规窗口 App 会一直占着 Dock，用户关闭窗口后又缺少安全的后台入口。  
Cause: 当前刷新链路依赖宿主进程常驻；如果只是普通 macOS App，虽然关窗口后进程还在，但 Dock 图标会一直存在；如果直接隐藏 Dock 图标又不提供入口，后续就很难再手动显示窗口或退出。  
Solution: 宿主在启动时切到 `.accessory` 激活策略，隐藏 Dock 图标；同时增加一个极简 `MenuBarExtra`，提供 `显示窗口 / 手动刷新 / 退出`。  
Verification: 关闭主窗口后进程仍可继续后台刷新；Dock 不再显示宿主图标；菜单栏入口仍可重新打开窗口并退出应用。  
Avoid next time: 只要 Widget 刷新链路依赖宿主常驻，就不要做成“纯隐藏无入口”的后台进程，至少保留一个菜单栏控制点。

Issue: Widget 背景容易因为壁纸不同而显得过黑，而且用户希望只调背景，不影响圈本身。  
Cause: 背景颜色和透明度原先写死在 Widget 视图里，且与圆环样式没有分离。  
Solution: 给共享快照增加独立的背景字段：`widgetBackgroundOpacity`、`widgetBackgroundStyle`、`widgetBackgroundColor`；宿主 App 增加“背景设置”面板，只提供透明度滑杆、默认颜色按钮和自定义颜色选择器；Widget 只读取这些字段来渲染外层卡片背景，不改圈的透明度和颜色。  
Verification: 拖动滑杆或切换到自定义颜色后，宿主预览与桌面 Widget 的背景会同步变化，而圆环外观保持不变。  
Avoid next time: 对有明显视觉偏好的 Widget，背景层和数据图层要分开控制，不要把二者绑在同一套透明度参数里。

Issue: 即使把自绘背景透明度拖到很低，桌面 Widget 也不会真实露出壁纸，低透明度下反而容易发黑。  
Cause: macOS 桌面 Widget 的背景并不是普通 App 视图那种可自由穿透桌面的 alpha 合成层；系统会按 Widget 上下文接管背景，呈现 clear / translucent / glass 一类材质效果，而不是真实“打洞透壁纸”。  
Solution: 改回系统主导的原生桌面玻璃样式：Widget 配置加 `containerBackgroundRemovable(true)`，Widget 视图背景改成 `Color.clear`，不再在 Widget 上暴露自定义背景色和透明度控制。  
Verification: Widget 会使用 macOS 自己的桌面背景表现；宿主说明文案也同步改成“系统接管背景呈现”。  
Avoid next time: 如果用户要的是“真实露出壁纸”，先说明 WidgetKit 做不到，不要先在自绘背景透明度上反复调参。

Issue: macOS 小组件样式设为透明后，背景会更像玻璃，但 SwiftUI 形状绘制的彩色圆环会被系统渲染模式去色。  
Cause: 透明/强调类 Widget 外观会进入 `WidgetRenderingMode.vibrant` 或 `accented` 一类系统渲染模式；本机 SDK 公开的 `.widgetAccentedRenderingMode(.fullColor)` 主要挂在 `Image` 上，不能直接稳定作用在 `Capsule` / `Shape` 组成的圆环视图上。  
Solution: 将 Widget 内的分段圆环从 SwiftUI `Capsule` 形状改为用 `NSImage` / CoreGraphics 预渲染，然后对 `Image(nsImage:)` 在 macOS 15+ 应用 `.widgetAccentedRenderingMode(.fullColor)`，尝试在透明背景下保留红黄绿圆环。  
Verification: `swift run CodexQuotaWidgetVerification` 与 Release `xcodebuild` 均通过；实际视觉需要在系统“小组件样式 = 透明”下观察圆环是否仍保留全彩。  
Avoid next time: 想在透明/强调 Widget 外观下保留复杂自绘彩色内容时，优先考虑把彩色内容栅格化成 Image，再标记 fullColor。

Issue: 中号 Widget 需要同时展示双额度圆环和刷新窗口进度，空间很紧。
Cause: 原先 `118pt` 圆环加圈外标签几乎占满高度，无法再放两条时间进度条；如果把条形进度也用 SwiftUI 彩色形状绘制，还可能在透明小组件样式下被系统去色。
Solution: 将圆环缩到 `92pt`，把“5小时 / 1周”移回圈内第二行，底部新增两条 `NSImage` / CoreGraphics 预渲染的分段时间条：左侧显示当前时间/日期，右侧显示刷新时间/日期，条形填充按剩余窗口时间从红到绿显示。
Verification: `swift run CodexQuotaWidgetVerification` 通过；`xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过。
Avoid next time: 中号 Widget 加信息密度时，先缩减已有 UI 的外部标签，再新增底部信息；彩色分段内容继续走预渲染 Image，避免透明模式下丢色。

Issue: 底部双时间条在中号 Widget 上可读性不足。
Cause: 中号 Widget 高度有限，双圆环下方再放两行标签和条形进度会迫使时间文字和分段条过小，实际桌面观看不够清楚。
Solution: 移除底部时间条，恢复较大的单行双圆布局；每个额度圈内部增加一条灰色分段时间环，和外圈使用同一套 CoreGraphics 分段绘制逻辑，外圈表示额度剩余，内圈表示当前刷新窗口剩余时间。
Verification: `swift run CodexQuotaWidgetVerification` 通过；`xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过。
Avoid next time: 中号 Widget 上不要把关键时间信息挤到额外小字行里；如果需要展示第二个进度维度，优先复用圆环内部空间，而不是继续增加底部行。

Issue: 双环版功能正确但视觉比例偏散、偏粗糙。
Cause: `34` 段和 `116pt` 圆环在中号 Widget 中显得块大且稀，内外圈间距和标题尺寸也不够接近参考仪表盘模板。
Solution: 将圆环调整为 `122pt`、`40` 段，收紧垂直 padding，略增左右间距和中心百分比/底部标题字号，同时缩短每个分段长度，让内外圈更像同一套仪表盘语言。
Verification: `swift run CodexQuotaWidgetVerification` 通过；`xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过。
Avoid next time: 双环视觉优先调整体比例、段数和内外圈间距，不要只调字体；中号 Widget 里 `122pt` 左右是当前更平衡的圆环尺寸。

Issue: 圆环段块看起来像圆点或胶囊，不够硬朗。
Cause: CoreGraphics 分段块使用 `cornerWidth = lineWidth / 2`，圆角半径等于半个块高时会把小段块视觉上圆化。
Solution: 将分段绘制参数改成明确的 `blockSize` 和 `blockRadius`：外圈 `6/2`，内圈 `4.5/1.5`，让每段成为带小圆角的方块。
Verification: `swift run CodexQuotaWidgetVerification` 通过；`xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过。
Avoid next time: 仪表盘风格段块不要用尺寸派生的满圆角；圆角应作为独立视觉参数维护。
