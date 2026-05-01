import Cocoa

/// 把 macOS keyCode + modifierFlags 渲染成 "⌃⌥S" 这样的快捷键文字
enum KeyDisplay {
    /// 常用键 keyCode → 显示名映射（覆盖字母 / 数字 / 功能键 / 方向键 / 常用编辑键）
    static let keyCodeMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9",
        26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        76: "Enter", 117: "Fwd Del", 115: "Home", 116: "Page Up", 119: "End", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func name(for keyCode: UInt16) -> String {
        keyCodeMap[keyCode] ?? "Key\(keyCode)"
    }

    /// "⌃⌥S" 形式
    static func chordText(keyCode: Int, modifiers: UInt) -> String {
        guard keyCode >= 0 else { return "未设置" }
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += name(for: UInt16(keyCode))
        return s
    }

    /// 设备级 mask（左右修饰键判断）→ HotkeyOption
    static func detectHotkey(deviceMask raw: UInt) -> HotkeyOption? {
        for opt in HotkeyOption.allCases where (raw & opt.deviceMask) != 0 {
            return opt
        }
        return nil
    }
}
