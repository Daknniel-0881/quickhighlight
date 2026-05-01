import Cocoa
import Carbon.HIToolbox

/// 热键监听器
///
/// 两条独立通道：
/// 1. **单键激活通道**（按住 ⌥/⇧/⌃/⌘/Fn 单个修饰键）
///    用 NSEvent.addGlobalMonitorForEvents(.flagsChanged)。
///    flagsChanged 是「修饰键状态变化」事件，系统不会拦截，被动监听足够。
///
/// 2. **组合键切换形状通道**（⌃⌥S / ⌥F1 之类含修饰键的组合键）
///    用 Carbon 的 RegisterEventHotKey 主动注册系统级热键。
///
///    踩坑记录（曲率 2026-05-01 反馈）：
///    之前用 NSEvent.addGlobalMonitorForEvents(.keyDown) 监听全局 keyDown，
///    在「设置面板没打开」时按 ⌥F1 完全不响应，必须打开设置面板才生效。
///    根因：addGlobalMonitorForEvents 是**被动监听**，
///    某些按键组合（特别是含 Fn / F1-F12 的）系统会在 SystemUIServer 层就消费掉，
///    被动监听根本拿不到事件。而 addLocalMonitor 只在自家 App 拥有 key window 时
///    才工作 —— 设置面板恰好是 key window，所以「打开设置面板」才能触发。
///
///    修复：换成 Carbon 的 RegisterEventHotKey —— 这是系统级**主动注册**通道，
///    会向 macOS 声明「这个组合键归我」，系统会优先把事件派给我们而不是被消费。
///    跟 Spotlight (⌘ Space)、QuickHighlight 切形状用的就是同一套 API。
final class HotkeyMonitor {
    var onStateChange: ((Bool) -> Void)?
    /// 切换形状组合键被按下时触发
    var onToggleShape: (() -> Void)?

    // 单键激活通道
    private var flagsGlobal: Any?
    private var flagsLocal: Any?
    private var lastState = false

    // Carbon 组合键通道
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?
    private var registeredKeyCode: UInt32 = 0
    private var registeredModifiers: UInt32 = 0
    private static let hotKeyID: UInt32 = 0x51484B31 // 'QHK1'

    private let store = SettingsStore.shared

    func start() {
        // 单键激活
        flagsGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        flagsLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
            return e
        }

        // Carbon 组合键
        installCarbonHandler()
        registerChordIfConfigured()
    }

    func stop() {
        if let g = flagsGlobal { NSEvent.removeMonitor(g); flagsGlobal = nil }
        if let l = flagsLocal { NSEvent.removeMonitor(l); flagsLocal = nil }
        unregisterChord()
        if let h = carbonEventHandler {
            RemoveEventHandler(h)
            carbonEventHandler = nil
        }
        if lastState {
            lastState = false
            onStateChange?(false)
        }
    }

    /// 设置项变更后调用：清旧状态 + 重新注册组合键
    /// SettingsStore 的 toggleShapeKeyCode / toggleShapeModifiers 改变后必须 reset，
    /// 否则用户改了快捷键但 Carbon 还注册的是旧组合
    func resetState() {
        if lastState {
            lastState = false
            onStateChange?(false)
        }
        registerChordIfConfigured()  // 重新注册（旧的会先被 unregister）
    }

    /// 单键激活（修饰键按住）
    private func handleFlags(_ event: NSEvent) {
        let mask = store.hotkey.deviceMask
        let isDown = (event.modifierFlags.rawValue & mask) != 0
        if isDown != lastState {
            lastState = isDown
            onStateChange?(isDown)
        }
    }

    // MARK: - Carbon 组合键

    private func installCarbonHandler() {
        guard carbonEventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr, hkID.id == HotkeyMonitor.hotKeyID else { return noErr }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { monitor.onToggleShape?() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &carbonEventHandler
        )
    }

    private func registerChordIfConfigured() {
        unregisterChord()
        guard store.toggleShapeKeyCode >= 0, store.toggleShapeModifiers != 0 else { return }
        let keyCode = UInt32(store.toggleShapeKeyCode)
        let carbonMods = cocoaToCarbonModifiers(store.toggleShapeModifiers)
        let id = EventHotKeyID(signature: HotkeyMonitor.hotKeyID, id: HotkeyMonitor.hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            carbonHotKeyRef = ref
            registeredKeyCode = keyCode
            registeredModifiers = carbonMods
            NSLog("[快捷高光] Carbon 热键注册成功: keyCode=%d carbonMods=0x%X", keyCode, carbonMods)
        } else {
            NSLog("[快捷高光] Carbon 热键注册失败 status=%d (可能跟系统快捷键冲突，请换组合)", status)
            // 通过 NotificationCenter 让 SettingsView 显示冲突提示
            NotificationCenter.default.post(
                name: .quickHighlightChordHotkeyConflict,
                object: nil,
                userInfo: ["status": Int(status)]
            )
        }
    }

    private func unregisterChord() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
    }

    /// Cocoa modifierFlags → Carbon modifiers 转换
    private func cocoaToCarbonModifiers(_ cocoa: UInt) -> UInt32 {
        var c: UInt32 = 0
        if cocoa & NSEvent.ModifierFlags.command.rawValue != 0  { c |= UInt32(cmdKey) }
        if cocoa & NSEvent.ModifierFlags.shift.rawValue != 0    { c |= UInt32(shiftKey) }
        if cocoa & NSEvent.ModifierFlags.option.rawValue != 0   { c |= UInt32(optionKey) }
        if cocoa & NSEvent.ModifierFlags.control.rawValue != 0  { c |= UInt32(controlKey) }
        return c
    }
}

extension Notification.Name {
    /// Carbon RegisterEventHotKey 失败（多半因为系统已占用该组合）
    static let quickHighlightChordHotkeyConflict = Notification.Name("com.curvature.quickhighlight.chordHotkeyConflict")
}
