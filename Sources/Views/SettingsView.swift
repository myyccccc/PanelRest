import SwiftUI

// MARK: - 面板尺寸：所有圆角同心（外圆角 = 内圆角 + 间距），间距全部统一
enum PanelMetrics {
    static let outer: CGFloat = 19          // 系统弹出面板（NSPopover）的外圆角，实测约 19pt
    static let inset: CGFloat = 8           // 面板边缘 → 卡片 / 标签栏
    static var card: CGFloat { outer - inset }   // 卡片、标签栏、底部按钮圆角 = 11
    static let tabInset: CGFloat = 3        // 标签栏 → 选中块
    static var tab: CGFloat { card - tabInset }  // 选中块圆角 = 8
    static let rowPadding: CGFloat = 12     // 卡片内文字左右边距
    static let rowHeight: CGFloat = 36
    static let inlineHeight: CGFloat = 24   // 行内按钮：上下各留 (36-24)/2 = 6
    static var inline: CGFloat { card - (rowHeight - inlineHeight) / 2 }   // 行内按钮圆角 = 5
    static let gap: CGFloat = 8             // 卡片之间
    static let width: CGFloat = 380
}

/// 设置面板：从菜单栏图标弹出（系统 NSPopover，液态玻璃），不是独立窗口
struct SettingsView: View {
    @State private var tab = UserDefaults.standard.integer(forKey: "settingsTab")   // 测试截图用：-settingsTab 4
    var body: some View {
        VStack(spacing: PanelMetrics.gap) {
            // 2026-11-18 用户要求：五个标签合并成三个，打开先看到常调的（空闲多久黑屏、过渡、唤醒）
            PanelTabBar(selection: $tab, items: ["黑屏", "触发", "通用"])
            Group {
                switch tab {
                case 0: BlackoutPane()
                case 1: TriggerPane()
                default: GeneralPane()
                }
            }
        }
        .padding(PanelMetrics.inset)
        .frame(width: PanelMetrics.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 基础组件

/// 标签栏：圆角 11，选中块内缩 3、圆角 8，与面板同心。
/// 切换不做动画（和系统分段控件一致）：选中块、页面内容、面板高度在同一帧切换。
/// 已录屏验证过：withAnimation 会让标签栏从面板中间滑回顶部、新旧页叠影；给选中块单独加动画会让它从下方斜飞上来。
struct PanelTabBar: View {
    @Binding var selection: Int
    let items: [LocalizedStringKey]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i])
                    .font(.system(size: 12, weight: selection == i ? .semibold : .regular))
                    .foregroundStyle(selection == i ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = i }
                    .accessibilityAddTraits(selection == i ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(alignment: .leading) {
            // 面板宽度固定，每个标签等宽：直接算偏移
            let w = (PanelMetrics.width - PanelMetrics.inset * 2 - PanelMetrics.tabInset * 2) / CGFloat(max(items.count, 1))
            RoundedRectangle(cornerRadius: PanelMetrics.tab)
                .fill(Color.primary.opacity(0.12))
                .frame(width: w)
                .offset(x: w * CGFloat(selection))
        }
        .padding(PanelMetrics.tabInset)
        .background(RoundedRectangle(cornerRadius: PanelMetrics.card).fill(Color.primary.opacity(0.06)))
    }
}

/// 按钮：bar = 面板底部（离面板边 8 → 圆角 11，高 32）；inline = 卡片行内（上下各留 6 → 圆角 5，高 24）
struct PanelButtonStyle: ButtonStyle {
    enum Kind { case bar, inline }
    var kind: Kind = .inline
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: kind == .bar ? PanelMetrics.card : PanelMetrics.inline)
        c.label
            .font(.system(size: kind == .bar ? 13 : 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, kind == .bar ? 14 : 10)
            .frame(height: kind == .bar ? 32 : PanelMetrics.inlineHeight)
            .background(shape.fill(prominent ? Color.accentColor : Color.primary.opacity(c.isPressed ? 0.16 : 0.09)))
            .overlay(shape.fill(Color.black.opacity(prominent && c.isPressed ? 0.12 : 0)))
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// 下拉菜单：外观与行内按钮一致（高 24、圆角 5）
struct PanelMenu<Items: View>: View {
    let title: String
    @ViewBuilder var items: Items
    var body: some View {
        Menu { items } label: {
            HStack(spacing: 6) {
                Text(verbatim: title)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PanelButtonStyle())
        .fixedSize()
    }
}

/// 卡片：圆角 11；可选小标题与卡片内文字左对齐
struct Card<Content: View>: View {
    var title: LocalizedStringKey? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, PanelMetrics.rowPadding)
                    .padding(.top, 4)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: PanelMetrics.card).fill(Color.primary.opacity(0.06)))
        }
    }
}

/// 卡片内的分隔线（从文字起点开始）
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            .padding(.leading, PanelMetrics.rowPadding)
    }
}

/// 一行：标题（可带一句说明）靠左，控件靠右
struct Row<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, PanelMetrics.rowPadding)
        .padding(.vertical, subtitle == nil ? 0 : 8)
        .frame(minHeight: PanelMetrics.rowHeight)
    }
}

