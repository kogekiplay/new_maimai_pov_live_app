# 直播画面重构需求文档

## 一、背景与问题

### 1.1 现状

当前推流输出为 **1:2 竖屏 (720×1440)**，点歌信息以3张卡片形式通过 Metal GPU 合成叠加在游戏画面上方。卡片默认位置为画面上部横向排列，尺寸240×360像素。

### 1.2 实际直播中发现的问题

1. **画幅不合理**：1:2竖屏比例过于窄长，在直播平台上显示效果差（两侧大量黑边），且无法有效利用横向空间
2. **排队信息不足**：3张卡片完全无法满足观众点歌需求，排队情况不直观
3. **卡片布局受限**：在1:2窄屏上，卡片只能横向排列在画面顶部，严重遮挡游戏画面
4. **信息展示单一**：无法展示公告、规则等辅助信息

### 1.3 核心洞察

maimai 游戏屏幕为正圆形，游戏画面只需要一个近似方形的区域即可完整展示。改为16:9横屏后，左右两侧的空白区域天然适合放置UI信息面板。

***

## 二、目标方案

### 2.1 整体布局

将推流画面从 **1:2 竖屏** 重构为 **16:9 横屏 (1920×1080)**，采用三栏式布局：

```
┌──────────────────────────────────────────────────────────┐
│            │                          │                  │
│  左侧面板   │      中央游戏画面          │   右侧面板       │
│            │      (5:4 比例)           │  (点歌队列)      │
│  当前歌曲   │                          │                  │
│  下一首     │                          │                  │
│  公告/规则  │                          │                  │
│            │                          │                  │
└──────────────────────────────────────────────────────────┘
```

### 2.2 画面尺寸计算

| 参数     | 值          | 说明          |
| ------ | ---------- | ----------- |
| 输出画布   | 1920×1080  | 16:9 标准横屏   |
| 游戏区域   | 1350×1080  | 5:4 比例，居中放置 |
| 左侧面板   | 285×1080   | 公告+当前/下一首卡片 |
| 右侧面板   | 285×1080   | 点歌队列列表      |
| 游戏区域偏移 | X=285, Y=0 | 居中偏移        |

### 2.3 裁剪管线变更

**当前管线**：

```
防抖输出(1080×1440, 3:4) → 裁剪(720×1440, 1:2) → 叠加卡片 → 推流
```

**目标管线**：

```
防抖输出(1080×1440, 3:4) → 裁剪(1080×864, 5:4) → 缩放至(1350×1080) → 放入16:9画布中心 → 合成左右面板 → 推流
```

裁剪逻辑：

- 从防抖输出 1080×1440 中，以 YOLO 追踪中心为基准
- 裁剪宽度 = 1080（取满防抖宽度）
- 裁剪高度 = 1080 × 4/5 = 864
- 裁剪区域以追踪中心垂直居中
- 画面不变形，保持原始像素比例

***

## 三、左侧面板设计

### 3.1 布局分区

```
┌─────────────┐
│  当前歌曲卡片  │  上部 ~40% 高度
│  (大封面式)   │
├─────────────┤
│  下一首卡片   │  中部 ~30% 高度
├─────────────┤
│  公告/规则    │  下部 ~30% 高度
│             │
└─────────────┘
```

### 3.2 当前歌曲卡片

- **风格**：大封面卡片式
- **内容**：
  - 歌曲封面图（大面积展示）
  - 歌曲名称（大字突出）
  - 难度标识（颜色编码：绿/黄/红/紫/白/粉）
  - 等级（如 "14+"）
  - 谱面类型（STD/DX/UTAGE）
  - 点歌人昵称
- **状态**：切歌时有过渡动画（淡出旧卡/淡入新卡）

### 3.3 下一首卡片

- **风格**：与当前歌曲卡片风格统一但尺寸较小
- **内容**：封面缩略图 + 歌名 + 难度 + 点歌人
- **标识**：插队歌曲显示金色边框 + ⚡图标

