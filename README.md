# 快捷高光 (QuickHighlight)

> 录屏 / 演示场景下，按住一个键即可让鼠标周围浮起一个放大圈，圈外暗化，圈内高亮放大画面细节。

一个轻量的 macOS 屏幕局部放大工具，让你在录教程、演讲、远程协作时，**让观众一眼看清你正在操作的位置**。

## 功能

- 🔍 **按住激活**：默认按住左 Option，鼠标周围浮现放大圈，松开即消失
- 🎯 **跟手居中**：60 fps 实时跟随鼠标，无延迟
- ◯ **两种形状**：圆形 / 圆角矩形，可全局快捷键秒切
- 🎚 **参数自定义**：放大倍率、尺寸、外圈暗度、是否显示白色高光圆环
- ⌨️ **录入式快捷键**：点击输入框直接按键即可设置（含切换形状的全局组合键）
- 🚀 **菜单栏常驻**：低存在感，不抢 Dock 位置
- 🖱 **隐藏圈内鼠标**：放大画面不被光标挡字
- ⚡ **基于 ScreenCaptureKit**：60 fps 流畅，与 macOS 现代图形栈无缝集成
- 🎬 **开机自启**：可选，由 `SMAppService` 管理

## 安装

### 方式 1：自己 build（推荐）

要求：macOS 14+ + Xcode Command Line Tools

```bash
git clone https://github.com/Daknniel-0881/quickhighlight.git
cd quickhighlight
bash build_app.sh
```

`build_app.sh` 会：
1. `swift build -c release` 编译
2. 生成图标 `.icns`
3. 打包成 `dist/快捷高光.app`
4. 安装到 `/Applications/快捷高光.app`
5. 在桌面创建 symlink 快捷方式

首次运行会请求两项权限：
- **辅助功能**：监听全局热键（按住激活）
- **屏幕录制**：放大圈内显示鼠标周围画面

### 方式 2：下载 Release

> 还没出，等首个 release。

## 用法

### 默认热键

| 操作 | 快捷键 |
|---|---|
| 激活放大镜 | 按住 **左 Option** |
| 切换形状 | 自定义（默认未设置）|
| 打开偏好设置 | 菜单栏 🔍 → 偏好设置 |

### 自定义快捷键

设置面板 → **快捷键** Tab：

- **激活放大镜**：点击输入框 → 按一下你要的修饰键（⌥ ⇧ ⌃ ⌘ Fn 之一） → 完成
- **切换形状**：点击输入框 → 按下组合键（必须含修饰键，如 ⌃⌥S） → 完成

### 调参

设置面板 → **放大镜** Tab，所有滑块实时生效，可在预览框内即时观察效果：

- 形状：圆形 / 圆角矩形
- 尺寸：圆形为半径，圆角矩形为宽 × 高（独立调节）
- 放大倍率：1.0× ~ 6.0×（默认 1.5×）
- 外圈暗度：0% ~ 90%（默认 60%）

## 项目结构

```
Sources/CursorMagnifier/
├── main.swift               # NSApplication 入口（.accessory 模式）
├── AppDelegate.swift        # 菜单栏 + 设置窗口 + 总指挥
├── HotkeyMonitor.swift      # IOKit 设备掩码 + 组合键 keyDown 监听
├── HotkeyRecorder.swift     # SwiftUI 录入式快捷键控件
├── KeyDisplay.swift         # keyCode → "⌃⌥S" 文字渲染
├── ScreenCapturer.swift     # SCStream 60 fps 抓帧（@MainActor）
├── OverlayWindow.swift      # 透明全屏窗口（不抢焦点 / 不挡点击）
├── OverlayView.swift        # 暗化挖洞 + crop + 放大绘制
├── SettingsStore.swift      # UserDefaults + @Published + 版本迁移
├── SettingsView.swift       # SwiftUI 三 Tab 设置面板
└── LaunchAtLogin.swift      # SMAppService 开机自启
```

## 技术要点

### 为什么不用 `CGWindowListCreateImage`

macOS 15+ 已废弃，且**权限缺失时会静默退化为只返回桌面壁纸**（不报错）—— 这是网上很多老项目「圈内只显示桌面」的真凶。本项目用 `ScreenCaptureKit (SCStream)` 持续抓主屏帧，60 fps、IOSurface-backed `CVPixelBuffer`，性能与正确性兼得。

### 为什么 zoom 一定要算 backingScaleFactor