/// 开关行
struct ToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var body: some View {
        Row(title: title) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

/// 滑条行：滑条和数值宽度固定，所有页面右侧对齐；不显示刻度点
struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    var body: some View {
        Row(title: title) {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { value },
                                      set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }),
                       in: range, onEditingChanged: onEditingChanged)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: 140)
                Text(text).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}

/// 卡片里的一句提示
struct TipRow: View {
    var icon = "exclamationmark.triangle.fill"
    let text: LocalizedStringKey
    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelMetrics.rowPadding)
            .padding(.vertical, 9)
    }
}

// MARK: - 黑屏（打开面板先看到这页：常调的都在这里）
struct BlackoutPane: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var b = Blackout.shared
    var body: some View {
        VStack(spacing: PanelMetrics.gap) {
            IdleSection()
            Card(title: "过渡") {
                SliderRow(title: "熄灭", value: $s.fadeOutDuration, range: 0...3, step: 0.1, text: formatSeconds(s.fadeOutDuration))
                RowDivider()
                SliderRow(title: "点亮", value: $s.fadeInDuration, range: 0...3, step: 0.1, text: formatSeconds(s.fadeInDuration))
            }
            Card(title: "唤醒") {
                ToggleRow(title: "触碰时自动恢复", isOn: $s.wakeOnInput)
                if s.wakeOnInput {
                    RowDivider()
                    SliderRow(title: "黑屏后先忽略", value: $s.wakeGrace, range: 0...5, step: 0.5, text: formatSeconds(s.wakeGrace))
                }
            }
            HStack {
                Spacer()
                Button("预览") { b.preview() }.buttonStyle(PanelButtonStyle(kind: .bar, prominent: true)).disabled(b.active)
            }
        }
    }
}