### 3.4 公告/规则区域

- **内容**：
  - 点歌规则（固定文字，如"弹幕点歌需送礼物""SC30元插队"）
  - 自定义公告（主播可随时修改的文字）
- **样式**：简洁文字列表，支持多行滚动显示

***

## 四、右侧面板设计

### 4.1 点歌队列列表

```
┌─────────────────┐
│  🎵 点歌队列      │  标题栏
├─────────────────┤
│ [封面] 歌名  难度  │  #2 排队中
│        点歌人      │
├─────────────────┤
│ [封面] 歌名  难度  │  #3 排队中
│        点歌人      │
├─────────────────┤
│ [封面] 歌名  难度  │  #4 ⚡插队
│        点歌人      │
├─────────────────┤
│ ...               │  持续滚动
└─────────────────┘
```

- **风格**：紧凑行式列表
- **每行内容**：
  - 封面缩略图（小尺寸）
  - 歌曲名称
  - 难度标识（颜色条/标签）
  - 点歌人昵称
  - 插队标识（金色⚡图标）
- **滚动行为**：
  - 队列超出可视区域时自动滚动
  - 新歌加入时从底部滑入
  - 切歌时顶部项移出，后续项上移
- **当前播放**：列表中不包含当前播放歌曲（当前播放在左侧面板突出显示）

***

## 五、背景与视觉风格

### 5.1 背景风格

- 左右面板区域使用**纯色或渐变背景**
- 建议使用深色系（如深蓝/深紫渐变），与maimai游戏风格协调
- 面板内容使用卡片/面板样式浮在背景上，保持层次感

### 5.2 面板分隔

- 游戏区域与面板之间可使用细微的分隔线或阴影
- 避免硬边切割，保持视觉流畅

***

## 六、技术方案

### 6.1 渲染架构

**UI面板渲染**：采用 WebView 整体渲染方案

- 左侧面板和右侧面板分别用一个 WKWebView 渲染为整体 HTML 页面
- 渲染结果截图为 Metal 纹理，通过 GPU 合成到输出画布
- 优势：开发效率高、布局灵活、与现有卡片渲染方案一致
- 更新策略：队列变化时触发重新渲染，非每帧渲染

**游戏画面合成**：Metal Compute Shader

- 裁剪 shader 从防抖输出中裁剪5:4区域
- 缩放并放置到16:9画布中心
- 合成左右面板纹理

### 6.2 管线变更

```
当前管线：
Camera → Stabilizer → YOLO → Tracker → CropRenderer(1:2) → OverlayCompositor → SongCardCompositor → Output

目标管线：
Camera → Stabilizer → YOLO → Tracker → CropRenderer(5:4) → CanvasComposer(16:9画布合成) → Output
                                                              ├── 游戏画面(缩放至中心)
                                                              ├── 左侧面板纹理
                                                              └── 右侧面板纹理
```

### 6.3 关键变更点

1. **Config.swift**：outputWidth/outputHeight 从 720×1440 改为 1920×1080
2. **CropRenderer / Crop.metal**：裁剪目标从 1:2 改为 5:4
3. **BBoxTracker**：outputRatio 从 0.5 (1:2) 改为 1.25 (5:4)
4. **新增 CanvasComposer**：16:9 画布合成器，替代原 OverlayCompositor + SongCardCompositor
5. **新增 LeftPanelRenderer**：左侧面板 WebView 渲染器
6. **新增 RightPanelRenderer**：右侧面板 WebView 渲染器
7. **RTMPStreamManager**：推流分辨率适配 1920×1080
8. **IOSurfaceOutputPool**：缓冲区尺寸从 720×1440 改为 1920×1080
9. **SongCardCompositor**：移除或重构（卡片不再直接叠加在游戏画面上）

### 6.4 性能要求

