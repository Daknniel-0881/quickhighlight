# 踩坑清单（PITFALLS — 不再犯）

> **每次写新代码、改老代码前必读。**
> 这里每一条都是真实流过血的坑，写代码时主动避开 —— 不要因为「这次不一样」而重新踩。

## 索引（按风险域分组）

- [§1 渲染管线](#1-渲染管线)
- [§2 ScreenCaptureKit](#2-screencapturekit)
- [§3 坐标系 & DPI](#3-坐标系--dpi)
- [§4 权限 & 签名](#4-权限--签名)
- [§5 SwiftUI 绑定](#5-swiftui-绑定)

---

## §1 渲染管线

### P-001 · 不要用 `CGImage.cropping(to:)` 喂给 `ctx.draw`
**症状**：zoom 倍率拉到 4×、6× 也看不出任何放大效果，圈内画面始终是整屏被压缩塞进去。
**根因**：`CGImage.cropping(to:)` 不返回独立 bitmap，返回的是引用父帧 buffer 的「cropping view」。某些 macOS / 显卡驱动版本下，把这个 view 喂给 `ctx.draw(image, in: dstRect)` 会**忽略 cropping 边界**，实际渲染整个父帧再缩放到 dstRect。
**正确做法**：
```swift
let fullCI = CIImage(cgImage: frame)
let cropped = fullCI.cropped(to: ciCropRect)
let materialized = ciContext.createCGImage(cropped, from: ciCropRect)  // 强制物化
ctx.draw(materialized, in: lensRect)
```
**反模式**：`frame.cropping(to: rect)` → `ctx.draw(view, in:)` ❌ 永远不要。

---

### P-002 · 不要在 NSView (isFlipped=false) 里手动 `scaleBy(x:1, y:-1)` 翻转 CGImage
**症状**：lens 圈内画面**上下颠倒**，桌面像照镜子一样。
**根因**：误解「CGImage top-down vs CGContext y-up 需要手动翻 Y」。实际上 AppKit 的 `ctx.draw(cgImage, in: rect)` **已经会自动正向映射** top-down CGImage 到 y-up 坐标系的 rect 上。手动再翻一次就反了。
**正确做法**：
```swift
ctx.draw(cgImage, in: rect)   // 直接画就是正的
```
**反模式**：以下组合是上下颠倒的元凶 ❌
```swift
ctx.translateBy(x: rect.minX, y: rect.maxY)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
```
**触发条件**：仅在你自己创建了一个 *flipped* 的 ctx 或者从 CGBitmap 之类的 top-down ctx 拷贝时才需要 flip；NSView.draw 里的 ctx **不需要**。

---

### P-003 · `NSImage(cgImage:size:)` 不一定按 size 缩放
**症状**：放大倍率参数变了，视觉上完全不变。
**根因**：`NSImage(cgImage: cgImage, size: NSSize)` 在某些缩放场景下会**忽略 size 参数**，沿用源 CGImage 的像素尺寸。
**正确做法**：
```swift
ctx.draw(cgImage, in: dstRect)   // 让 CGContext 自己按 src→dst 比例缩放
```
**反模式**：`NSImage(cgImage:size:).draw(in:from:.zero)` ❌ 在缩放路径上不可靠。

---

### P-004 · CIUnsharpMask 在小 crop 上参数太弱看不见
**症状**：开启「锐化抗模糊」开关后，圈内文字看着没变化，跟没开一样。
**根因**：CIUnsharpMask 的 `radius` 参数是**绝对像素**单位。crop 区域只有 68×67 像素时，radius=1.2 = 仅占图像 1.7% 半径，肉眼几乎看不出。
**正确做法**：参数跟 zoom 走（zoom 越高、crop 越小，参数要越激进）：
```swift
f.radius    = Float(min(3.5, 1.0 + z * 0.45))  // 1.5×→1.7  6×→3.5
f.intensity = Float(min(1.2, 0.4 + z * 0.15))  // 1.5×→0.62  6×→1.2
```
**经验值**：肉眼可见的最小 unsharp 强度大约是 radius ≥ 2 + intensity ≥ 0.7 在 crop 像素 < 200 的小图上。

---

## §2 ScreenCaptureKit

### P-101 · 不要用废弃的 `CGWindowListCreateImage`
**症状**：圈内只显示桌面壁纸，不显示真实桌面应用。
**根因**：macOS 15+ 已废弃；权限缺失时**静默退化**为只返回桌面壁纸（不报错）。
**正确做法**：用 `ScreenCaptureKit` (`SCStream` + `SCContentFilter`)，60 fps 抓 IOSurface-backed CVPixelBuffer。

### P-102 · `SCDisplay.width/.height` 已经是物理像素
**症状**：zoom 视觉上算出来的倍率跟参数对不上，永远小一倍。
**根因**：`SCDisplay.width / .height` 是物理像素（不是点）。如果再 `× backingScaleFactor` 就是 4× 超采样，算出来的 scale 是真值的 2 倍，crop 像素区域也跟着翻倍 —— zoom 被这个错误的 scale 抵消。
**正确做法**：
```swift
let pointSize = NSScreen.main!.frame.size
let backingScale = NSScreen.main!.backingScaleFactor
config.width  = Int((pointSize.width  * backingScale).rounded())
config.height = Int((pointSize.height * backingScale).rounded())
```

### P-103 · SCStream 当前只抓主屏
**症状**：鼠标在副屏时 crop 出来空，画面渲染成 nil。
**正确做法**：检测 `mouseScreen.frame.origin == .zero`（主屏判定），副屏时 `capturedCGImage = nil` 跳过渲染，**不要**强行 crop 一个非主屏的区域。

---

## §3 坐标系 & DPI

### P-201 · CIImage 是左下原点，CGImage 是左上原点
**症状**：crop 区域偏移，圈内画面是错误位置的内容。
**正确做法**：CGImage cropRect → CIImage cropRect 时翻 Y：
```swift
let ciCropRect = CGRect(
    x: cgRect.minX,
    y: CGFloat(frame.height) - cgRect.maxY,   // top-down → bottom-up
    width:  cgRect.width,
    height: cgRect.height
)
```

### P-202 · `NSEvent.mouseLocation` 是全局坐标，左下原点；屏幕坐标是相对当前 NSScreen 的
**症状**：lens 跟手时位置永远偏移。
**正确做法**：转 view 内坐标时减去 `viewScreen.frame.origin`：
```swift
cursorPos = NSPoint(
    x: mouseGlobal.x - viewScreen.frame.origin.x,
    y: mouseGlobal.y - viewScreen.frame.origin.y
)
```

---

## §4 权限 & 签名

### P-301 · `codesign --sign -` ad-hoc 签名 → 每次重 build 都会重新弹权限
**症状**：每次 `bash build_app.sh` 后启动 app，TCC 都重新弹一次「屏幕录制」「辅助功能」授权框。
**根因**：ad-hoc 签名每次生成新 cdhash，TCC 数据库以为是全新 app。
**正确做法**：用稳定本地自签证书 `QuickHighlightDevCert`：
```bash
codesign --force --deep --sign QuickHighlightDevCert /Applications/快捷高光.app
```
build_app.sh 里 `ensure_signing_identity()` 一次性创建并复用。

### P-302 · `/Applications` 和桌面快捷方式必须共享同一 cdhash
**症状**：双击桌面快捷方式弹一次权限，再双击 /Applications 又弹一次。
**正确做法**：用同一证书签名 → `cp -R /Applications/X.app ~/Desktop/X.app`，两份共享 cdhash，TCC 只记一条授权。**不要**用 symlink（某些 macOS 版本 Finder 不刷图标）。

### P-303 · 别忘了清 quarantine 属性
```bash
xattr -cr "$APP_PATH"
xattr -dr com.apple.provenance "$APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH"
```
否则跨设备/下载来的 .app 启动会被 Gatekeeper 拦截。

---

## §5 SwiftUI 绑定

### P-401 · `@State` 初值用 `ProcessInfo` 必须用闭包形式
**症状**：环境变量预选 tab 不生效，永远是默认值。
**正确做法**：
```swift
@State private var selection: Int = {
    switch ProcessInfo.processInfo.environment["QH_TAB"] {
    case "general": return 0
    case "hotkey":  return 1
    default:        return 0
    }
}()
```
不要写 `@State private var selection = ProcessInfo.processInfo.environment["QH_TAB"] == "hotkey" ? 1 : 0` —— 部分 Swift 版本会报「无法在 property initializer 内访问类型成员」。

### P-402 · `TabView` 的 `tag` 类型必须和 `selection` 完全一致
**症状**：点击 tab 没反应，或预选 tab 失败。
**正确做法**：`@State selection: Int` + `.tag(0)` `.tag(1)` `.tag(2)` 全部 Int。如果 selection 是 String 但 tag 给 Int，绑定会失效。

---

## SOP：写代码前的自检清单

每次准备改 `OverlayView.swift` / `ScreenCapturer.swift` / `build_app.sh` 之前，对照过一遍：

- [ ] 即将动的代码区是否在本文档某条 PITFALL 范围内？
- [ ] 我有没有打算重新引入手动 Y 翻转？（看到 `scaleBy(x:1, y:-1)` 警觉）
- [ ] 我有没有打算用 `CGImage.cropping(to:)` 直接喂渲染？
- [ ] 改完后 zoom 数学是否还能通过：`captureSize_pt = lensSize_pt / zoom`?
- [ ] 改完后是否还能通过 [FEATURES.md](FEATURES.md) 全部 ✅ 项？

**任何一条没过，停下来想清楚再写。**
