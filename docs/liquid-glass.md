# Liquid Glass 实现笔记

本文记录本项目采用 iOS 26 Liquid Glass 时的判断规则，避免后续修改把半透明背景、blur、material 或自绘胶囊误当成原生液态玻璃。

当前结论以 2026-06-08 读取的 Apple Developer 文档、`apple-doc-mcp`、Apple Landmarks 示例和 Han1meViewer-iOS 源码为准。

## 官方参考

- Apple Technology Overview: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Apple Technology Overview - Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- SwiftUI: Applying Liquid Glass to custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- SwiftUI `Picker`: https://developer.apple.com/documentation/swiftui/picker
- SwiftUI `SegmentedPickerStyle`: https://developer.apple.com/documentation/swiftui/segmentedpickerstyle
- SwiftUI `GlassEffectContainer`: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- SwiftUI `glassEffect(_:in:)`: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- SwiftUI `Glass.interactive(_:)`: https://developer.apple.com/documentation/swiftui/glass/interactive(_:)
- SwiftUI `glassEffectID(_:in:)`: https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
- SwiftUI `glassEffectUnion(id:namespace:)`: https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)
- SwiftUI `GlassButtonStyle`: https://developer.apple.com/documentation/swiftui/glassbuttonstyle
- SwiftUI `GlassProminentButtonStyle`: https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle

## Apple Doc MCP 读取记录

本轮使用 `apple-doc-mcp-server` 1.9.6，选择技术为 SwiftUI。MCP 核对到的 API 信息：

- `Picker`：iOS 13.0+，用于从互斥值集合里选择一个值。
- `SegmentedPickerStyle`：iOS 13.0+，把 `Picker` 展示为 segmented control。
- `GlassEffectContainer`：iOS 26.0+，把多个 Liquid Glass shape 组合成一个可互相 morph 的形状集合。
- `glassEffect(_:in:)`：iOS 26.0+，给自定义 SwiftUI view 应用 Liquid Glass。
- `Glass.interactive(_:)`：iOS 26.0+，把 `Glass` 配置成可交互版本。
- `glassEffectID(_:in:)`：iOS 26.0+，给 view 内的 Liquid Glass effect 关联 identity，用于过渡和 morph。
- `glassEffectUnion(id:namespace:)`：iOS 26.0+，把 view 内的 Liquid Glass effects 关联到同一个 union。
- `GlassButtonStyle` / `GlassProminentButtonStyle`：iOS 26.0+，让 Button 使用系统 glass button artwork。

这组 API 的边界很清楚：标准控件优先交给系统；只有标准控件不能表达目标交互时，才进入自定义 `glassEffect` 路线。

## 官方设计结论

采用 Liquid Glass 不等于重画整个 app。官方建议先用最新 Xcode 和最新 SDK 构建，再在最新系统上观察标准 SwiftUI/UIKit/AppKit 组件自动获得的新外观。

对本项目最重要的约束：

- 能用标准控件时优先用标准控件。系统控件会在 iOS 26 自动获得 Liquid Glass 外观、交互和辅助功能适配。
- Liquid Glass 主要服务 controls、navigation、tab bars、toolbars 等功能层；它应该浮在内容上方，而不是把内容区也刷成一片玻璃。
- 减少自定义 controls/navigation 背景。自绘背景、blur、stroke、半透明色块容易遮挡系统 Liquid Glass。
- 自定义 Liquid Glass 要克制。过多 glass 会分散注意力，也会影响内容可读性和性能。
- 自定义 view 需要 glass 时，使用 `glassEffect(_:in:)`；多个 glass view 同屏时，使用 `GlassEffectContainer(spacing:)`。
- 可交互的自定义 glass surface 使用 `.interactive()`；普通 Button 优先使用 `.buttonStyle(.glass)` 或 `.buttonStyle(.glassProminent)`。
- `glassEffectID` 用于 view hierarchy 里 glass effect 出现、消失、互相 morph 的场景；不要为了普通拖动或普通状态切换滥用。
- `glassEffectUnion` 用于把多个 view 的 Liquid Glass effects 关联到同一个 union；只有确实需要合并几何时才用。
- 控件颜色要克制，优先系统色。不要为了让玻璃“明显”而加入粉色、紫色、渐变、光晕、bokeh 或额外背景图层。
- 需要测试不同系统设置，包括降低透明度、减少动态效果和高对比。标准控件会更自然地跟随系统设置，自定义控件必须额外验证。

## 参考项目结论

### Apple Landmarks

参考目录：

`/Users/kogeki/dev/LandmarksBuildingAnAppWithLiquidGlass/Landmarks`

本地 codegraph 索引必须建在上面的 `Landmarks` 目录，不要建在外层目录。

`Landmarks/Views/Badges/BadgesView.swift` 是本项目自定义 Liquid Glass 的主要参照：

1. owning view 声明 `@Namespace`。
2. 相关 glass 元素放进 `GlassEffectContainer(spacing:)`。
3. 自定义 badge 使用 `.glassEffect(.regular, in: .rect(cornerRadius: ...))`。
4. 展开/收起 Button 使用 `.buttonStyle(.glass)`。
5. 需要随展开/收起过渡的 glass 元素使用稳定的 `.glassEffectID(..., in: namespace)`。
6. 文本、图标和内容是 glass 元素的前景内容；不要把 glass 当成外部背景贴片。

判断标准：如果某个 iOS 26 UI 只是 `Capsule().fill(Color.opacity(...))`、`.background(.ultraThinMaterial)`、blur、stroke、overlay 的组合，它只能算 fallback 或装饰，不能称为原生 Liquid Glass。

### Han1meViewer-iOS

参考目录：

`/Users/kogeki/dev/Han1meViewer-iOS`

