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

    /// 抓帧静默重启状态（指数退避：1s → 2s → 4s → ... 30s 封顶 · 最多 5 次后停手）
    /// 用户体验铁律：抓帧失败永远不弹窗，后台默默重试，菜单栏图标做轻状态提示
    /// 5 次仍失败大概率是权限/cdhash 问题，再重试也只会反复触发系统级权限弹框
    private var captureRestartDelay: TimeInterval = 1.0
    private var captureRestartTimer: Timer?
    private var captureRestartAttempts = 0
    private static let maxCaptureRestartAttempts = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupOverlayWindow()
        setupStatusItem()
        setupHotkey()
        observeSettings()
        // SCStream 系统级停止时静默重启，绝不弹窗
        ScreenCapturer.shared.onStreamStopped = { [weak self] _ in
            self?.updateStatusIcon(captureHealthy: false)
            self?.scheduleSilentCaptureRestart()
        }
        // 权限引导放到 UI 起来之后弹，避免被启动闪屏盖掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.ensurePermissions()
            self?.startScreenCapture()
            if ProcessInfo.processInfo.environment["QH_OPEN_SETTINGS"] == "1" {
                self?.openSettings()
            }
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
        captureRestartTimer?.invalidate()
        captureRestartTimer = nil
        Task { await ScreenCapturer.shared.stop() }
    }

    /// 修复「APP 用着用着自动退出」的根因：
    /// macOS 默认行为是「最后一个窗口关闭 → terminate」。本 APP 是菜单栏常驻类型，
    /// 关掉设置面板不应该退出。必须显式返回 false，否则用户每关一次设置窗口就退出一次。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// 应用启动后即启动屏幕抓帧（持续运行），按热键时直接拿最新帧。
    /// 用户体验铁律：失败永远不弹窗，只 NSLog + 菜单栏图标轻提示 + 后台静默指数退避重启。
    /// CGPreflight 在 ad-hoc 重签 cdhash 漂移时会假阴性，所以不预检——直接让 SCStream 试，
    /// 真正不行了再静默重试，绝不打扰用户。
    private func startScreenCapture() {
        let windowID = CGWindowID(overlayWindow?.windowNumber ?? 0)
        Task { @MainActor in
            do {
                try await ScreenCapturer.shared.start(excludingWindowIDs: [windowID])
            } catch {
                NSLog("[快捷高光] ScreenCapturer.start 失败: \(error.localizedDescription) — 静默重启中")
                self.updateStatusIcon(captureHealthy: false)
                self.scheduleSilentCaptureRestart()
                return
            }
            // start() 成功 ≠ 真有 frame；2s 后仍无 latestFrame 当作启动失败，静默重启
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if ScreenCapturer.shared.latestFrame == nil {
                NSLog("[快捷高光] SCStream 启动后 2s 无帧 — 静默重启")
                await ScreenCapturer.shared.stop()
                self.updateStatusIcon(captureHealthy: false)
                self.scheduleSilentCaptureRestart()
                return
            }
            // 真·健康：reset 退避 + 重试计数，菜单栏图标恢复正常
            self.captureRestartDelay = 1.0
            self.captureRestartAttempts = 0
            self.updateStatusIcon(captureHealthy: true)
        }
    }

    /// 静默重启抓帧。退避 1s → 2s → 4s ... 30s 封顶。
    /// 累计 5 次仍失败就停手 —— 大概率是权限/cdhash 问题，继续重试只会
    /// 反复触发系统级"想录制屏幕"弹框，把用户拖进死循环。
    /// 用户可以从菜单栏点"重新尝试连接屏幕抓帧"手动恢复。
    private func scheduleSilentCaptureRestart() {
        captureRestartTimer?.invalidate()
        if captureRestartAttempts >= AppDelegate.maxCaptureRestartAttempts {
            NSLog("[快捷高光] 抓帧重启已达 %d 次上限，停止自动重试。用户可从菜单栏手动恢复。",
                  AppDelegate.maxCaptureRestartAttempts)
            return
        }
        captureRestartAttempts += 1
        let delay = captureRestartDelay
        captureRestartDelay = min(captureRestartDelay * 2.0, 30.0)
        captureRestartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.startScreenCapture()
        }
    }

    /// 用户从菜单栏手动触发重连：清空退避计数 + 立刻重启
    @objc private func manualRetryCapture() {
        captureRestartTimer?.invalidate()
        captureRestartAttempts = 0
        captureRestartDelay = 1.0
        startScreenCapture()
    }

    /// 菜单栏图标轻量状态提示：抓帧健康 = plus.magnifyingglass，失败 = magnifyingglass（无加号）
    /// 用户瞥一眼就知道当前能不能放大；不健康时也不弹窗、不阻断使用。
    private func updateStatusIcon(captureHealthy: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = captureHealthy ? "plus.magnifyingglass" : "magnifyingglass"
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "快捷高光")
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !captureHealthy
        button.toolTip = captureHealthy ? "快捷高光" : "快捷高光（屏幕抓帧暂时不可用，正在重连…）"
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
        let retryItem = NSMenuItem(title: "重新尝试连接屏幕抓帧", action: #selector(manualRetryCapture), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)
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

        // 切换形状的组合键改了 → 立即 unregister 旧 Carbon 热键 + register 新的
        // 这就是曲率要的「设置快捷键时能写入系统、监听修改、修改系统快捷键设置」机制：
        // resetState() 内部 unregisterChord() + registerChordIfConfigured()，
        // Carbon RegisterEventHotKey 是系统级注册，跟 Spotlight 一个层级，
        // 注册后 macOS 会优先把事件派给我们 —— 跟系统快捷键冲突时本 App 优先生效
        SettingsStore.shared.$toggleShapeKeyCode
            .dropFirst()
            .sink { [weak self] _ in self?.hotkeyMonitor.resetState() }
            .store(in: &cancellables)
        SettingsStore.shared.$toggleShapeModifiers
            .dropFirst()
            .sink { [weak self] _ in self?.hotkeyMonitor.resetState() }
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

    /// 权限引导：仅在「全新设备 + 没用过本 App」时弹一次自定义引导对话框。
    ///
    /// 死循环根因（v8 之前）：
    /// 1) ad-hoc 签名每次 build cdhash 变化，TCC 数据库认旧 cdhash 不认新的
    /// 2) `CGPreflightScreenCaptureAccess()` 因此**永远返回 false**
    /// 3) 旧逻辑用 `axTrusted && scOk` 作为「曾经授权」判定 → 永远不成立 → kPermGrantedOnce 永远不写
    /// 4) 主动调 `CGRequestScreenCaptureAccess()` → 系统每次启动都弹「想录制屏幕」对话框
    /// 5) 用户去系统设置勾选 → 重启 → cdhash 再变 → 又弹 → **死循环**
    ///
    /// 修复策略（v8）：
    /// - 「弹过自定义引导」就标记 kPermPromptShownAt，**之后永远不再弹任何 App 自己的引导**
    /// - **永远不主动调 CGRequestScreenCaptureAccess**——首次 SCStream.startCapture 会自然触发一次系统弹框，
    ///   交给系统决定，App 不重复请求
    /// - 不依赖 preflight 结果做循环判定，因为 ad-hoc 下它根本不可信
    private func ensurePermissions() {
        let defaults = UserDefaults.standard
        let kPermPromptShownAt = "permPromptDismissedAt"

        // 任何时候只要弹过一次自定义引导，永久不再弹（无视 preflight 结果）
        // 这一行是切断死循环的关键
        if defaults.double(forKey: kPermPromptShownAt) > 0 {
            return
        }

        // 真·首次（这台设备从未运行过本 App）：弹一次告知去开权限
        // ⚠️ 不调用 CGRequestScreenCaptureAccess —— 让 SCStream.startCapture 那条路径
        //    去自然触发系统级弹框，避免双重请求
        let axTrusted = AXIsProcessTrustedWithOptions(nil)
        let scOk = CGPreflightScreenCaptureAccess()
        if axTrusted && scOk {
            // 极少数情况：用户从其他 App 打开过相同 cdhash（比如签名稳定的版本），
            // 此时无需弹引导，直接静默 + 标记
            defaults.set(Date().timeIntervalSince1970, forKey: kPermPromptShownAt)
            return
        }

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
        // 关键：弹之前就先写标志，无论用户点哪个按钮、是否真去授权，下次启动都不再打扰
        defaults.set(Date().timeIntervalSince1970, forKey: kPermPromptShownAt)
        defaults.synchronize()
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
