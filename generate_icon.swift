#!/usr/bin/env swift
// 程序化生成"圆环聚焦放大"图标 — 多尺寸 PNG → AppIcon.iconset/
import AppKit
import CoreGraphics

let outDir = "Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

struct IconEntry { let name: String; let px: Int }
let entries: [IconEntry] = [
    .init(name: "icon_16x16.png", px: 16),
    .init(name: "icon_16x16@2x.png", px: 32),
    .init(name: "icon_32x32.png", px: 32),
    .init(name: "icon_32x32@2x.png", px: 64),
    .init(name: "icon_128x128.png", px: 128),
    .init(name: "icon_128x128@2x.png", px: 256),
    .init(name: "icon_256x256.png", px: 256),
    .init(name: "icon_256x256@2x.png", px: 512),
    .init(name: "icon_512x512.png", px: 512),
    .init(name: "icon_512x512@2x.png", px: 1024)
]

func renderIcon(px: Int) -> Data? {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let inset = s * 0.06           // App icon 留白
    let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerR = bgRect.width * 0.225   // Big Sur squircle 圆角

    // 1) 圆角矩形背景 + 蓝紫渐变（macOS 风格底色）
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil))
    ctx.clip()

    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.36, green: 0.55, blue: 0.98, alpha: 1.0),  // 顶部亮蓝
            CGColor(red: 0.20, green: 0.30, blue: 0.78, alpha: 1.0)   // 底部深蓝
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: bgRect.midX, y: bgRect.maxY),
        end: CGPoint(x: bgRect.midX, y: bgRect.minY),
        options: []
    )

    // 2) 外圈暗化（径向渐变模拟 dim 效果）
    let center = CGPoint(x: s / 2, y: s / 2)
    let dimGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        ] as CFArray,
        locations: [0.35, 1]
    )!
    ctx.drawRadialGradient(
        dimGrad,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: s * 0.55,
        options: []
    )

    // 3) 放大圆内部"亮区"（高光球体感）
    let lensR = s * 0.27
    let lensRect = CGRect(
        x: center.x - lensR,
        y: center.y - lensR,
        width: lensR * 2,
        height: lensR * 2
    )
    ctx.saveGState()
    ctx.addPath(CGPath(ellipseIn: lensRect, transform: nil))
    ctx.clip()
    let brightGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
            CGColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.55),
            CGColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 0.20)
        ] as CFArray,
        locations: [0, 0.6, 1]
    )!
    ctx.drawRadialGradient(
        brightGrad,
        startCenter: CGPoint(x: center.x - lensR * 0.2, y: center.y + lensR * 0.2),
        startRadius: 0,
        endCenter: center,
        endRadius: lensR,
        options: []
    )
    ctx.restoreGState()

    // 4) 白色高光圆环（主体）
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(s * 0.038)
    ctx.strokeEllipse(in: lensRect)

    // 5) 圆环内侧细暗线（增加深度）
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.setLineWidth(s * 0.014)
    ctx.strokeEllipse(in: lensRect.insetBy(dx: s * 0.024, dy: s * 0.024))

    // 6) 中心十字准星
    let crossLen = s * 0.055
    let crossWidth = s * 0.018
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(crossWidth)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: center.x, y: center.y - crossLen))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + crossLen))
    ctx.move(to: CGPoint(x: center.x - crossLen, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x + crossLen, y: center.y))
    ctx.strokePath()

    // 7) 中心高光小点
    let dotR = s * 0.022
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))

    ctx.restoreGState()  // bg clip

    // 输出 PNG
    guard let cgImg = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImg)
    return rep.representation(using: .png, properties: [:])
}

for entry in entries {
    guard let data = renderIcon(px: entry.px) else {
        FileHandle.standardError.write(Data("✗ 渲染失败: \(entry.name)\n".utf8))
        continue
    }
    let url = URL(fileURLWithPath: "\(outDir)/\(entry.name)")
    try? data.write(to: url)
    print("✓ \(entry.name) (\(entry.px)×\(entry.px))")
}
print("→ 全部完成，下一步：iconutil -c icns \(outDir) -o Resources/AppIcon.icns")
