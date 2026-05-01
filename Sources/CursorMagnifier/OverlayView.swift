import Cocoa
import CoreImage
import CoreImage.CIFilterBuiltins

/// CIContext 单例 — 每帧重建会很重；锐化路径在主线程跑，需要稳定上下文复用
private let sharpenCIContext: CIContext = {
    CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])
}()

/// 编译时 BUILD ID — 每次重 build 改一次，肉眼验证「跑的是不是新 binary」
/// 诊断模式下会画在 lens 下方
private let kBuildID = "v8-2026-05-01-ux"

/// 诊断模式开关 — 默认 OFF。开发期需要肉眼诊断时用 QH_DIAG=1 启动。
/// 用户体验铁律：默认状态下 lens 周边不允许出现任何调试文字/数字。
private let kDiagMode = ProcessInfo.processInfo.environment["QH_DIAG"] == "1"

final class OverlayView: NSView {
    /// 鼠标在 view 内的坐标（左下原点，与 isFlipped=false 一致）
    private var cursorPos: NSPoint = .zero
    /// 直接缓存 cropped CGImage —— 之前用 NSImage(cgImage:size:) + draw(in:from:.zero) 在某些
    /// 缩放场景下不会按 size 真正缩放（NSImage 用源 CGImage 像素尺寸而忽略 size 参数），
    /// 这是「放大倍率不生效」的根因。改用 ctx.draw(cgImage:in:) 由 CGContext 自己缩放。
    private var capturedCGImage: CGImage?

    /// 诊断模式快照：最近一次 updateForCursor() 算出的关键数据
    /// 这些数据画在 lens 下方，肉眼验证「数学是不是对的、binary 是不是新的」
    private struct DiagSnapshot {
        var frameSize: CGSize = .zero
        var pointSize: CGSize = .zero
        var zoom: CGFloat = 0
        var innerSize: CGSize = .zero
        var cropPxSize: CGSize = .zero
        var capturedSize: CGSize = .zero  // 物化后实际像素尺寸
    }
    private var diag = DiagSnapshot()

    private var radius: CGFloat { CGFloat(SettingsStore.shared.radius) }
    private var rectWidth: CGFloat { CGFloat(SettingsStore.shared.rectWidth) }
    private var rectHeight: CGFloat { CGFloat(SettingsStore.shared.rectHeight) }
    private var zoom: CGFloat { CGFloat(SettingsStore.shared.zoom) }
    private var dimAlpha: CGFloat { CGFloat(SettingsStore.shared.dimAlpha) }
    private var showRing: Bool { SettingsStore.shared.showRing }
    private var shape: MagnifierShape { SettingsStore.shared.shape }

    /// 当前形状的内部矩形点尺寸（圆形 = 直径方阵；圆角矩形 = 长×宽）
    private var innerSize: CGSize {
        switch shape {
        case .circle:       return CGSize(width: radius * 2, height: radius * 2)
        case .roundedRect:  return CGSize(width: rectWidth, height: rectHeight)
        }
    }