- 当前裁剪管线每帧约12ms，重构后需保持同等性能
- WebView 面板渲染仅在数据变化时触发，不每帧渲染
- Metal 合成操作保持在一个 CommandBuffer 中
- 面板纹理使用缓存，无变化时不重新渲染

***

## 七、分阶段实施计划

### 阶段一：画幅改造（优先级最高）

**目标**：将推流画面从1:2竖屏改为16:9横屏，游戏画面5:4居中显示，两侧暂用深色背景填充

#### 1.1 新增文件

| 文件路径 | 说明 |
|---------|------|
| `MaimaiPOV/Canvas/CanvasComposer.swift` | 16:9画布合成器（替代CropRenderer+OverlayCompositor+SongCardCompositor） |
| `MaimaiPOV/Canvas/CanvasUniforms.swift` | 画布合成器Uniforms结构体 |
| `MaimaiPOV/Canvas/Shaders/Canvas.metal` | 画布合成Compute Shader（单Pass完成裁剪+画布合成） |

#### 1.2 修改文件清单

| 文件 | 修改内容 | 风险 |
|------|---------|------|
| `Config.swift` | outputWidth: 720→1920, outputHeight: 1440→1080, 新增gameAreaRatio=5/4 | 低 |
| `BBoxTracker.swift` | outputRatio从0.5改为1.25, 修改裁剪区域计算逻辑(需clamp) | **中** |
| `LivePipelineManager.swift` | 用CanvasComposer替换CropRenderer/OverlayCompositor/SongCardCompositor | **高** |
| `RTMPStreamManager.swift` | 分辨率枚举改为16:9 (720p=1280×720, 1080p=1920×1080) | 低 |
| `IOSurfaceOutputPool.swift` | 缓冲区尺寸自动跟随Config变更 | 低 |
| `Phase2View.swift` | 预览宽高比从1:2改为16:9 | 低 |
| `project.yml` | 添加Canvas目录下的新文件 | 低 |

#### 1.3 CanvasComposer 详细设计

**核心思路**：将当前的 CropRenderer + OverlayCompositor + SongCardCompositor 三步操作合并为**单个Compute Shader Pass**，从防抖纹理直接采样到16:9画布，减少GPU Pass数量。

**CanvasUniforms 结构体**：
```swift
struct CanvasUniforms {
    var cropX1: Float       // 裁剪区域左上角X（防抖坐标系）
    var cropY1: Float       // 裁剪区域左上角Y
    var cropW: Float        // 裁剪区域宽度
    var cropH: Float        // 裁剪区域高度
    var stabWidth: Float    // 防抖输出宽度 (1080)
    var stabHeight: Float   // 防抖输出高度 (1440)
    var canvasWidth: Float  // 画布宽度 (1920)
    var canvasHeight: Float // 画布高度 (1080)
    var gameX: Float        // 游戏区域在画布中的X偏移 (285)
    var gameY: Float        // 游戏区域在画布中的Y偏移 (0)
    var gameW: Float        // 游戏区域宽度 (1350)
    var gameH: Float        // 游戏区域高度 (1080)
    var bgColorR: Float     // 背景色R (0.06)
    var bgColorG: Float     // 背景色G (0.06)
    var bgColorB: Float     // 背景色B (0.12)
}
```

