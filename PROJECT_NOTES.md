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
- rollout `jsonl` 中 `type == "event_msg"` 且 `payload.type == "token_count"` 的事件
- 优先取 `payload.rate_limits.limit_id == "codex"` 的最后一条总额度事件；如果没有该字段，再回退到最后一条有效 `token_count`
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
Solution: 先从 `state_5.sqlite` 找最新非归档线程的 `rollout_path`，再读取对应 `jsonl` 中的 `token_count`；升级套餐后要优先取最后一条 `rate_limits.limit_id == "codex"` 的总额度事件，缺少 `limit_id` 时才回退到最后一条有效 `token_count`。  
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
Verification: `swift run CodexQuotaWidgetVerification` 通过；Debug `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过；Release `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Release build` 通过，并已覆盖安装到 `/Applications/CodexQuotaDesktop.app`。
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

Issue: 双环 Widget 固定 `344x164` 画布后，真实桌面 Widget 里的圆环显得太小。
Cause: 参考图坐标适合表达视觉方向，但直接作为固定设计画布会把原先更舒展的 `122pt` 圆环缩到 `104pt` 左右，桌面实际效果不够撑开。
Solution: 改用 `GeometryReader` 按实际 Widget 尺寸计算比例布局：左右圆心分别取宽度 `30%/70%`，圆环尺寸取 `min(width * 0.39, height * 0.82, 136)`；内外圈统一 `36` 段，外圈半径约 `ringSize * 0.455`、内圈半径约 `ringSize * 0.36`，并给百分比文字固定安全框和轻微缩放。
Verification: `swift run CodexQuotaWidgetVerification` 通过；Debug `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过；Release `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Release build` 通过，并已覆盖安装到 `/Applications/CodexQuotaDesktop.app`。
Avoid next time: 参考图参数只能作为视觉基准；Widget 真实布局优先用实际容器比例适配，再用截图微调观感。

Issue: 中号 Widget 的双环在桌面标签内仍偏小、偏圆，不够撑满。
Cause: 后续用 `GeometryReader + position` 绝对定位圆心和底部标题，圆环按整块高度放大，但标题不参与布局；这和最早版本 `HStack + VStack` 的自然排版不同，容易出现圆环和底部标题互相挤压、整体分布不稳。
Solution: 恢复最早版本的布局骨架：外层 `HStack` 均分左右仪表盘，每个仪表盘内部用 `VStack` 把圆环和底部标题作为一个整体排版；圆环尺寸按真实可用高度扣除标题高度后计算，同时保留 `30` 段双环和外圈 `6.4/1.2`、内圈 `4.8/0.9` 的硬朗方块参数。宿主 App 预览同步为同语义的 30 段双环，避免预览与桌面实际样式脱节。
Verification: `swift run CodexQuotaWidgetVerification` 通过；Debug `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet` 通过。
Avoid next time: 中号 Widget 视觉微调优先保留“圆环 + 底部标题”整体参与布局的结构；需要撑满时先按实际可用内容区分配高度，不要先回到绝对坐标。

Issue: 中号桌面 Widget 实际截图仍有很大的上下留白。
Cause: WidgetKit 会给 Widget 内容默认套 `widgetContentMargins`；在 `344x164` 中号尺寸下，如果默认边距约为 `24pt`，视图实际高度会被压到约 `116pt`，按当前公式圆环只能算到约 `96pt`，正好对应截图里“小圈 + 大留白”的观感。Debug build 也不会自动更新 `/Applications` 里桌面正在注册使用的 Release App/Widget。
Solution: 在 `CodexQuotaWidget` 配置链上增加 `.contentMarginsDisabled()`，让 Widget 内容拿到完整尺寸；继续保留 `HStack + VStack` 的整体排版，让“圆环 + 底部标题”一起撑满高度。完成后需要 Release build 并覆盖安装 `/Applications/CodexQuotaDesktop.app`，否则桌面仍可能显示旧 appex。
Verification: `swift run CodexQuotaWidgetVerification` 通过；Debug `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet` 通过；Release `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Release build` 通过；已用 Release 产物覆盖安装到 `/Applications/CodexQuotaDesktop.app`，并重新注册 Widget 扩展、重启宿主 App。
Avoid next time: 桌面 Widget 出现无法解释的大边距时，先检查 `.contentMarginsDisabled()` 和实际安装的 appex 时间戳，再调整内部排版参数。

Issue: 禁用系统 content margins 后，中号 Widget 又显得过满、上下贴边。
Cause: `.contentMarginsDisabled()` 让内容拿到完整 `344x164` 后，之前的尺寸公式会把“圆环 + 底部标题”总高度算到刚好 `164pt`，等于内部 0 留白；同时 `30` 段放在大圆上弧距过大，方块间隙比方块本身更显眼，圆环节奏不稳。
Solution: 保留 `.contentMarginsDisabled()`，但在 Widget 内部主动留约 `6pt` 上下视觉边距；圆环尺寸上限收回到约 `136pt`，底部标题约 `16pt`，段数改为 `36`，外圈方块 `7.0/1.2`、内圈方块 `5.2/0.9`，让大圆更密、更稳但不贴边。
Verification: `swift run CodexQuotaWidgetVerification` 通过；Debug `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet` 通过；Release `xcodebuild -project CodexQuotaDesktop.xcodeproj -scheme CodexQuotaDesktop -configuration Release build -quiet` 通过；已用 Release 产物覆盖 `/Applications/CodexQuotaDesktop.app`，并重新注册 Widget 扩展、重启宿主 App。
Avoid next time: 先区分“系统边距”和“内部视觉留白”；禁用系统边距后仍要保留少量主动留白，不要把几何可用高度全部吃满。

