import SwiftUI

/// 首次启动引导：欢迎 → 触发 → 唤醒 → 启动
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @ObservedObject var s = Settings.shared
    @ObservedObject var b = Blackout.shared
    @ObservedObject var r = RealInput.shared
    private let pages = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: step("适用屏幕") { DisplayFitView().padding(.top, 24) }
                case 2: step("触发") { VStack(spacing: PanelMetrics.gap) { ShortcutSection(); HotCornerSection() }.cardPage() }
                case 3: step("唤醒") {
                    VStack(spacing: PanelMetrics.gap) {
                        PermissionSection()
                        Card { ToggleRow(title: "黑屏时保持电脑唤醒", isOn: $s.keepAwake) }
                    }.cardPage()
                }
                default: step("启动") {
                    VStack(spacing: PanelMetrics.gap) {
                        Card {
                            ToggleRow(title: "开机自动启动", isOn: $s.launchAtLogin)
                            RowDivider()
                            ToggleRow(title: "菜单栏图标", isOn: $s.showMenuBarIcon)
                        }
                        Card {
                            Row(title: "试一下") {
                                Button("预览") { b.preview() }.buttonStyle(PanelButtonStyle()).disabled(b.active)
                            }
                        }
                    }.cardPage()
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Capsule().fill(i == page ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 18 : 6, height: 6)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: page)
                Spacer()
                if page > 0 {
                    Button("返回") { withAnimation(.easeInOut(duration: 0.25)) { page -= 1 } }
                        .glassButton()
                }
                if needsPermission {
                    // 「只认亲手操作」默认要开：主按钮直接去授权，跳过放在次要按钮
                    Button("以后再说") { next() }.glassButton()
                    Button("开启") { PermissionSection.request() }
                        .keyboardShortcut(.defaultAction).glassButton(prominent: true)
                } else {
                    Button(page == pages - 1 ? LocalizedStringKey("完成") : LocalizedStringKey("继续")) {
                        if page == pages - 1 { onFinish() } else { next() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .frame(width: 560, height: 520)
    }

    /// 「唤醒」页且还没有输入监控权限
    private var needsPermission: Bool { page == 3 && !r.hasPermission }
    private func next() { withAnimation(.easeInOut(duration: 0.25)) { page += 1 } }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("PanelRest").font(.largeTitle.weight(.semibold))
            Text("屏幕全黑，后台照常运行").font(.title3).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func step<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.largeTitle.weight(.semibold)).padding(.horizontal, 28).padding(.top, 40)
            content()
        }
    }
}

private extension View {
    /// 引导页里的卡片区：左右与标题对齐
    func cardPage() -> some View { self.padding(.horizontal, 28).padding(.top, 20) }
}
