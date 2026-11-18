import SwiftUI

/// 引导页「适用屏幕」：左边分区背光逐格熄灭成纯黑（mini-LED / OLED），右边 LCD 背光一直透出灰光
struct DisplayFitView: View {
    private var kinds: Set<DisplayFit> { Set(Blackout.displays().map { DisplayFit.classify($0.name) }) }
    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 18) {
                card(ok: true, title: "Mini-LED / OLED", caption: "纯黑，不发光", highlight: kinds.contains(.supported)) { ZoneDimmingAnimation() }
                card(ok: false, title: "普通 LCD", caption: "背光常亮，无效果", highlight: kinds.contains(.lcd)) { LCDGlowAnimation() }
            }
            DetectedDisplaysList()
        }
        .padding(.horizontal, 28)
    }

    private func card<A: View>(ok: Bool, title: LocalizedStringKey, caption: LocalizedStringKey, highlight: Bool,
                               @ViewBuilder animation: () -> A) -> some View {
        VStack(spacing: 10) {
            MonitorFrame { animation() }
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
                Text(title).font(.headline)
            }
            Text(caption).font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard()
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ok ? Color.green : Color.red, lineWidth: highlight ? 2 : 0))
    }
}

/// 显示器外框 + 支架
private struct MonitorFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(width: 168, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.72)))
            Rectangle().fill(Color(white: 0.62)).frame(width: 22, height: 14)
            Capsule().fill(Color(white: 0.75)).frame(width: 66, height: 5)
        }
        .accessibilityHidden(true)
    }
}

/// 分区背光：一格一格从亮灰波浪式熄灭到纯黑，停一会，再亮起，循环
private struct ZoneDimmingAnimation: View {
    private let cols = 12, rows = 7, period = 4.0
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let w = size.width / CGFloat(cols), h = size.height / CGFloat(rows)
                for r in 0..<rows {
                    for c in 0..<cols {
                        // 从左上往右下的波浪：0.4s 后开始熄灭，1.6s 内扫完；3.2s 后重新亮起
                        let delay = 0.4 + Double(c + r) / Double(cols + rows) * 1.2
                        let fade = max(0, min(1, (t - delay) / 0.35))
                        let back = max(0, min(1, (t - 3.3) / 0.4))
                        let lum = 0.42 * (1 - fade) + 0.42 * back
                        let rect = CGRect(x: CGFloat(c) * w + 0.5, y: CGFloat(r) * h + 0.5, width: w - 1, height: h - 1)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color(white: lum)))
                    }
                }
            }
        }
    }
}

/// 普通 LCD：画面变黑后，整片背光仍透出灰光（边缘更亮，轻微起伏）
private struct LCDGlowAnimation: View {
    private let period = 4.0
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            let blackOut = max(0, min(1, (t - 0.4) / 0.6)) * (1 - max(0, min(1, (t - 3.3) / 0.4)))
            let base = 0.42 - 0.22 * blackOut                     // 亮灰 → 只降到发灰，降不到纯黑
            let breathe = 0.03 * sin(t * 2 * .pi / period * 2)
            ZStack {
                Color(white: base + breathe)
                RadialGradient(colors: [.clear, Color(white: 0.5).opacity(0.35 * blackOut)],
                               center: .center, startRadius: 30, endRadius: 110)   // 边缘漏光
            }
        }
    }
}

/// 识别当前连接的每台显示器，告诉用户适不适用
struct DetectedDisplaysList: View {
    @State private var displays = Blackout.displays().map(\.name)
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(displays.enumerated()), id: \.offset) { _, name in
                let fit = DisplayFit.classify(name)
                HStack(spacing: 10) {
                    Image(systemName: fit.icon).foregroundStyle(fit.color).font(.title3)
                    Text(verbatim: name).fontWeight(.semibold)
                    Spacer(minLength: 12)
                    Text(fit.verdict).foregroundStyle(fit == .supported ? .primary : .secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassCard(cornerRadius: 12)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = Blackout.displays().map(\.name)
        }
    }
}

enum DisplayFit: Hashable {
    case supported, lcd, unknown

    /// Apple XDR 系列都是 mini-LED 分区背光；名称带 OLED 的是自发光；已知的 Apple 普通 LCD 判为不适用
    static func classify(_ name: String) -> DisplayFit {
        let n = name.lowercased()
        if n.contains("xdr") || n.contains("oled") || n.contains("mini-led") || n.contains("miniled") || n.contains("mini led") {
            return .supported
        }
        let knownLCD = ["studio display", "built-in retina", "retina display", "imac", "ultrafine",
                        "thunderbolt display", "cinema display", "color lcd", "内建", "內建"]
        if knownLCD.contains(where: { n.contains($0) }) { return .lcd }
        return .unknown
    }
    static func isLikelySupported(_ name: String) -> Bool { classify(name) == .supported }

    var icon: String {
        switch self {
        case .supported: "checkmark.circle.fill"
        case .lcd: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .supported: .green
        case .lcd: .red
        case .unknown: .secondary
        }
    }
    var verdict: LocalizedStringKey {
        switch self {
        case .supported: "适用"
        case .lcd: "普通 LCD，不建议使用"
        case .unknown: "无法确认，请查看是否为 Mini-LED / OLED"
        }
    }
}
