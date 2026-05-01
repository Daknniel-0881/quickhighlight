import Cocoa

final class HotkeyMonitor {
    var onStateChange: ((Bool) -> Void)?
    /// 切换形状组合键被按下时触发
    var onToggleShape: (() -> Void)?

    private var flagsGlobal: Any?
    private var flagsLocal: Any?
    private var keyDownGlobal: Any?
    private var keyDownLocal: Any?
    private var lastState = false
    private let store = SettingsStore.shared

    func start() {
        flagsGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        flagsLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
            return e
        }
        keyDownGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            _ = self?.handleKeyDown(e)
        }
        keyDownLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            // 在自家窗口里按下我们的组合键，吞掉以避免传到 Settings 窗口的输入控件
            (self?.handleKeyDown(e) ?? false) ? nil : e
        }
    }

    func stop() {
        if let g = flagsGlobal { NSEvent.removeMonitor(g); flagsGlobal = nil }
        if let l = flagsLocal { NSEvent.removeMonitor(l); flagsLocal = nil }
        if let g = keyDownGlobal { NSEvent.removeMonitor(g); keyDownGlobal = nil }
        if let l = keyDownLocal { NSEvent.removeMonitor(l); keyDownLocal = nil }
        if lastState {
            lastState = false
            onStateChange?(false)
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let mask = store.hotkey.deviceMask
        let isDown = (event.modifierFlags.rawValue & mask) != 0
        if isDown != lastState {
            lastState = isDown
            onStateChange?(isDown)
        }
    }

    /// 返回 true 表示事件已被消费
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard store.toggleShapeKeyCode >= 0 else { return false }
        guard event.keyCode == UInt16(store.toggleShapeKeyCode) else { return false }
        let cleanMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        guard cleanMods == store.toggleShapeModifiers else { return false }
        DispatchQueue.main.async { [weak self] in self?.onToggleShape?() }
        return true
    }

    /// 设置项变更后调用，避免旧热键状态残留
    func resetState() {
        if lastState {
            lastState = false
            onStateChange?(false)
        }
    }
}
