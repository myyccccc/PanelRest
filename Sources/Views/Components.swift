import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - 原生液态玻璃样式（macOS 26+），旧系统退回原生样式
extension View {
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - 快捷键录制
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var conflict = false
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? stop() : start() }) {
                Group {
                    if recording { Text("按下新的组合键…") }
                    else if shortcut.isSet { Text(verbatim: shortcut.label) }
                    else { Text("点击设置") }
                }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 72)
                    .foregroundStyle(recording ? Color.accentColor : (shortcut.isSet ? .primary : .secondary))
            }
            .buttonStyle(PanelButtonStyle())
            .help("单按 Esc 取消，Delete 清除")
            if conflict && !recording {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("已被其他 App 占用")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeys.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = carbonMods(e.modifierFlags)
            if e.keyCode == UInt16(kVK_Escape) && mods == 0 { stop(); return nil }
            if (e.keyCode == UInt16(kVK_Delete) || e.keyCode == UInt16(kVK_ForwardDelete)) && mods == 0 {
                shortcut = .none; stop(); return nil
            }
            let isFKey = fKeys.contains(Int(e.keyCode))
            // 普通键必须带 ⌘ / ⌥ / ⌃（只按 ⇧ 会吞掉大写字母），F 键可单独使用
            if mods & (cmdKey | optionKey | controlKey) == 0 && !isFKey { NSSound.beep(); return nil }
            shortcut = Shortcut(keyCode: Int(e.keyCode), modifiers: mods, label: keyName(e))
            stop()
            return nil
        }
    }
    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        HotKeys.shared.register()
    }
}

private let fKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                               kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
    var m = 0
    if f.contains(.command) { m |= cmdKey }
    if f.contains(.option) { m |= optionKey }
    if f.contains(.control) { m |= controlKey }
    if f.contains(.shift) { m |= shiftKey }
    return m
}

func keyName(_ e: NSEvent) -> String {
    let special: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_Space: "Space", kVK_Escape: "Esc", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
    var s = ""
    let f = e.modifierFlags
    if f.contains(.control) { s += "⌃" }
    if f.contains(.option) { s += "⌥" }
    if f.contains(.shift) { s += "⇧" }
    if f.contains(.command) { s += "⌘" }
    return s + (special[Int(e.keyCode)] ?? (e.charactersIgnoringModifiers ?? "?").uppercased())
}

// MARK: - 提示（一句话）
struct TipBox: View {
    var icon = "exclamationmark.triangle.fill"
    let text: LocalizedStringKey
    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
    }
}

/// 触发角示意：一个小屏幕，被选中的角亮起
struct CornerDiagram: View {
    let corner: HotCornerPosition
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.85))
            RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            if corner != .off {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(3)
            }
        }
        .frame(width: 38, height: 24)
        .accessibilityLabel("触发角：\(corner.title)")
    }
    private var alignment: Alignment {
        switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .off: .center
        }
    }
}

func formatSeconds(_ v: Double) -> String {
    if v < 0.05 { return String(localized: "立即") }
    let n = v.formatted(.number.precision(.fractionLength(1)))
    return String(localized: "\(n) 秒")
}

func formatMinutes(_ m: Int) -> String {
    if m < 60 { return String(localized: "\(m) 分钟") }
    let h = (Double(m) / 60).formatted(.number.precision(.fractionLength(0...1)))
    return String(localized: "\(h) 小时")
}