    /// 当前形状的几何路径（圆形 / 5px 圆角矩形）—— 暗化挖洞、画面 clip、白色高光全用它
    private func shapePath(in rect: CGRect) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRect:
            return CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        }
    }

    override var isFlipped: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateForCursor() {
        let mouseGlobal = NSEvent.mouseLocation  // AppKit 全局坐标，主屏左下原点

        let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseGlobal, $0.frame, false) })
            ?? NSScreen.main
        guard let mouseScreen else { return }

        // 主屏（含原点）—— SCStream 抓的是主屏，坐标系左上原点
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? mouseScreen
        let primaryHeight = primary.frame.height

        // view 内坐标（绘制 cursor 圈用）
        let viewScreen = window?.screen ?? mouseScreen
        cursorPos = NSPoint(
            x: mouseGlobal.x - viewScreen.frame.origin.x,
            y: mouseGlobal.y - viewScreen.frame.origin.y
        )

        // 鼠标在副屏时：当前 SCStream 只抓主屏，crop 不出有效内容 — 直接清空
        guard mouseScreen.frame.origin == .zero else {
            capturedCGImage = nil
            needsDisplay = true
            return
        }

        guard let frame = ScreenCapturer.shared.latestFrame else {
            capturedCGImage = nil
            needsDisplay = true
            return
        }

        // 主屏点尺寸 → CGImage 像素尺寸的缩放
        let pointSize = ScreenCapturer.shared.displayPointSize
        guard pointSize.width > 0, pointSize.height > 0 else {
            capturedCGImage = nil
            needsDisplay = true
            return
        }
        let scaleX = CGFloat(frame.width) / pointSize.width
        let scaleY = CGFloat(frame.height) / pointSize.height

        // 鼠标在主屏点坐标（左上原点）
        let cursorPxX = mouseGlobal.x * scaleX
        let cursorPxY = (primaryHeight - mouseGlobal.y) * scaleY

        // crop 区域：内部尺寸 / zoom 倍率得"原始尺寸"，乘像素比得像素尺寸
        let z = max(zoom, 0.01)
        let inner = innerSize
        let captureSizePtW = inner.width / z
        let captureSizePtH = inner.height / z
        let captureSizePxW = captureSizePtW * scaleX
        let captureSizePxH = captureSizePtH * scaleY

        var cropRect = CGRect(
            x: cursorPxX - captureSizePxW / 2,
            y: cursorPxY - captureSizePxH / 2,
            width: captureSizePxW,
            height: captureSizePxH
        ).integral

        // 边缘 clamp，避免靠近角落时 cropping 返回 nil
        let frameBounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        cropRect = cropRect.intersection(frameBounds)
        guard !cropRect.isEmpty else {
            capturedCGImage = nil
            needsDisplay = true
            return
        }

        // 关键修复：不用 frame.cropping(to:) ——它返回的 CGImage 是「父帧 buffer 的窗口视图」，
        // 在 ctx.draw(in:rect) 渲染路径上有些 macOS/驱动版本会渲染父帧而不是裁剪区域，
        // 导致看上去 zoom 不生效（用户自始至终都在看 1920×1080 整屏画面被缩到 lens 里）。
        //
        // 改用 CIImage.cropped + CIContext.createCGImage，强制把裁剪区域 render 成一张
        // 独立、自洽的 CGImage（standalone bitmap），彻底解耦父帧。
        // 注意：CIImage 用左下原点，cropRect 此时是左上原点（CGImage 坐标系），需翻 Y。
        let fullCI = CIImage(cgImage: frame)
        let ciCropRect = CGRect(
            x: cropRect.minX,
            y: CGFloat(frame.height) - cropRect.maxY,  // CGImage top-down → CIImage bottom-up
            width: cropRect.width,
            height: cropRect.height
        )
        var processedCI = fullCI.cropped(to: ciCropRect)

        // 锐化（zoom > 1.0 且用户未关）：CIUnsharpMask 抵消上采样模糊
        // 注意：zoom 越高、crop 区域越小，单位像素被放大得越厉害，需要越强的锐化才能视觉可见。
        // 之前 radius=1.2/intensity=0.5 在 zoom=1.5 的小 crop（68px 量级）上几乎看不出 ——
        // 锐化效果与 (kernel_radius / image_dimension) 成比例，crop 越小绝对像素越少，必须放大参数。
        if SettingsStore.shared.sharpenEnabled, z > 1.05 {
            let f = CIFilter.unsharpMask()
            f.inputImage = processedCI
            // radius 跟 zoom 走：zoom 1×~6× → radius 1.5~3.5
            f.radius = Float(min(3.5, 1.0 + z * 0.45))
            // intensity 也跟 zoom 走：zoom 1×~6× → intensity 0.6~1.2
            f.intensity = Float(min(1.2, 0.4 + z * 0.15))
            if let out = f.outputImage {
                processedCI = out
            }
        }

        guard let materialized = sharpenCIContext.createCGImage(processedCI, from: ciCropRect) else {
            capturedCGImage = nil
            needsDisplay = true
            return
        }
        capturedCGImage = materialized

        if kDiagMode {
            diag = DiagSnapshot(
                frameSize: CGSize(width: frame.width, height: frame.height),
                pointSize: pointSize,
                zoom: z,
                innerSize: inner,
                cropPxSize: cropRect.size,
                capturedSize: CGSize(width: materialized.width, height: materialized.height)
            )
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inner = innerSize
        let circleRect = CGRect(
            x: cursorPos.x - inner.width / 2,
            y: cursorPos.y - inner.height / 2,
            width: inner.width,
            height: inner.height
        )

        let innerPath = shapePath(in: circleRect)

        // 1) 暗化外圈（甜甜圈：full bounds 减去内部形状，用 even-odd 填充一次性搞定）
        let donut = CGMutablePath()
        donut.addRect(bounds)
        donut.addPath(innerPath)
        ctx.addPath(donut)
        ctx.setFillColor(CGColor(gray: 0, alpha: dimAlpha))
        ctx.fillPath(using: .evenOdd)

        // 2) 内部放大画面 —— 直接 ctx.draw(img, in: circleRect)
        //
        // 踩坑记录：之前为了"修 zoom 不生效"加了一段手动 translate + scaleBy(x:1, y:-1)，
        // 注释自圆其说为「CGImage top-down vs ctx y-up 需要翻 Y」。这是误解 ——
        // AppKit NSView (isFlipped=false) 的 CGContext 在 ctx.draw(cgImage, in: rect) 时
        // **已经会自动正向映射 top-down CGImage 到 y-up rect**，不需要也不能再手动翻。
        // 手动加了那次 scaleBy(-1) 后，画面确实「精确缩放到 circleRect」了，但同时把图像
        // 上下颠倒了 —— 用户看到的就是倒立的桌面画面，看着很假。
        //
        // 修复：删掉手动翻转，直接 draw 进 circleRect。zoom 数学已经在 updateForCursor()
        // 那一层算好（用 captureSizePt = innerSize / zoom 决定 crop 大小，再用 createCGImage
        // 物化），lens 区域只负责把这张「已经是被裁好的小图」按 lens 几何拉伸显示即可。
        if let img = capturedCGImage {
            ctx.saveGState()
            ctx.addPath(innerPath)
            ctx.clip()
            ctx.interpolationQuality = .high
            ctx.draw(img, in: circleRect)
            ctx.restoreGState()
        }
        // 用户体验铁律：抓帧失败时绝不在 lens 内画红字/警告/弹窗。
        // lens 内部保持透明（露出真实桌面 1× 画面）+ donut 暗化 + ring 高光，
        // 用户依然能用激活键标记鼠标位置。抓帧链路恢复后会自动显示放大画面。
        // 状态提示只通过菜单栏图标做轻量呈现（plus.magnifyingglass ↔ magnifyingglass）。

        // 3) 白色高光边框
        if showRing {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
            ctx.setLineWidth(2)
            ctx.addPath(innerPath)
            ctx.strokePath()

            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
            ctx.setLineWidth(1)
            ctx.addPath(shapePath(in: circleRect.insetBy(dx: -1.5, dy: -1.5)))
            ctx.strokePath()
        }

        // 4) 当前放大倍率小标签（用户验证 zoom 是否生效）
        if SettingsStore.shared.showZoomLabel && !kDiagMode {
            let label = String(format: "%.1f×", zoom)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black.withAlphaComponent(0.85),
                .strokeWidth: -3.5
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let strSize = str.size()
            let labelOrigin = NSPoint(
                x: cursorPos.x - strSize.width / 2,
                y: circleRect.minY - strSize.height - 6
            )
            str.draw(at: labelOrigin)
        }

        // 5) 诊断模式：lens 下方画完整诊断标签（QH_DIAG=1 启动）
        //    这个标签让肉眼直接验证：跑的是不是新 binary、zoom 数学对不对、物化是否成功
        if kDiagMode {
            // 物化尺寸 vs lens 几何尺寸的视觉放大倍率
            let visualZoomX = diag.capturedSize.width > 0
                ? circleRect.width / diag.capturedSize.width : 0
            let verdict: String = {
                if diag.capturedSize == .zero { return "✗ 抓帧失败" }
                let expectedSrcW = diag.innerSize.width / max(diag.zoom, 0.01)
                if abs(diag.cropPxSize.width - expectedSrcW) > expectedSrcW * 0.2 {
                    return "✗ crop 尺寸异常"
                }
                if abs(visualZoomX - diag.zoom) > 0.5 {
                    return "✗ 视觉倍率 ≠ zoom"
                }
                return "✓ 放大正常"
            }()
            let lines = [
                "BUILD \(kBuildID)",
                String(format: "zoom=%.1f×  inner=%.0f×%.0f pt", diag.zoom,
                       diag.innerSize.width, diag.innerSize.height),
                String(format: "crop=%.0f×%.0f px  src=%d×%d px",
                       diag.cropPxSize.width, diag.cropPxSize.height,
                       Int(diag.capturedSize.width), Int(diag.capturedSize.height)),
                String(format: "dst=%.0f×%.0f pt  视觉≈%.1f×",
                       circleRect.width, circleRect.height, visualZoomX),
                verdict
            ]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black.withAlphaComponent(0.9),
                .strokeWidth: -3.5
            ]
            var y = circleRect.minY - 14
            for line in lines {
                let str = NSAttributedString(string: line, attributes: attrs)
                let w = str.size().width
                let origin = NSPoint(x: cursorPos.x - w / 2, y: y)
                str.draw(at: origin)
                y -= 14
            }
        }
    }
}
