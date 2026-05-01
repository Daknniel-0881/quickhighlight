import Cocoa
import SwiftUI
import Combine

extension Notification.Name {
    static let quickHighlightPreviewOverlay = Notification.Name("com.curvature.quickhighlight.previewOverlay")
    static let quickHighlightTogglePersistentPreview = Notification.Name("com.curvature.quickhighlight.togglePersistentPreview")
    static let quickHighlightPersistentPreviewStateChanged = Notification.Name("com.curvature.quickhighlight.persistentPreviewStateChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var updateTimer: Timer?
    private var isActive = false
    /// 持续预览模式：开启后 overlay 一直保持显示，便于在 Settings 里实时调参对比效果
    private(set) var persistentPreview = false

    private let hotkeyMonitor = HotkeyMonitor()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlayWindow()
        setupStatusItem()
        setupHotkey()
        observeSettings()
        // 权限引导放到 UI 起来之后弹，避免被启动闪屏盖掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.ensurePermissions()
            self?.startScreenCapture()
        }
        // 屏幕拓扑变化时重建覆盖窗口（接显示器/分辨率变更）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // 监听设置面板触发的"测试效果"事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewRequest),
            name: .quickHighlightPreviewOverlay,
            object: nil
        )
        // 监听持续预览开关
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTogglePersistentPreview),
            name: .quickHighlightTogglePersistentPreview,
            object: nil
        )
    }

    /// 切换持续预览模式：ON → 强制显示 overlay；OFF → 关闭并恢复正常按键控制
    @objc private func handleTogglePersistentPreview() {
        UserDefaults.standard.synchronize()
        persistentPreview.toggle()
        if persistentPreview {
            // 开启：立即激活，强制显示
            if !isActive { activate() }
        } else {
            // 关闭：仅当不是被热键按住时 deactivate
            if isActive { deactivate() }
        }
        NotificationCenter.default.post(
            name: .quickHighlightPersistentPreviewStateChanged,
            object: nil,
            userInfo: ["on": persistentPreview]
        )
    }

    /// 设置面板"保存并预览效果"按钮触发：在鼠标当前位置激活 overlay 1.5 秒，让用户立即看到当前参数下的真实渲染
    @objc private func handlePreviewRequest() {
        // 强制 flush UserDefaults，确保参数已落盘
        UserDefaults.standard.synchronize()
        // 已经处于按住状态就不重复触发（避免冲突）
        guard !isActive else { return }
        activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.isActive else { return }
            self.deactivate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor.stop()
        stopTimer()
        Task { await ScreenCapturer.shared.stop() }
    }

    /// 应用启动后即启动屏幕抓帧（持续运行），按热键时直接拿最新帧 — 避免按键时再启动 stream 的延迟
    private func startScreenCapture() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let windowID = CGWindowID(overlayWindow?.windowNumber ?? 0)
        Task { @MainActor in
            do {
                try await ScreenCapturer.shared.start(excludingWindowIDs: [windowID])
            } catch {
                NSLog("[快捷高光] ScreenCapturer.start 失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Overlay

    private func setupOverlayWindow() {
        guard let screen = NSScreen.main else { return }
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.sharingType = .none
        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        window.orderOut(nil)
        self.overlayWindow = window
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "plus.magnifyingglass",
                accessibilityDescription: "快捷高光"
            )
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        let prefItem = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 快捷高光", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "快捷高光 偏好设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyMonitor.onStateChange = { [weak self] isDown in
            DispatchQueue.main.async {
                isDown ? self?.activate() : self?.deactivate()
            }
        }
        hotkeyMonitor.onToggleShape = {
            // 全局组合键触发：圆形 ↔ 圆角矩形 立即互切
            let store = SettingsStore.shared
            store.shape = (store.shape == .circle) ? .roundedRect : .circle
        }
        hotkeyMonitor.start()
    }

    private func observeSettings() {
        // 切换激活键时清掉旧状态
        SettingsStore.shared.$hotkey
            .dropFirst()
            .sink { [weak self] _ in
                self?.hotkeyMonitor.resetState()
                self?.deactivate()
            }
            .store(in: &cancellables)

        // 调整外观参数时立即刷新视图（每个 publisher 独立订阅，subscribe 时初始值用 dropFirst(1) 跳掉）
        let signals: [AnyPublisher<Void, Never>] = [
            SettingsStore.shared.$radius.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$rectWidth.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$rectHeight.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$zoom.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$dimAlpha.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$showRing.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$shape.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(signals)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let view = self?.overlayWindow?.contentView as? OverlayView else { return }
                view.updateForCursor()  // 立即重 crop（zoom/radius 改变会影响 captureSize）
            }
            .store(in: &cancellables)
    }

    // MARK: - Activation

    private func activate() {
        guard !isActive else { return }
        isActive = true
        overlayWindow?.orderFrontRegardless()
        startTimer()
    }

    private func deactivate() {
        guard isActive else { return }
        // 持续预览模式下，松开热键不应该关闭 overlay
        if persistentPreview { return }
        isActive = false
        overlayWindow?.orderOut(nil)
        stopTimer()
    }

    private func startTimer() {
        updateTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let window = self.overlayWindow,
                  let view = window.contentView as? OverlayView else { return }
            _ = window  // silence unused warning if any
            view.updateForCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    @objc private func handleScreenChange() {
        // 屏幕变了，重建覆盖窗口 + 重启抓帧
        deactivate()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        setupOverlayWindow()
        Task { @MainActor in
            await ScreenCapturer.shared.stop()
            self.startScreenCapture()
        }
    }

    /// 显式检测屏幕录制 + 辅助功能两项关键权限。
    /// 加了「曾经全部授权过」缓存：一次授权成功后不再弹我们自己的对话框，
    /// 即使 ad-hoc 重签名导致 TCC 暂时失效也保持安静，让用户不被反复打扰。
    private func ensurePermissions() {
        let defaults = UserDefaults.standard
        let kPermPromptShownAt = "permPromptDismissedAt"
        let kPermGrantedOnce = "permGrantedOnce"

        // 1) 辅助功能 — 不带 prompt:true 调用，避免每次启动都触发系统辅助功能弹框
        let axTrusted = AXIsProcessTrustedWithOptions(nil)

        // 2) 屏幕录制 — Preflight 是只读检测，安全
        let scOk = CGPreflightScreenCaptureAccess()

        // 都通过：标记「曾经成功授权过」，永久消音
        if axTrusted && scOk {
            defaults.set(true, forKey: kPermGrantedOnce)
            return
        }

        // 曾经全部授权过：永久静默。即使现在某项 false（ad-hoc 重签 cdhash 变化导致的临时
        // 失效），也不再弹任何我们或系统的对话框。用户授权过一次就一辈子不再被打扰。
        // ⚠️ 关键：不调用 CGRequestScreenCaptureAccess() —— 这个函数本身会触发系统弹框。
        if defaults.bool(forKey: kPermGrantedOnce) {
            return
        }

        // 之前弹过一次（任何时间）：永久不再弹。曲率明确要求"开过就不再问"，
        // 优于按 24h 周期重弹。
        let lastShown = defaults.double(forKey: kPermPromptShownAt)
        if lastShown > 0 {
            return
        }

        // 真·首次：弹一次告知用户去开权限。这次会触发系统弹框（CGRequestScreenCaptureAccess）
        if !scOk { _ = CGRequestScreenCaptureAccess() }
        let alert = NSAlert()
        alert.messageText = "快捷高光 首次启动需要授权两项系统权限"
        var lines: [String] = []
        if !scOk { lines.append("• 屏幕录制：放大圈内显示鼠标周围画面") }
        if !axTrusted { lines.append("• 辅助功能：监听全局快捷键（按住激活）") }
        alert.informativeText = """
        \(lines.joined(separator: "\n"))

        授权后请退出快捷高光（菜单栏 🔍 → 退出），再次打开即可。授权状态会被记住，下次不会再弹这个对话框。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "去开启屏幕录制")
        alert.addButton(withTitle: "去开启辅助功能")
        alert.addButton(withTitle: "稍后")
        defaults.set(Date().timeIntervalSince1970, forKey: kPermPromptShownAt)
        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        default:
            break
        }
    }
}
