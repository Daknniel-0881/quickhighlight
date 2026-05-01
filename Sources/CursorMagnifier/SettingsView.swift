import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var savedFlash = false
    @State private var persistentPreviewOn = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            hotkeyTab
                .tabItem { Label("快捷键", systemImage: "command") }
            magnifierTab
                .tabItem { Label("放大镜", systemImage: "plus.magnifyingglass") }
        }
        .frame(width: 520, height: 540)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("开机自动启动", isOn: $store.launchAtLogin)
                Toggle("显示白色高光圆环", isOn: $store.showRing)
            } footer: {
                Text("开机自启需要将 App 安装到「应用程序」目录，并在系统设置 → 通用 → 登录项中授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击下方输入框，然后按一下你想用的修饰键即可设置：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ModifierHotkeyRecorder(store: store)
                    DisclosureGroup("或从列表选择") {
                        Picker("", selection: $store.hotkey) {
                            ForEach(HotkeyOption.allCases) { opt in
                                Text(opt.displayName).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .font(.caption)
                }
            } header: {
                Text("激活放大镜")
            } footer: {
                Text("按住激活键 → 放大镜出现，松开消失。激活键必须是单个修饰键（⌥ ⇧ ⌃ ⌘ Fn），不支持组合键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击下方输入框，按下你想用的组合键（必须含修饰键，如 ⌃⌥S）：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ChordHotkeyRecorder(store: store)
                }
            } header: {
                Text("切换形状（圆形 / 圆角矩形）")
            } footer: {
                Text("按下组合键 → 立即在圆形与圆角矩形之间切换，无需打开设置面板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var magnifierTab: some View {
        Form {
            Section("实时预览") {
                MagnifierPreview(store: store)
                    .frame(height: 180)
            }
            Section("外观") {
                Picker("形状", selection: $store.shape) {
                    ForEach(MagnifierShape.allCases) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                if store.shape == .circle {
                    LabeledSlider(
                        title: "尺寸（半径）",
                        valueText: "\(Int(store.radius)) px",
                        value: $store.radius,
                        range: 50...400,
                        step: 5
                    )
                } else {
                    LabeledSlider(
                        title: "宽度",
                        valueText: "\(Int(store.rectWidth)) px",
                        value: $store.rectWidth,
                        range: 100...800,
                        step: 10
                    )
                    LabeledSlider(
                        title: "高度",
                        valueText: "\(Int(store.rectHeight)) px",
                        value: $store.rectHeight,
                        range: 30...600,
                        step: 5
                    )
                }
                LabeledSlider(
                    title: "放大倍率",
                    valueText: String(format: "%.1f×", store.zoom),
                    value: $store.zoom,
                    range: 1.0...6.0,
                    step: 0.1
                )
                LabeledSlider(
                    title: "外圈暗度",
                    valueText: "\(Int(store.dimAlpha * 100))%",
                    value: $store.dimAlpha,
                    range: 0...0.9,
                    step: 0.05
                )
            }
            Section {
                Toggle("锐化（抗模糊）", isOn: $store.sharpenEnabled)
                    .help("CIUnsharpMask 锐化，仅在放大倍率 > 1.0 时生效，让文字边缘更清晰")
                Toggle("显示当前放大倍率", isOn: $store.showZoomLabel)
                    .help("在放大圈下方显示 1.5× / 4.0× 这样的小标识，方便对比参数（录屏时建议关闭）")
            } header: {
                Text("画面增强")
            }
            Section {
                HStack {
                    Button("恢复默认") { store.resetMagnifier() }
                    Spacer()
                    Button(persistentPreviewOn ? "停止持续预览" : "持续预览") {
                        UserDefaults.standard.synchronize()
                        NotificationCenter.default.post(
                            name: .quickHighlightTogglePersistentPreview,
                            object: nil
                        )
                    }
                    .help("开启后放大圈一直显示，可以拖滑块实时对比效果。再点击或退出 App 时关闭。")
                    Button("瞬时测试 (1.5s)") {
                        UserDefaults.standard.synchronize()
                        NotificationCenter.default.post(
                            name: .quickHighlightPreviewOverlay,
                            object: nil
                        )
                    }
                    .help("立即在鼠标位置显示放大圈 1.5 秒")
                    Button("保存") {
                        UserDefaults.standard.synchronize()
                        savedFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            savedFlash = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } footer: {
                if persistentPreviewOn {
                    Text("● 持续预览中 — 把鼠标移到任意窗口看效果，拖滑块即时对比。完成后再点一次按钮关闭。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if savedFlash {
                    Text("✓ 已保存，参数立即生效")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("拖动滑块时已自动保存。开启「持续预览」可一边调一边看真实效果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: .quickHighlightPersistentPreviewStateChanged)) { note in
            if let on = note.userInfo?["on"] as? Bool {
                persistentPreviewOn = on
            }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct MagnifierPreview: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxW = size.width - 12
            let maxH = size.height - 12
            // 把真实尺寸按 0.5 比例映射到预览画布，并夹到边界
            let innerW: CGFloat = {
                switch store.shape {
                case .circle:       return min(CGFloat(store.radius) * 2 * 0.5, maxW, maxH)
                case .roundedRect:  return min(CGFloat(store.rectWidth) * 0.5, maxW)
                }
            }()
            let innerH: CGFloat = {
                switch store.shape {
                case .circle:       return innerW
                case .roundedRect:  return min(CGFloat(store.rectHeight) * 0.5, maxH)
                }
            }()
            let circleRect = CGRect(
                x: center.x - innerW / 2, y: center.y - innerH / 2,
                width: innerW, height: innerH
            )

            drawTestPattern(ctx: ctx, size: size)

            let shapeBuilder: (CGRect) -> Path = { rect in
                switch store.shape {
                case .circle:
                    return Path(ellipseIn: rect)
                case .roundedRect:
                    return Path(roundedRect: rect, cornerRadius: 8)
                }
            }

            var donut = Path()
            donut.addRect(CGRect(origin: .zero, size: size))
            donut.addPath(shapeBuilder(circleRect))
            ctx.fill(
                donut,
                with: .color(.black.opacity(store.dimAlpha)),
                style: FillStyle(eoFill: true)
            )

            ctx.drawLayer { layer in
                layer.clip(to: shapeBuilder(circleRect))
                layer.translateBy(x: center.x, y: center.y)
                layer.scaleBy(x: store.zoom, y: store.zoom)
                layer.translateBy(x: -center.x, y: -center.y)
                drawTestPattern(ctx: layer, size: size)
            }

            if store.showRing {
                ctx.stroke(
                    shapeBuilder(circleRect),
                    with: .color(.white.opacity(0.9)),
                    lineWidth: 2
                )
                ctx.stroke(
                    shapeBuilder(circleRect.insetBy(dx: -1.5, dy: -1.5)),
                    with: .color(.black.opacity(0.35)),
                    lineWidth: 1
                )
            }

            let arrow = Path { p in
                p.move(to: CGPoint(x: center.x, y: center.y - 6))
                p.addLine(to: CGPoint(x: center.x, y: center.y + 6))
                p.move(to: CGPoint(x: center.x - 6, y: center.y))
                p.addLine(to: CGPoint(x: center.x + 6, y: center.y))
            }
            ctx.stroke(arrow, with: .color(.white), lineWidth: 1.5)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.95, blue: 0.97),
                         Color(red: 0.85, green: 0.86, blue: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    /// 预览背景：彩色色块网格 + 文字 + 细线，用于直观感受放大效果
    private func drawTestPattern(ctx: GraphicsContext, size: CGSize) {
        let cols = 10
        let rows = 6
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let hue = Double(col) / Double(cols)
                let bri = 0.92 - Double(row) * 0.05
                let rect = CGRect(
                    x: CGFloat(col) * cellW,
                    y: CGFloat(row) * cellH,
                    width: cellW, height: cellH
                )
                ctx.fill(
                    Path(rect),
                    with: .color(Color(hue: hue, saturation: 0.30, brightness: bri))
                )
            }
        }
        // 细线网格（为放大后的清晰度提供参考）
        for x in stride(from: 0, to: size.width, by: 16) {
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                },
                with: .color(.black.opacity(0.06)),
                lineWidth: 0.5
            )
        }
        for y in stride(from: 0, to: size.height, by: 16) {
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                },
                with: .color(.black.opacity(0.06)),
                lineWidth: 0.5
            )
        }
        ctx.draw(
            Text("快捷高光 · Aa文字 12345")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.75)),
            at: CGPoint(x: size.width * 0.5, y: size.height * 0.45),
            anchor: .center
        )
        ctx.draw(
            Text("Detail Preview · 细节预览")
                .font(.system(size: 9))
                .foregroundColor(.black.opacity(0.55)),
            at: CGPoint(x: size.width * 0.5, y: size.height * 0.62),
            anchor: .center
        )
    }
}
