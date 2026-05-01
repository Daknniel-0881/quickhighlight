# 快捷高光 (QuickHighlight)

> 录屏 / 演讲 / 远程协作场景下，按住一个键即可让鼠标周围浮起一个放大圈，圈外暗化，圈内高亮放大画面细节。

一个轻量的 macOS 屏幕局部放大工具——让观众一眼看清你正在操作的位置。基于 ScreenCaptureKit 60 fps 抓帧，原生 AppKit 渲染，菜单栏常驻不抢 Dock。

![放大镜设置](screenshots/03_settings_magnifier.png)

---

## ✨ 功能一览

### 核心交互
- 🔍 **按住激活**：默认按住「左 Option」，鼠标周围浮现放大圈，松开即消失
- 🎯 **跟手居中**：60 fps 实时跟随鼠标，无延迟
- ◯ **两种形状**：圆形 / 圆角矩形，圆角矩形宽高独立调节
- ⌨️ **全局组合键秒切形状**：自定义快捷键（如 ⌃⌥S）随时切换圆形⇄矩形，不用打开设置
- 🚀 **菜单栏常驻**：低存在感，不抢 Dock 位置

### 画面控制
- 🔬 **放大倍率 1.0× ~ 6.0×**（默认 1.5×，0.1 步进）
- 📏 **尺寸滑块**：圆形半径 50–400 px / 矩形宽 100–800 px / 矩形高 30–600 px
- 🌑 **外圈暗化**：0% – 90% 可调，强化视觉聚焦
- ⚪ **白色高光圆环**：可开关，让放大圈的边界更清晰
- ✨ **抗模糊锐化**：CIUnsharpMask 锐化，仅 zoom > 1.0× 时生效，让文字边缘更清晰
- 🔢 **当前倍率小标识**：放大圈下方显示 `1.5×` / `4.0×` 实时倍率（录屏时建议关闭）

### 可调试性
- 🪞 **实时预览**：设置面板内嵌预览框，拖滑块时即时看到形状/暗度/倍率效果
- 🎬 **持续预览模式**：开启后放大圈一直显示，可一边拖滑块一边在真实窗口对比
- ⚡ **瞬时测试 (1.5s)**：在当前鼠标位置闪现放大圈 1.5 秒，验证参数

### 系统集成
- 🎬 **开机自启**：可选，由 `SMAppService` 管理
- 🔐 **稳定本地代码签名保护**：默认使用 `QuickHighlightLocalSigner`，避免 ad-hoc rebuild 让 macOS 把 App 当成新程序反复请求屏幕录制权限
- 🖼 **桌面快捷方式带 Logo**：自动复制完整 .app 到桌面，Finder 直接显示应用图标
- 📍 **多显示器感知**：副屏暂不放大（SCStream 当前仅抓主屏），不会出错或卡死

---

## 📸 界面预览

### 通用设置（开机自启 / 高光圆环）
![通用设置](screenshots/01_settings_general.png)

### 快捷键设置（激活键 / 切换形状组合键）
![快捷键设置](screenshots/02_settings_hotkey.png)

### 放大镜参数（形状 / 尺寸 / 倍率 / 暗度 / 锐化）
![放大镜设置](screenshots/03_settings_magnifier.png)

---

## 🚀 安装

### 自己 Build（推荐）