**Canvas.metal Shader 逻辑**：
```metal
kernel void cropAndCompose(
    texture2d<float, access::sample> stabOutput [[texture(0)]],
    texture2d<float, access::write>  canvasOutput [[texture(1)]],
    constant CanvasUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    // 边界检查
    if (gid.x >= uint(u.canvasWidth) || gid.y >= uint(u.canvasHeight)) return;

    // 判断当前像素是否在游戏区域内
    if (gid.x >= uint(u.gameX) && gid.x < uint(u.gameX + u.gameW) &&
        gid.y >= uint(u.gameY) && gid.y < uint(u.gameY + u.gameH))
    {
        // 游戏区域：计算在游戏区域内的归一化位置
        float relX = float(gid.x - uint(u.gameX)) / u.gameW;
        float relY = float(gid.y - uint(u.gameY)) / u.gameH;

        // 映射到防抖纹理坐标
        float srcX = u.cropX1 + relX * u.cropW;
        float srcY = u.cropY1 + relY * u.cropH;

        // 越界检查（裁剪区域超出防抖纹理范围时填充背景色）
        if (srcX < 0.0 || srcX >= u.stabWidth || srcY < 0.0 || srcY >= u.stabHeight) {
            canvasOutput.write(float4(u.bgColorR, u.bgColorG, u.bgColorB, 1.0), gid);
            return;
        }

        // 双线性采样防抖纹理
        float2 uv = float2(srcX / u.stabWidth, srcY / u.stabHeight);
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 rgba = stabOutput.sample(s, uv);
        canvasOutput.write(rgba, gid);
    }
    else
    {
        // 非游戏区域：填充深色背景
        canvasOutput.write(float4(u.bgColorR, u.bgColorG, u.bgColorB, 1.0), gid);
    }
}
```

**CanvasComposer.swift 类设计**：
```swift
class CanvasComposer {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let uniformsBuffer: MTLBuffer

    // 画布布局参数（基于1920×1080画布，5:4游戏区域居中）
    let canvasWidth: Int = 1920
    let canvasHeight: Int = 1080
    let gameX: Int = 285       // (1920 - 1350) / 2
    let gameY: Int = 0
    let gameW: Int = 1350      // 1080 * 5/4
    let gameH: Int = 1080

    let stabWidth: Float = Float(Config.stabWidth)   // 1080
    let stabHeight: Float = Float(Config.stabHeight) // 1440

    // 背景色（深蓝紫，可后续通过Config配置）
    var bgColorR: Float = 0.06
    var bgColorG: Float = 0.06
    var bgColorB: Float = 0.12

    init?(device: MTLDevice, commandQueue: MTLCommandQueue)
    func encode(into encoder: MTLComputeCommandEncoder,
                stabTexture: MTLTexture,
                cx: Float, cy: Float, cropW: Float, cropH: Float,
                outputTexture: MTLTexture)
}
```

**encode() 方法逻辑**：
1. 根据 cx, cy, cropW, cropH 计算 cropX1, cropY1
2. 填充 CanvasUniforms 并拷贝到 uniformsBuffer
3. 设置 pipeline, textures (stabOutput=0, canvasOutput=1), buffer
4. dispatchThreads: gridSize = canvasWidth × canvasHeight, threadgroupSize = 16×16

#### 1.4 BBoxTracker 修改详情

**当前问题**：outputRatio = Config.outputWidth / Config.outputHeight = 720/1440 = 0.5

**修改方案**：引入独立的裁剪比例，与输出分辨率解耦

```swift
// 修改前
private let outputRatio: Float = Float(Config.outputWidth) / Float(Config.outputHeight)  // 0.5

// 修改后
private let cropRatio: Float = Float(Config.gameAreaWidth) / Float(Config.gameAreaHeight)  // 5/4 = 1.25
```

**裁剪区域计算修改**：

1. **初始化居中裁剪**：
```swift
// 修改前
lastCropW = stabHeight * outputRatio  // 1440 * 0.5 = 720
lastCropH = stabHeight               // 1440

// 修改后（5:4裁剪，宽度不能超过stabWidth）
let maxCropW: Float = stabWidth      // 1080
let maxCropH = maxCropW / cropRatio  // 1080 / 1.25 = 864
lastCropW = maxCropW                 // 1080
lastCropH = maxCropH                 // 864
```

2. **追踪目标时**：
```swift
// 修改前
let cropW = cropH * outputRatio

// 修改后
var cropW = cropH * cropRatio
// clamp: 裁剪宽度不能超过防抖纹理宽度
cropW = min(cropW, stabWidth)
// 重新计算cropH以保持5:4比例
let adjustedCropH = cropW / cropRatio
```

