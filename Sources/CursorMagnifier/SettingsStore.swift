import Foundation
import Combine

enum MagnifierShape: String, CaseIterable, Identifiable {
    case circle
    case roundedRect

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .circle:       return "圆形"
        case .roundedRect:  return "圆角矩形"
        }
    }
}

enum HotkeyOption: String, CaseIterable, Identifiable {
    case leftOption, rightOption
    case leftShift, rightShift
    case leftControl, rightControl
    case leftCommand, rightCommand
    case fn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftOption:   return "左 Option (⌥)"
        case .rightOption:  return "右 Option (⌥)"
        case .leftShift:    return "左 Shift (⇧)"
        case .rightShift:   return "右 Shift (⇧)"
        case .leftControl:  return "左 Control (⌃)"
        case .rightControl: return "右 Control (⌃)"
        case .leftCommand:  return "左 Command (⌘)"
        case .rightCommand: return "右 Command (⌘)"
        case .fn:           return "Fn / 地球键"
        }
    }

    /// IOKit device-side modifier mask（与 NSEvent.modifierFlags.rawValue 按位与即可判断）
    var deviceMask: UInt {
        switch self {
        case .leftControl:  return 0x000001
        case .leftShift:    return 0x000002
        case .rightShift:   return 0x000004
        case .leftCommand:  return 0x000008
        case .rightCommand: return 0x000010
        case .leftOption:   return 0x000020
        case .rightOption:  return 0x000040
        case .rightControl: return 0x002000
        case .fn:           return 0x800000
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var hotkey: HotkeyOption {
        didSet { defaults.set(hotkey.rawValue, forKey: Keys.hotkey) }
    }
    @Published var radius: Double {
        didSet { defaults.set(radius, forKey: Keys.radius) }
    }
    /// 圆角矩形宽度（点）。仅在 shape == .roundedRect 时生效
    @Published var rectWidth: Double {
        didSet { defaults.set(rectWidth, forKey: Keys.rectWidth) }
    }
    /// 圆角矩形高度（点）。仅在 shape == .roundedRect 时生效
    @Published var rectHeight: Double {
        didSet { defaults.set(rectHeight, forKey: Keys.rectHeight) }
    }
    @Published var zoom: Double {
        didSet { defaults.set(zoom, forKey: Keys.zoom) }
    }
    @Published var dimAlpha: Double {
        didSet { defaults.set(dimAlpha, forKey: Keys.dimAlpha) }
    }
    @Published var showRing: Bool {
        didSet { defaults.set(showRing, forKey: Keys.showRing) }
    }
    @Published var shape: MagnifierShape {
        didSet { defaults.set(shape.rawValue, forKey: Keys.shape) }
    }
    /// 切换形状的组合键 keyCode（-1 表示未设置）
    @Published var toggleShapeKeyCode: Int {
        didSet { defaults.set(toggleShapeKeyCode, forKey: Keys.toggleShapeKeyCode) }
    }
    /// 切换形状的组合键修饰键（NSEvent.ModifierFlags.deviceIndependentFlagsMask raw）
    @Published var toggleShapeModifiers: UInt {
        didSet { defaults.set(toggleShapeModifiers, forKey: Keys.toggleShapeModifiers) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLogin.set(launchAtLogin)
        }
    }

    private enum Keys {
        static let hotkey = "hotkey"
        static let radius = "radius"
        static let rectWidth = "rectWidth"
        static let rectHeight = "rectHeight"
        static let zoom = "zoom"
        static let dimAlpha = "dimAlpha"
        static let showRing = "showRing"
        static let shape = "shape"
        static let toggleShapeKeyCode = "toggleShapeKeyCode"
        static let toggleShapeModifiers = "toggleShapeModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let settingsVersion = "settingsVersion"
    }

    /// 当前 schema 版本。每次默认值/字段语义变更时 +1，触发一次性迁移。
    private static let currentVersion = 4

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Keys.hotkey: HotkeyOption.leftOption.rawValue,
            Keys.radius: 150.0,
            Keys.rectWidth: 360.0,
            Keys.rectHeight: 220.0,
            Keys.zoom: 1.5,
            Keys.dimAlpha: 0.6,
            Keys.showRing: true,
            Keys.shape: MagnifierShape.circle.rawValue,
            Keys.toggleShapeKeyCode: -1,            // 默认未设置
            Keys.toggleShapeModifiers: 0,
            Keys.launchAtLogin: false,
            Keys.settingsVersion: 0
        ])

        // 版本迁移：把"超过当前默认上限/老版本残留值"统一拉回新默认
        let storedVersion = defaults.integer(forKey: Keys.settingsVersion)
        if storedVersion < Self.currentVersion {
            // v1 → v2：默认 zoom 从 2.5 调回 1.5。如果用户保留了 2.5（最常见的老默认），重置；自定义值（!=2.5）保留
            if abs(defaults.double(forKey: Keys.zoom) - 2.5) < 0.01 {
                defaults.set(1.5, forKey: Keys.zoom)
            }
            defaults.set(Self.currentVersion, forKey: Keys.settingsVersion)
        }

        let raw = defaults.string(forKey: Keys.hotkey) ?? HotkeyOption.leftOption.rawValue
        self.hotkey = HotkeyOption(rawValue: raw) ?? .leftOption
        self.radius = defaults.double(forKey: Keys.radius)
        self.rectWidth = defaults.double(forKey: Keys.rectWidth)
        self.rectHeight = defaults.double(forKey: Keys.rectHeight)
        self.zoom = defaults.double(forKey: Keys.zoom)
        self.dimAlpha = defaults.double(forKey: Keys.dimAlpha)
        self.showRing = defaults.bool(forKey: Keys.showRing)
        let shapeRaw = defaults.string(forKey: Keys.shape) ?? MagnifierShape.circle.rawValue
        self.shape = MagnifierShape(rawValue: shapeRaw) ?? .circle
        self.toggleShapeKeyCode = defaults.integer(forKey: Keys.toggleShapeKeyCode)
        self.toggleShapeModifiers = UInt(defaults.integer(forKey: Keys.toggleShapeModifiers))
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    func resetMagnifier() {
        radius = 150
        rectWidth = 360
        rectHeight = 220
        zoom = 1.5
        dimAlpha = 0.6
        showRing = true
        shape = .circle
    }
}