// MARK: - 通用（不常改的：启动、显示器、权限、关于）
struct GeneralPane: View {
    @ObservedObject var s = Settings.shared
    @State private var needsApproval = LoginItem.needsApproval
    var body: some View {
        VStack(spacing: PanelMetrics.gap) {
            Card {
                ToggleRow(title: "开机自动启动", isOn: $s.launchAtLogin)
                    .onChange(of: s.launchAtLogin) { _, _ in needsApproval = LoginItem.needsApproval }
                if s.launchAtLogin && needsApproval {
                    RowDivider()
                    Row(title: "需要在系统设置中允许") {
                        Button("打开") { LoginItem.openSystemSettings() }.buttonStyle(PanelButtonStyle())
                    }
                }
                RowDivider()
                ToggleRow(title: "菜单栏图标", isOn: $s.showMenuBarIcon)
                RowDivider()
                ToggleRow(title: "黑屏时保持电脑唤醒", isOn: $s.keepAwake)
                RowDivider()
                Row(title: "显示器") {
                    PanelMenu(title: s.displayName) {
                        ForEach(displayNames, id: \.self) { n in Button(n) { s.displayName = n } }
                    }
                }
            }
            PermissionSection()
            AboutCard()
            HStack(spacing: 8) {
                Button("使用引导") { AppDelegate.shared?.showOnboarding() }.buttonStyle(PanelButtonStyle(kind: .bar))
                Button("恢复默认") { confirmReset() }.buttonStyle(PanelButtonStyle(kind: .bar))
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(PanelButtonStyle(kind: .bar))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            needsApproval = LoginItem.needsApproval
        }
    }
    private var displayNames: [String] {
        Array(Set(Blackout.displays().map(\.name) + [s.displayName])).filter { !$0.isEmpty }.sorted()
    }
    /// 面板是无边框浮层，用系统提醒框确认
    private func confirmReset() {
        let a = NSAlert()
        a.messageText = String(localized: "恢复所有设置为默认值？")
        a.addButton(withTitle: String(localized: "恢复默认"))
        a.addButton(withTitle: String(localized: "取消"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { Settings.shared.resetToDefaults() }
    }
}

// MARK: - 触发
struct TriggerPane: View {
    var body: some View {
        VStack(spacing: PanelMetrics.gap) {
            ShortcutSection()
            HotCornerSection()
        }
    }
}

struct ShortcutSection: View {
    @ObservedObject var s = Settings.shared
    var body: some View {
        Card(title: "快捷键") {
            Row(title: "快捷键 1") { ShortcutRecorder(shortcut: $s.shortcut1, conflict: HotKeys.shared.failed.contains(1)) }
            RowDivider()
            Row(title: "快捷键 2") { ShortcutRecorder(shortcut: $s.shortcut2, conflict: HotKeys.shared.failed.contains(2)) }
        }
    }
}

/// 触发角（设置面板与引导页共用）
struct HotCornerSection: View {
    @ObservedObject var s = Settings.shared
    @State private var refreshID = 0
    var body: some View {
        Card(title: "触发角") {
            Row(title: "位置") {
                HStack(spacing: 8) {
                    CornerDiagram(corner: s.hotCorner)
                    PanelMenu(title: s.hotCorner.title) {
                        ForEach(HotCornerPosition.allCases) { c in Button(c.title) { s.hotCorner = c } }
                    }
                }
            }
            if s.hotCorner != .off {
                RowDivider()
                SliderRow(title: "停留", value: $s.cornerDelay, range: 0.1...3, step: 0.1, text: formatSeconds(s.cornerDelay))
                SystemCornerHint(corner: s.hotCorner).id(refreshID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshID += 1 }
    }
}

/// 系统自带触发角冲突提示
struct SystemCornerHint: View {
    let corner: HotCornerPosition
    @State private var replaced = false
    var body: some View {
        #if APPSTORE
        RowDivider()
        HStack {
            TipRow(text: "请把系统触发角的\(corner.title)设为「–」").padding(.trailing, -PanelMetrics.rowPadding)
            Button("系统触发角…") { SystemHotCorner.openSettings() }.buttonStyle(PanelButtonStyle())
                .padding(.trailing, PanelMetrics.rowPadding)
        }
        #else
        if let a = SystemHotCorner.action(at: corner), a > 1, !replaced {
            RowDivider()
            HStack {
                TipRow(text: "系统触发角：\(SystemHotCorner.actionName(a))").padding(.trailing, -PanelMetrics.rowPadding)
                Button("替换") { SystemHotCorner.clear(corner); replaced = true }.buttonStyle(PanelButtonStyle(prominent: true))
                    .padding(.trailing, PanelMetrics.rowPadding)
            }
        }
        #endif
    }
}

/// 定时熄灭：无人亲手操作一段时间后自动黑屏
struct IdleSection: View {
    @ObservedObject var s = Settings.shared
    @State private var systemMinutes = SystemDisplaySleep.minutes
    private let steps = Settings.idleSteps

    var body: some View {
        Card(title: "自动黑屏") {
            ToggleRow(title: "空闲时自动黑屏", isOn: $s.idleAutoBlackout)
                .onChange(of: s.idleAutoBlackout) { _, on in if on { alertIfConflict() } }
            if s.idleAutoBlackout {
                RowDivider()
                SliderRow(title: "空闲", value: stepIndex, range: 0...Double(steps.count - 1), step: 1,
                          text: formatMinutes(s.idleMinutes)) { editing in
                    if !editing { alertIfConflict() }
                }
                if let m = conflict {
                    RowDivider()
                    HStack {
                        TipRow(text: "系统会在 \(m) 分钟后先关闭显示器").padding(.trailing, -PanelMetrics.rowPadding)
                        Button("打开") { SystemDisplaySleep.openSettings() }.buttonStyle(PanelButtonStyle())
                            .padding(.trailing, PanelMetrics.rowPadding)
                    }
                }
                RowDivider()
                TipRow(icon: "lock.open.fill", text: "黑屏不会锁定，唤醒无需密码")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemMinutes = SystemDisplaySleep.minutes
        }
    }

    private var conflict: Int? {
        guard let m = systemMinutes, m > 0, m <= s.idleMinutes else { return nil }
        return m
    }
    private var stepIndex: Binding<Double> {
        Binding(get: { Double(steps.firstIndex(of: s.idleMinutes) ?? steps.firstIndex(of: Settings.nearestIdleStep(s.idleMinutes)) ?? 0) },
                set: { s.idleMinutes = steps[max(0, min(steps.count - 1, Int($0.rounded())))] })
    }
    private func alertIfConflict() {
        systemMinutes = SystemDisplaySleep.minutes
        guard let m = conflict else { return }
        DispatchQueue.main.async { SystemDisplaySleep.alert(systemMinutes: m) }
    }
}

/// 输入监控权限（设置面板与引导页共用）
struct PermissionSection: View {
    @ObservedObject var r = RealInput.shared
    var body: some View {
        Card {
            Row(title: "只认亲手操作", subtitle: "需要「输入监控」，AI 的后台操作不会点亮屏幕") {
                if r.hasPermission {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 16))
                } else {
                    Button("开启") { PermissionSection.request() }.buttonStyle(PanelButtonStyle(prominent: true))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in r.refresh() }
    }
    /// 弹出系统授权并打开「输入监控」设置
    static func request() {
        RealInput.shared.requestPermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}

// MARK: - 关于（放在「通用」页）
struct AboutCard: View {
    @ObservedObject var s = Settings.shared
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("PanelRest").font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 4) {
                        Text(verbatim: version)
                        if !Edition.isAppStore { Text(verbatim: "·"); Text("直装版") }
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("累计黑屏").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(formatHours(s.totalDarkSeconds)).font(.system(size: 13)).monospacedDigit()
                }
            }
            .padding(.horizontal, PanelMetrics.rowPadding)
            .padding(.vertical, 10)
        }
    }
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private func formatHours(_ s: Double) -> String {
        if s < 3600 { return String(localized: "\(Int(s / 60)) 分钟") }
        let h = (s / 3600).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(h) 小时")
    }
}
