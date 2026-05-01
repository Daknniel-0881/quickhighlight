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

final class OverlayView: NSView {
    /// 鼠标在 view 内的坐标（左下原点，与 isFlipped=false 一致）
    private var cursorPos: NSPoint = .zero
    /// 直接缓存 cropped CGImage —— 之前用 NSImage(cgImage:size:) + draw(in:from:.zero) 在某些
    /// 缩放场景下不会按 size 真正缩放（NSImage 用源 CGImage 像素尺寸而忽略 size 参数），
    /// 这是「放大倍率不生效」的根因。改用 ctx.draw(cgImage:in:) 由 CGContext 自己缩放。
    private var capturedCGImage: CGImage?

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
        guard !cropRect.isEmpty, let cropped = frame.cropping(to: cropRect) else {
            capturedCGImage = nil
            needsDisplay = true
            return
        }

        // 锐化（仅 zoom > 1.0 且用户未关）—— CIUnsharpMask 抵消上采样模糊
        // 经验值：radius 1.2 / intensity 0.5 在 60fps 下不卡，文字边缘明显锐
        if SettingsStore.shared.sharpenEnabled, z > 1.05 {
            let ci = CIImage(cgImage: cropped)
            let f = CIFilter.unsharpMask()
            f.inputImage = ci
            f.radius = 1.2
            f.intensity = 0.5
            if let out = f.outputImage,
               let sharpened = sharpenCIContext.createCGImage(out, from: ci.extent) {
                capturedCGImage = sharpened
                needsDisplay = true
                return
            }
        }
        capturedCGImage = cropped
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

        // 2) 内部放大画面 — 改用经典 transform + ctx.draw 路径，确保 zoom 数学稳定。
        //    之前 ctx.draw(img, in: circleRect) 在某些 macOS 版本下，对 CGImage 的目标矩形
        //    缩放可能不按 src→dst 像素比线性插值，导致 zoom 视觉效果不明显。
        //    手动 translate + scale 后用 (0,0,w,h) 绘制，路径无歧义。
        if let img = capturedCGImage {
            ctx.saveGState()
            ctx.addPath(innerPath)
            ctx.clip()
            ctx.interpolationQuality = .high
            // 把坐标原点移到 circleRect 左上，然后 y 轴翻转（CGImage 是 top-down 像素，
            // 当前 ctx 是 y-up），这样 ctx.draw(img, in: 0,0,w,h) 会精确缩放到 circleRect
            ctx.translateBy(x: circleRect.minX, y: circleRect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: circleRect.width, height: circleRect.height))
            ctx.restoreGState()
        }

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
        if SettingsStore.shared.showZoomLabel {
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
    }
}