要求：**macOS 14+** + Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/Daknniel-0881/quickhighlight.git
cd quickhighlight
bash build_app.sh
```

`build_app.sh` 一键完成：
1. `swift build -c release` 编译
2. 用 `generate_icon.swift` 生成图标 `.icns`
3. 打包成 `dist/快捷高光.app`
4. 用稳定本地证书签名（首次自动创建 `QuickHighlightLocalSigner`）
5. 安装到 `/Applications/快捷高光.app`
6. 复制完整 .app 到桌面（带完整 icon resource，Finder 直接显示 logo）
7. 重新注册到 Launch Services 刷图标缓存
8. 关闭旧实例，准备启动新版本

### 首次运行

双击桌面【快捷高光】图标启动，菜单栏会出现 🔍 图标。

首次运行需授权两项系统权限：

| 权限 | 用途 | 路径 |
|---|---|---|
| **辅助功能** | 监听全局热键（按住激活、组合键切换形状）| 系统设置 → 隐私与安全性 → 辅助功能 |
| **屏幕录制** | 抓主屏画面给放大圈显示 | 系统设置 → 隐私与安全性 → 屏幕录制 |

> macOS 的屏幕录制授权和 App 代码身份绑定。`build_app.sh` 默认拒绝生成 ad-hoc 签名产物，避免重 build 后 cdhash 漂移导致反复授权。若只是临时本机调试，可显式运行 `QH_ALLOW_ADHOC=1 bash build_app.sh`，但这可能让系统再次请求屏幕录制授权。

---

## 🎮 用法

### 默认热键

| 操作 | 快捷键 |
|---|---|
| 激活放大镜 | 按住 **左 Option (⌥)** |
| 切换形状 | 默认未设置（建议设为 ⌃⌥S）|
| 打开偏好设置 | 菜单栏 🔍 → 偏好设置 |

### 自定义快捷键

打开偏好设置 → **快捷键** Tab：

- **激活放大镜**：点击输入框 → 按一下你要的修饰键（⌥ / ⇧ / ⌃ / ⌘ / Fn）→ 完成。**仅支持单个修饰键**（按住-放开式交互）
- **切换形状**：点击输入框 → 按下组合键（必须含修饰键，如 ⌃⌥S）→ 完成。每次按下立即在圆形⇄圆角矩形之间切换

### 调参流程（推荐）

1. 打开偏好设置 → **放大镜** Tab
2. 看上方「实时预览」框，先选好形状
3. 拖动尺寸/倍率/暗度滑块，每一帧都自动保存
4. 点「**持续预览**」按钮 → 放大圈在真实桌面上长亮
5. 把鼠标移到任意窗口，继续拖滑块 → 实时对比真实效果
6. 满意后再点一次按钮关闭持续预览

### 录屏建议参数

- **屏幕录制教学**：圆角矩形 360×220 / 倍率 1.5× / 暗度 60% / 关闭倍率标签
- **代码细节展示**：圆形半径 100 / 倍率 2.5× / 暗度 70% / 开启锐化
- **远程会议指引**：圆形半径 150 / 倍率 1.3× / 暗度 40% / 开启高光环

---

## 🏗 项目结构

```
Sources/CursorMagnifier/
├── main.swift               # NSApplication 入口（.accessory 模式不抢 Dock）
├── AppDelegate.swift        # 菜单栏 + 设置窗口 + 总指挥
├── HotkeyMonitor.swift      # IOKit 设备掩码 + 组合键 keyDown 监听
├── HotkeyRecorder.swift     # SwiftUI 录入式快捷键控件
├── KeyDisplay.swift         # keyCode → "⌃⌥S" 文字渲染
├── ScreenCapturer.swift     # SCStream 60 fps 抓帧（@MainActor）
├── OverlayWindow.swift      # 透明全屏窗口（不抢焦点 / 不挡点击）
├── OverlayView.swift        # 暗化挖洞 + crop + 缩放绘制 + CIUnsharpMask 锐化
├── SettingsStore.swift      # UserDefaults + @Published + 版本迁移
├── SettingsView.swift       # SwiftUI 三 Tab 设置面板 + 实时预览 Canvas
└── LaunchAtLogin.swift      # SMAppService 开机自启
```

---

## 🔬 技术要点

### 为什么不用 `CGWindowListCreateImage`

macOS 15+ 已废弃，且**权限缺失时会静默退化为只返回桌面壁纸**（不报错）—— 这是网上很多老项目「圈内只显示桌面」的真凶。本项目用 `ScreenCaptureKit (SCStream)` 持续抓主屏帧，60 fps、IOSurface-backed `CVPixelBuffer`，性能与正确性兼得。

### 为什么 zoom 必须算 backingScaleFactor

`SCDisplay.width / .height` 已经是物理像素（不是点）。如果直接 `config.width = display.width × 2` 会变成 4× 超采样，导致 `frame.width / pointSize.width` 算出 4.0 而不是 backing scale 真值 2.0，crop 像素区域是预期 2 倍 —— **zoom 参数被这个错误的 scale 视觉化抵消掉**。正确做法：

```swift
let pointSize = NSScreen.main!.frame.size
let backingScale = NSScreen.main!.backingScaleFactor
config.width = Int((pointSize.width * backingScale).rounded())
config.height = Int((pointSize.height * backingScale).rounded())
```

### 关键 bug 修复：`CGImage.cropping(to:)` 是「父帧 buffer 的窗口视图」

> 这是本项目最难调的一个 bug。表象：把 zoom 拉到 4×、6× 也看不出任何放大效果。

`CGImage.cropping(to: rect)` **不返回独立 bitmap**，而是返回一个引用父帧的「cropping view」。在某些 macOS / 显卡驱动版本上，把这个 view 喂给 `ctx.draw(image, in: dstRect)` 时，CG 渲染管线会忽略 cropping view 的边界，**实际渲染整个父帧再缩放到 dstRect** —— 用户自始至终看到的都是 1920×1080 整屏被强行塞进放大圈，倍率信息完全丢失。

**修复方案**：用 `CIImage` + `CIContext.createCGImage(_:from:)` 强制物化成独立的 standalone bitmap：

```swift
let fullCI = CIImage(cgImage: frame)
// 注意 CIImage 用左下原点，CGImage cropRect 是左上原点，需要翻 Y
let ciCropRect = CGRect(
    x: cropRect.minX,
    y: CGFloat(frame.height) - cropRect.maxY,
    width: cropRect.width,
    height: cropRect.height
)
let processedCI = fullCI.cropped(to: ciCropRect)

