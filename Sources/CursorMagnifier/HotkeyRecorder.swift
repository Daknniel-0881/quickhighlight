import SwiftUI
import Cocoa

/// 修饰键录制框：点击后变 "等待按键..."，按下任意修饰键即捕获并写回 store.hotkey
struct ModifierHotkeyRecorder: View {
    @ObservedObject var store: SettingsStore
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack {
                Text(recording ? "请按下任意修饰键…（Esc 取消）" : store.hotkey.displayName)
                    .foregroundStyle(recording ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: recording ? "record.circle.fill" : "pencil.circle")
                    .foregroundStyle(recording ? .red : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(recording ? Color.accentColor.opacity(0.10) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(recording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: recording ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown, event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            if event.type == .flagsChanged,
               let opt = KeyDisplay.detectHotkey(deviceMask: event.modifierFlags.rawValue) {
                store.hotkey = opt
                stopRecording()
                return nil
            }
            return nil  // 录制期间吞掉所有事件，避免误触
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = false
    }
}

/// 组合键录制框：点击后捕获下一次 keyDown（必须含至少一个修饰键），写回 keyCode + modifiers
struct ChordHotkeyRecorder: View {
    @ObservedObject var store: SettingsStore
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: toggleRecording) {
                    HStack {
                        Text(label)
                            .foregroundStyle(recording ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: recording ? "record.circle.fill" : "pencil.circle")
                            .foregroundStyle(recording ? .red : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(recording ? Color.accentColor.opacity(0.10) : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(recording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: recording ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)

                if store.toggleShapeKeyCode >= 0 {
                    Button {
                        store.toggleShapeKeyCode = -1
                        store.toggleShapeModifiers = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清除快捷键")
                }
            }
            if let hint = hint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if recording { return "请按下组合键…（Esc 取消）" }
        if store.toggleShapeKeyCode < 0 { return "未设置（点击录制）" }
        return KeyDisplay.chordText(keyCode: store.toggleShapeKeyCode, modifiers: store.toggleShapeModifiers)
    }

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown, event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            if event.type == .keyDown {
                let cleanMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let hasModifier = NSEvent.ModifierFlags(rawValue: cleanMods)
                    .intersection([.control, .option, .shift, .command])
                if hasModifier.isEmpty {
                    hint = "组合键必须包含至少一个修饰键（⌃ ⌥ ⇧ ⌘）"
                    return nil
                }
                store.toggleShapeKeyCode = Int(event.keyCode)
                store.toggleShapeModifiers = cleanMods
                stopRecording()
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = false
    }
}