Issue: 底部标题和圆环的几何距离一致，但 `1周` 视觉上仍显得比 `5小时` 更远。
Cause: 中文字形的视觉中心和 SwiftUI `Text` 的 frame/baseline 中心不完全重合；即使几何间距相同，短标签 `1周` 也会更容易显得“坠”一点。
Solution: 保持标题高度和整体布局不变，只把底部标题整体上移约 `1pt`，用光学修正收紧圆环与标题的关系，同时给底边留出更多呼吸空间。
Verification: 需要重新看桌面 Widget 和宿主预览，确认 `5小时 / 1周` 与圆环的距离更协调，底部不再显得下坠。
Avoid next time: 遇到短标签和长标签混排时，不要只看几何值；必要时用 `1pt` 级别的 optical offset 做微调。

Issue: 36 段布局稳定了，但当前格子仍偏小、内圈偏内收。
Cause: 在 `36` 段和 `136pt` 圆尺寸下，外圈 `7.0` / 内圈 `5.2` 的方块仍显得略细，内圈半径 `0.355` 让灰环离外圈稍远，整体偏散。
Solution: 保持整体圆位置、外圈半径和最大尺寸不变，只增大格子并把内圈向外提：外圈改为 `8.0/1.8`，内圈改为 `5.6/1.3`，内圈半径改为 `ringSize * 0.385`；字号同步固定为百分比 `30`、刷新时间 `12.5`、底部标题 `14`。
Verification: 需要重新跑 `swift run CodexQuotaWidgetVerification`、Debug/Release `xcodebuild`，并覆盖安装 `/Applications/CodexQuotaDesktop.app` 后实看段块密度和内外圈关系。
Avoid next time: 如果用户已经明确给了局部参数实验方案，先只动那一组参数，不要同时改整体几何和布局骨架。

Issue: 上一版没有严格按图中的精确半径收口，内外圈可见间距仍偏小。
Cause: 虽然方块尺寸已经切到外圈 `8.0`、内圈 `5.6`，但半径仍沿用了比例值 `outerRadius = ringSize * 0.458`、`innerRadius = ringSize * 0.385`，没有严格落到目标的 `61.788 / 49.0`。
Solution: 按精确参数改成 `segments = 36`、`outerBlock = 8.0`、`outerCorner = 1.8`、`outerRadius = 61.788`、`innerBlock = 5.6`、`innerCorner = 1.3`、`innerRadius = 49.0`；宿主预览按 `136` 基准做等比缩放，确保桌面和预览一致。
Verification: `swift run CodexQuotaWidgetVerification` 通过；Debug/Release `xcodebuild` 通过；已覆盖安装 `/Applications/CodexQuotaDesktop.app`，并重新注册 Widget 扩展、重启宿主 App。
Avoid next time: 当用户直接给出绝对半径时，不要再把它换回比例理解；优先按绝对值落地，再讨论是否要做自适应。

Issue: 升级套餐后桌面 Widget 一度显示 `100/100`，但 Codex UI 显示的是另一个持续变化的总额度值。
Cause: 最新 rollout 里同时存在多种额度事件：`limit_id = "codex"` 表示 UI 里的总额度，后续 `limit_id = "codex_bengalfox"` / `limit_name = "GPT-5.3-Codex-Spark"` 表示某个模型线路的单独额度。原实现无条件取最后一条 `token_count`，把后写入的模型额度 `0%/0% used` 误当成总额度，导致显示 `100/100`。
Solution: `CodexQuotaSnapshotBuilder` 解析 `rate_limits.limit_id`，在同一 rollout 中优先选择最后一条 `limit_id == "codex"` 的总额度事件；只有找不到总额度事件时才回退到最后一条有效 `token_count`。内圈刷新进度颜色改为固定蓝色 `Color(red: 0.72, green: 0.86, blue: 0.90).opacity(0.85)`，避免旧灰色被误读成禁用状态。
Verification: 新增 `testPrefersOverallCodexLimitOverLaterModelLimit`，复现“先 `codex` 总额度、后 `codex_bengalfox` 模型额度”的场景；`swift run CodexQuotaWidgetVerification` 已验证会选总额度事件，不会跳到模型额度的 `100/100`。数值本身会随使用持续变化，不应写死为某个截图百分比。
Avoid next time: 额度显示不一致时不要只看“最后一条 token_count”；先检查 `rate_limits.limit_id`，按“最新 `codex` 总额度事件 -> 宿主快照 -> Widget fallback 快照 -> 正在运行的 appex”顺序查证。