3. **回中/空闲时**：同初始化逻辑，使用clamp后的最大5:4裁剪区域

#### 1.5 LivePipelineManager 修改详情

**管线编码部分修改**（替换第646-705行）：

```swift
// 修改前：3步操作
cr.encode(into: encoder, stabTexture: stab.outputTexture, ...)           // CropRenderer
overlay.encode(into: encoder, outputTexture: writeBuffer.texture)        // OverlayCompositor
songCard.updateAnimations(); songCard.encode(into: encoder, ...)         // SongCardCompositor

// 修改后：1步操作
canvasComposer.encode(into: encoder,
                      stabTexture: stab.outputTexture,
                      cx: track.cx, cy: offsetCy,
                      cropW: track.cropW, cropH: track.cropH,
                      outputTexture: writeBuffer.texture)                 // CanvasComposer
```

**初始化部分修改**：
- 移除 CropRenderer、OverlayCompositor、SongCardCompositor 的初始化
- 新增 CanvasComposer 初始化
- 保留 SongCardManager（队列管理逻辑不变，只是渲染方式变了）

**点歌相关回调修改**：
- `addSongToQueue` / `addSongAtNextToQueue` 等方法中移除卡片渲染和Compositor操作
- 队列管理逻辑（SongCardManager）保持不变
- 阶段二/三再接入面板渲染

#### 1.6 RTMPStreamManager 修改详情

```swift
// 修改前
enum StreamResolution: String, CaseIterable {
    case r720p = "720p"
    case r1080p = "1080p"
    var size: CGSize {
        switch self {
        case .r720p: return CGSize(width: Config.outputWidth, height: Config.outputHeight)  // 720x1440
        case .r1080p: return CGSize(width: 1080, height: 2160)
        }
    }
}

// 修改后
enum StreamResolution: String, CaseIterable {
    case r720p = "720p"
    case r1080p = "1080p"
    var size: CGSize {
        switch self {
        case .r720p: return CGSize(width: 1280, height: 720)    // 16:9 720p
        case .r1080p: return CGSize(width: 1920, height: 1080)  // 16:9 1080p
        }
    }
}
```

注意：720p模式下，IOSurface池仍为1920×1080，HaishinKit编码器会自动缩放。

#### 1.7 Config.swift 修改详情

```swift
// 修改前
static let outputWidth = 720
static let outputHeight = 1440

// 修改后
static let outputWidth = 1920
static let outputHeight = 1080

// 新增：游戏区域比例（5:4，即 width:height = 5:4）
static let gameAreaRatio: Float = 5.0 / 4.0  // 1.25

// 新增：游戏区域在画布中的布局
// 5:4比例：游戏区域高度=画布高度(1080)，宽度=1080×5/4=1350
// 游戏区域X偏移=(1920-1350)/2=285，Y偏移=0
static var gameAreaWidth: Int {
    Int(Float(outputHeight) * gameAreaRatio)  // 1080 * 1.25 = 1350
}
static var gameAreaHeight: Int {
    outputHeight  // 1080
}
static var gameAreaX: Int {
    (outputWidth - gameAreaWidth) / 2  // (1920 - 1350) / 2 = 285
}
static var gameAreaY: Int {
    0
}
```

#### 1.8 Phase2View 修改详情

```swift
// 修改前
MetalView(...)
    .aspectRatio(
        pipeline.isCropActive
            ? CGFloat(Config.outputWidth) / CGFloat(Config.outputHeight)  // 720/1440 = 0.5
            : 3.0 / 4.0,
        contentMode: .fit
    )

// 修改后
MetalView(...)
    .aspectRatio(
        pipeline.isCropActive
            ? CGFloat(Config.outputWidth) / CGFloat(Config.outputHeight)  // 1920/1080 = 16/9
            : 3.0 / 4.0,
        contentMode: .fit
    )
```