// CIUnsharpMask 抗模糊（zoom > 1.05 时生效）
if SettingsStore.shared.sharpenEnabled, zoom > 1.05 {
    let f = CIFilter.unsharpMask()
    f.inputImage = processedCI
    f.radius = 1.2
    f.intensity = 0.5
    if let out = f.outputImage { processedCI = out }
}

// createCGImage 是关键 —— 强制物化成自洽 bitmap，彻底解耦父帧
let materialized = sharpenCIContext.createCGImage(processedCI, from: ciCropRect)
```

然后绘制路径用经典的 translate + scale 翻 Y，让 `ctx.draw(img, in: 0,0,w,h)` 精确缩放到 lens 几何区域：

```swift
ctx.translateBy(x: circleRect.minX, y: circleRect.maxY)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(img, in: CGRect(x: 0, y: 0, width: circleRect.width, height: circleRect.height))
```

### 设备级 mask 区分左右修饰键

`NSEvent.ModifierFlags.option` 不区分左右键。但 `event.modifierFlags.rawValue` 包含 IOKit device-side bits（`kIOHIDKeyboardModifierMaskLeft*`），按位与即可：

```swift
.leftOption.deviceMask  = 0x000020
.rightOption.deviceMask = 0x000040
.fn.deviceMask          = 0x800000
```

### 全局组合键监听

用 `NSEvent.addGlobalMonitorForEvents(.keyDown)` + `addLocalMonitorForEvents` 双管齐下：global 接其他 app 内的按键，local 接自家窗口的按键并能消费事件（避免误触表单）。已授权辅助功能即可工作，**不需要额外授权 Input Monitoring**。

### 稳定本地代码签名（重 build 后不弹权限）

`codesign --sign -` ad-hoc 签名每次重 build 都会生成新的 cdhash，TCC 数据库以为是新 app 反复要求授权。`build_app.sh` 优先使用本地自签 `QuickHighlightLocalSigner` 长期复用，并且默认不再悄悄退回 ad-hoc：

```bash
bash build_app.sh
```

如果钥匙串私钥访问授权未完成，脚本会停止并说明原因。临时调试可以显式设置 `QH_ALLOW_ADHOC=1`，但发布/日常使用不推荐。

### Windows 版本

Windows WPF/.NET 8 端口位于 `quickhighlight-win/QuickHighlight/`：

- 使用 `Windows.Graphics.Capture` + D3D11 frame pool 持续抓主屏。
- 使用透明置顶 WPF overlay，`WS_EX_TRANSPARENT` 鼠标穿透。
- 默认按住 `LeftAlt` 显示高光，`Ctrl+Alt+S` 全局切换圆形 / 圆角矩形。
- 抓帧失败时不弹窗、不在 lens 内画错误文字，托盘轻提示并指数退避重连。

Windows 构建：

```powershell
cd quickhighlight-win
.\build.ps1
```

输出：`quickhighlight-win/artifacts/QuickHighlight-win-x64.zip`

---

## 🪟 Windows 移植思路

如果你想在 Windows 上做同样的工具，技术栈对照：

| macOS | Windows | 说明 |
|---|---|---|
| ScreenCaptureKit (SCStream) | **Windows.Graphics.Capture** (UWP) 或 DXGI Desktop Duplication API | 推荐 Graphics.Capture，权限模型干净 |
| NSWindow level=.screenSaver | **Win32 layered window** + `WS_EX_TOPMOST` + `WS_EX_TRANSPARENT` | 透明覆盖层，鼠标事件穿透 |
| NSEvent.addGlobalMonitorForEvents | **`SetWindowsHookEx(WH_KEYBOARD_LL)`** + `WH_MOUSE_LL` 低级钩子 | 全局键盘监听 |
| AXIsProcessTrusted | 不需要 | Windows 没有等价"辅助功能"权限闸门 |
| SMAppService | **任务计划程序 / 注册表 Run 键** | 开机自启 |
| SwiftUI Settings | **WPF / WinUI 3** | 推荐 WinUI 3 + C#，原生 Fluent Design |
| AppKit drawing | **Direct2D / Skia** | 60 fps 圆形 clip + 缩放绘制 |
| CIUnsharpMask | **Direct2D Effects: D2D1_UNSHARP_MASK** | 抗模糊锐化 |

**关键复杂点**：
1. **DPI 适配**：Windows 多显示器各自 DPI scale，比 macOS 的 backingScaleFactor 更复杂
2. **DRM 内容**：Netflix / 部分流媒体在 Windows 上抓帧会变黑，需要降级
3. **多桌面 (Virtual Desktop)**：覆盖窗口要正确处理切换桌面的可见性
4. **HiDPI 鼠标坐标**：`GetCursorPos` 返回逻辑像素，与 Capture API 拿到的物理像素需要换算

如有兴趣启动 Windows 版，欢迎开 issue 讨论或直接 PR `quickhighlight-win/` 子目录。

---

## 🛠 开发

```bash
swift build                      # debug build
swift build -c release           # release build
bash build_app.sh                # 完整流程：编译 → 签名 → 装 /Applications → 桌面快捷方式
```

调试时直接跑 `.build/debug/CursorMagnifier`，菜单栏图标会出现，但你需要先给这个 debug binary 单独授一次屏幕录制权限。

### 调试用环境变量

| 变量 | 值 | 用途 |
|---|---|---|
| `QH_OPEN_SETTINGS` | `1` | 启动后立即打开设置面板（用于截图） |
| `QH_TAB` | `general` / `hotkey` / `magnifier` | 设置面板预选 tab |

```bash
QH_OPEN_SETTINGS=1 QH_TAB=magnifier ./.build/release/CursorMagnifier
```

---

## 📝 License

[MIT](LICENSE) © 2026 Daknniel-0881