本轮已为该目录建立 codegraph 索引。源码没有搜索到 `glassEffect` 直接用法，主要依赖系统 `TabView`、navigation、toolbar visibility 等 SwiftUI 原生结构。对本项目的借鉴点不是“抄一段自定义 glass”，而是：

- 优先使用系统导航和系统控件承载平台外观。
- 不要为了追求 Liquid Glass 手感而把系统控件替换成自绘控件。
- 需要隐藏/显示系统 tab bar 或 toolbar 时，优先用 SwiftUI 的系统 visibility/navigation API，而不是覆盖一层自绘背景。

## 本项目规则

- iOS 26+：标准控件优先。`Picker(...).pickerStyle(.segmented)` 是有效路线，尤其适用于普通互斥选择。
- iOS 26+：如果标准控件已满足视觉和交互，不要为了“源码里能看到 glassEffect”而强行自绘。
- iOS 26+：只有标准控件不能满足交互时，才做自定义 Liquid Glass。自定义实现必须能在源码里直接看到 `glassEffect`、`GlassEffectContainer` 或 glass button style。
- iOS 26+：自定义 glass 分支禁止用 `.background(.ultraThinMaterial)`、半透明 `Color`、blur、stroke/overlay 组合冒充 Liquid Glass。
- iOS 17 fallback：可以使用 `.ultraThinMaterial`、半透明色、stroke 等旧 material 写法，但必须通过 `#available(iOS 26.0, *)` 与 iOS 26 分支分开。
- 不要在没有用户确认的情况下把系统 segmented `Picker` 改成自绘 segmented control；反过来也一样，不要在用户明确需要按住拖动 glass thumb 时偷换成普通 Picker。
- 任何 Liquid Glass UI 修改前，先用 codegraph 查看当前项目相关控件，再查看 Apple Landmarks 示例。不要凭截图或记忆改。
- 修改后必须更新本文档，写清楚采用的是“系统控件路线”还是“自定义 glassEffect 路线”。

## 当前 Debug 四按钮实现

`MaimaiPOV/UI/DebugOverlayView.swift` 里定义了 `DraggableGlassSegmentedControl`。这个名字保留自 iOS 17 fallback，但当前 iOS 26 分支不是自绘 glass thumb。

当前状态已经按用户要求回退到 `c91dfdf` 并经 iOS 26 模拟器截图确认。

- iOS 26+：使用 `nativeSegmentedPicker()`。
- `nativeSegmentedPicker()` 使用 `Picker("", selection:)`、`.labelsHidden()`、`.pickerStyle(.segmented)`、`.tint(accent)`、`.controlSize(.small)`。
- 这条路径依赖系统 segmented control 在 iOS 26 的原生 Liquid Glass 外观和系统交互。它不需要手写 `.glassEffect(...)`，也不应该因为源码里没有 `glassEffect` 就被判定为“假玻璃”。
- iOS 17：使用 `fallbackSegmentedControl`，保留自定义 capsule/material/drag gesture 体验。它是旧系统 fallback，不是原生 Liquid Glass。
- 当前 iOS 26 Debug 四按钮不是“按住拖动 thumb 跟随手指”的自定义 glass 控件。用户在 2026-06-08 已确认 `c91dfdf` 的系统 segmented 版本视觉没问题，所以后续 AI 不得再擅自把它改回自定义 glassEffect 版本。

如果未来用户再次明确要求 iOS 26 也支持“按住拖动时 glass thumb 跟手”，必须重新做一个专门设计，而不是临时拼 UI。那条路线应参考 Landmarks：

1. `GlassEffectContainer(spacing:)` 包住 track/thumb。
2. track/thumb 自身直接使用 `.glassEffect(...)`，可交互 thumb 使用 `.interactive()`。
3. 需要 hierarchy transition 时再用 `@Namespace` + `glassEffectID`。
4. 需要合并多个 glass geometry 时再用 `glassEffectUnion`。
5. 完成后必须在 iOS 26 模拟器里验证按住拖动的视觉跟手，并更新本文档。

## 禁止修改

后续 AI 或开发者修改 Liquid Glass 时必须遵守下面的硬约束：

- 禁止把 iOS 26 标准控件替换成自绘半透明胶囊，只为了让源码里出现 `glassEffect`。
- 禁止在 iOS 26 自定义 glass 分支用 `.ultraThinMaterial`、blur、半透明 `Color`、stroke/overlay 冒充 Liquid Glass。
- 禁止为 Debug 四按钮添加粉色、紫色、渐变、光晕、bokeh 或额外背景图层。
- 禁止随手改 Debug 四按钮尺寸、间距或 tint。当前经用户确认的版本是 `.frame(width: 228, height: 34)` 附近的系统 segmented 外观。
- 禁止把 iOS 17 fallback 的 material 写法复制到 iOS 26 分支后声称是真 Liquid Glass。
- 禁止凭记忆改 Landmarks 参考。必须用 codegraph 或文件读取核对 `BadgesView.swift`。
- 禁止在没有截图或模拟器验证的情况下声称 UI 已经对齐。

## 验证要求

提交前至少验证：

- `git diff --check` 无输出。
- iOS 26 build 成功。
- iOS 17 build 成功。
- iOS 26 展开/收起调试面板。
- iOS 26 调试分段四个选项 `推流`、`YOLO`、`跟踪`、`日志` 都能点击切换。
- iOS 26 展开调试面板后，切换底部 app tab，再收起调试面板。
- iOS 26 展开调试面板后，收起控制面板，再收起调试面板。
- iOS 17 重复上面的基础交互；iOS 17 不要求原生 Liquid Glass，只要求 fallback 布局和交互正常。
- 如果修改了自定义 Liquid Glass 控件，还要验证降低透明度、减少动态效果、高对比下没有明显遮挡或不可读。