#### 1.9 性能预估

| 指标 | 当前 (1:2) | 阶段一 (16:9) | 变化 |
|------|-----------|-------------|------|
| GPU Pass数 | 3 (Crop+Overlay+SongCard) | 1 (CanvasComposer) | **-67%** |
| 输出纹理像素 | 720×1440 = 1.04M | 1920×1080 = 2.07M | +100% |
| 总dispatch线程 | ~6.2M (3次全画布dispatch) | ~2.1M (1次全画布dispatch) | **-66%** |
| 显存占用 | ~4MB (输出) + ~1.5MB (卡片) | ~8MB (输出) | +50% |
| 预估每帧耗时 | ~12ms | ~10-14ms | 持平或更优 |

**关键优化**：虽然输出纹理像素翻倍，但GPU Pass从3个减少到1个，总dispatch线程数减少66%。单Pass意味着只提交1次CommandBuffer，减少了GPU同步开销。预估性能持平或略有提升。

#### 1.10 实施步骤顺序

1. 修改 `Config.swift`（输出分辨率+游戏区域参数）
2. 新建 `Canvas/` 目录及3个文件（CanvasUniforms + Canvas.metal + CanvasComposer.swift）
3. 修改 `BBoxTracker.swift`（cropRatio + 裁剪计算逻辑）
4. 修改 `LivePipelineManager.swift`（替换管线编码，禁用旧组件）
5. 修改 `RTMPStreamManager.swift`（16:9分辨率）
6. 修改 `Phase2View.swift`（预览比例）
7. 修改 `project.yml`（添加新文件引用）
8. 编译测试

#### 1.11 验证标准（人工验证）

- [ ] 推流输出为16:9横屏画面
- [ ] 游戏画面5:4居中显示，不变形
- [ ] 两侧为深色背景（非黑屏/花屏）
- [ ] YOLO追踪正常工作（目标检测→跟踪→裁剪→居中）
- [ ] 防抖功能正常
- [ ] 推流画面流畅，无卡顿/掉帧
- [ ] 预览画面正确显示16:9比例
- [ ] Web控制面板可正常访问和操作队列

### 阶段二：左侧面板

**目标**：实现左侧面板的当前歌曲卡片、下一首卡片、公告区域

- 新增 LeftPanelRenderer（WKWebView + HTML模板）
- 实现当前歌曲大封面卡片
- 实现下一首卡片
- 实现公告/规则区域
- 集成到 CanvasComposer

**验证标准**：左侧面板正确显示当前歌曲、下一首、公告信息，切歌时动画流畅

### 阶段三：右侧面板

**目标**：实现右侧面板的点歌队列滚动列表

- 新增 RightPanelRenderer（WKWebView + HTML模板）
- 实现紧凑行式队列列表
- 实现封面缩略图加载
- 实现插队标识
- 实现滚动动画
- 集成到 CanvasComposer

**验证标准**：右侧面板正确显示排队列表，新歌加入/切歌时动画流畅，插队标识清晰

### 阶段四：优化与完善

**目标**：性能优化和细节打磨

- 性能测试与优化（确保每帧处理时间不增加）
- 面板背景渐变/主题定制
- Web控制面板适配新布局
- 边界情况处理（空队列、超长歌名等）

***

## 八、风险与注意事项

1. **性能风险**：1920×1080 比 720×1440 像素总量更大（2.07M vs 1.04M），需关注GPU负载
2. **YOLO追踪适配**：5:4裁剪比1:2宽很多，追踪算法的裁剪区域计算需要重新调整
3. **WebView渲染延迟**：面板内容变化到画面更新的延迟需控制在可接受范围
4. **向后兼容**：Web控制面板的API需要适配新的队列显示逻辑
5. **推流码率**：1080p需要更高码率，可能需要从4000kbps提升到6000-8000kbps

