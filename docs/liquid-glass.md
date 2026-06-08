# Liquid Glass 实现笔记

本文记录本项目采用 iOS 26 Liquid Glass 时的判断规则，避免把半透明背景、blur 或 material 误当成原生液态玻璃。

## 官方结论

参考：

- Apple Technology Overview: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- SwiftUI: Applying Liquid Glass to custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- SwiftUI `GlassEffectContainer`: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- SwiftUI `glassEffect(_:in:)`: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

要点：

- 优先使用 SwiftUI/UIKit/AppKit 的标准控件。系统组件会在最新系统上自动采用 Liquid Glass 的外观和交互。
- 减少 controls、navigation、tab bars、toolbars 等区域的自定义背景；自定义背景容易遮挡或干扰系统 Liquid Glass。
- 自定义 view 需要 Liquid Glass 时，使用 `glassEffect(_:in:)`。它会把 Liquid Glass 材料锚定在 view bounds 后方，并叠加前景效果。
- 可交互的自定义 glass view 需要使用 `.interactive()`，获得与 `.buttonStyle(.glass)` 类似的触摸/指针响应。
- 多个 glass view 同屏出现时，放进 `GlassEffectContainer`，让系统统一渲染、合成、融合和 morph。
- `glassEffectID` 和 `glassEffectUnion` 只用于 glass view 的过渡、合并或形变；它们不能把自绘 material 变成原生 Liquid Glass。

## Apple Landmarks 示例

参考项目：

`/Users/kogeki/dev/LandmarksBuildingAnAppWithLiquidGlass/Landmarks`

本地 codegraph 索引必须建在上面的 `Landmarks` 目录，不要建在外层目录。

示例里的关键模式：

- `BadgesView` 使用 `GlassEffectContainer(spacing:)` 包裹多个 glass 元素。
- 普通徽章使用 `.glassEffect(.regular, in: .rect(cornerRadius: ...))`。
- 展开/收起按钮使用 `.buttonStyle(.glass)`。
- 需要过渡动画的 glass 元素使用 `.glassEffectID(..., in: namespace)`。

## 本项目规则

- iOS 26+：能用标准控件就用标准控件。例如分段切换优先使用 `Picker` + `.pickerStyle(.segmented)`，不要自己画胶囊背景。
- iOS 26+：自定义 glass 只用于没有合适标准控件的 surface/chip/button，并且必须是 `glassEffect` 或 `.buttonStyle(.glass/.glassProminent)`。
- iOS 26+：不要用 `.background(.ultraThinMaterial)`、半透明 `Color`、blur、stroke 组合冒充 Liquid Glass。
- iOS 17 fallback：可以继续用 `.ultraThinMaterial` 等旧 material，但必须通过 `#available(iOS 26.0, *)` 与原生 Liquid Glass 分支分开。
- 做交互验证时，至少检查：
  - 展开/收起调试面板。
  - 调试分段四个选项都能点击切换。
  - 调试面板展开后，切换底部 tab，再收起调试面板。
  - 调试面板展开后，收起控制面板，再收起调试面板。
  - iOS 26 和 iOS 17 都要跑一遍。

## 当前调试分段实现

`MaimaiPOV/UI/DebugOverlayView.swift` 中的调试分段：

- iOS 26+ 使用系统 `Picker("", selection:)` + `.pickerStyle(.segmented)`，让系统提供原生 Liquid Glass 分段外观和交互。
- iOS 17 使用旧的自定义 fallback，保留可拖动选择体验和 material 背景。