`SCDisplay.width / .height` 已经是物理像素（不是点）。如果直接 `config.width = display.width * 2` 会变成 4× 超采样，导致 `frame.width / pointSize.width` 算出 4.0 而不是 backing scale 真值 2.0，crop 像素区域是预期 2 倍 —— **zoom 参数被这个错误的 scale 视觉化抵消掉**。正确做法：

```swift
let pointSize = NSScreen.main!.frame.size
let backingScale = NSScreen.main!.backingScaleFactor
config.width = Int((pointSize.width * backingScale).rounded())
config.height = Int((pointSize.height * backingScale).rounded())
```

### 为什么不用 `NSImage.draw(in:)` 绘制 cropped 帧

`NSImage(cgImage: cropped, size: NSSize)` 在某些缩放场景下**会忽略 size 参数**，沿用源 CGImage 像素尺寸，导致放大倍率视觉上不生效。改用 `CGContext.draw(cgImage, in: rect)`，让 CGContext 自己按 src/dst 比例缩放，无歧义。

### 设备级 mask 区分左右修饰键

`NSEvent.ModifierFlags.option` 不区分左右键。但 `event.modifierFlags.rawValue` 包含 IOKit device-side bits（`kIOHIDKeyboardModifierMaskLeft*`），按位与即可：

```swift
.leftOption.deviceMask  = 0x000020
.rightOption.deviceMask = 0x000040
```

### 全局组合键监听

用 `NSEvent.addGlobalMonitorForEvents(.keyDown)` + `addLocalMonitorForEvents` 双管齐下：global 接其他 app 内的按键，local 接自家窗口的按键并能消费事件（避免误触表单）。已授权辅助功能即可工作，不需要额外授权 Input Monitoring。

## Windows 移植思路

如果你想在 Windows 上做同样的工具，技术栈对照：

| macOS | Windows | 说明 |
|---|---|---|
| ScreenCaptureKit (SCStream) | **Windows.Graphics.Capture** (UWP) 或 DXGI Desktop Duplication API | 推荐 Graphics.Capture，权限模型干净，DXGI 偶尔会被 fullscreen exclusive 顶掉 |
| NSWindow level=.screenSaver | **Win32 layered window** + `WS_EX_TOPMOST` + `WS_EX_TRANSPARENT` | 透明覆盖层，鼠标事件穿透 |
| NSEvent.addGlobalMonitorForEvents | **`SetWindowsHookEx(WH_KEYBOARD_LL)`** + `WH_MOUSE_LL` 低级钩子 | 全局键盘监听 |
| AXIsProcessTrusted | 不需要 | Windows 没有等价"辅助功能"权限闸门 |
| SMAppService | **任务计划程序 / 注册表 Run 键** | 开机自启 |
| SwiftUI Settings | **WPF / WinUI 3** | 推荐 WinUI 3 + C#，原生 Fluent Design |
| AppKit drawing | **Direct2D / Skia** | 60 fps 圆形 clip + 缩放绘制 |

**架构建议**：用 **C# / .NET 8 + WinUI 3**：
- `Microsoft.UI.Xaml` 做设置面板（与 SwiftUI 体验最接近）
- `Windows.Graphics.Capture` API 抓帧（需要 UWP capability `graphicsCapture`）
- `Microsoft.UI.Composition` 做透明覆盖层和圆形 clip
- 全局热键用 `RegisterHotKey` (Win32) 或 `WH_KEYBOARD_LL` 钩子
- 打包成 MSIX，自带 logo + 桌面快捷方式

**关键复杂点**：
1. **DPI 适配**：Windows 多显示器各自 DPI scale，绘制 / crop 时必须按 per-monitor DPI 算坐标，比 macOS 的 backingScaleFactor 更复杂
2. **DRM 内容**：Netflix / 部分流媒体在 Windows 上抓帧会变黑，需要在抓不到时降级
3. **多桌面 (Virtual Desktop)**：覆盖窗口要正确处理切换桌面的可见性
4. **HiDPI 鼠标坐标**：`GetCursorPos` 返回逻辑像素，与 Capture API 拿到的物理像素需要换算

如有兴趣启动 Windows 版，欢迎开 issue 讨论或直接 PR `quickhighlight-win/` 子目录。

## 开发

```bash
swift build                      # debug build
swift build -c release           # release build
bash build_app.sh                # 完整流程：编译 → 打包 → 装 /Applications → 桌面 symlink
```

调试时直接跑 `.build/debug/CursorMagnifier`，菜单栏图标会出现，但你需要**先**给这个 debug binary 单独授一次屏幕录制权限。

## License

[MIT](LICENSE) © 2026 Daknniel-0881
