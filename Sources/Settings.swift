import AppKit
import Carbon.HIToolbox

/// 一个快捷键：Carbon keyCode + Carbon 修饰键 + 显示文字。keyCode < 0 表示未设置。
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: Int
    var label: String
    static let none = Shortcut(keyCode: -1, modifiers: 0, label: "")
    var isSet: Bool { keyCode >= 0 }
}

enum HotCornerPosition: Int, CaseIterable, Identifiable {
    case off = 0, topLeft, topRight, bottomLeft, bottomRight
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: String(localized: "关闭")
        case .topLeft: String(localized: "左上角")
        case .topRight: String(localized: "右上角")
        case .bottomLeft: String(localized: "左下角")
        case .bottomRight: String(localized: "右下角")
        }
    }
    /// 系统触发角在 com.apple.dock 里的键名
    var dockKey: String? {
        switch self {
        case .off: nil
        case .topLeft: "wvous-tl-corner"
        case .topRight: "wvous-tr-corner"
        case .bottomLeft: "wvous-bl-corner"
        case .bottomRight: "wvous-br-corner"
        }
    }
}

/// 所有用户设置，改动即写入 UserDefaults。
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // 通用
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: K.onboardingDone) } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin); LoginItem.apply() } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: K.showMenuBarIcon); AppDelegate.shared?.updateStatusItem() } }
    @Published var displayName: String { didSet { d.set(displayName, forKey: K.displayName) } }

    // 触发
    @Published var shortcut1: Shortcut { didSet { save(shortcut1, K.shortcut1); HotKeys.shared.register() } }
    @Published var shortcut2: Shortcut { didSet { save(shortcut2, K.shortcut2); HotKeys.shared.register() } }
    @Published var hotCorner: HotCornerPosition { didSet { d.set(hotCorner.rawValue, forKey: K.hotCorner) } }
    @Published var cornerDelay: Double { didSet { d.set(cornerDelay, forKey: K.cornerDelay) } }
    @Published var idleAutoBlackout: Bool { didSet { d.set(idleAutoBlackout, forKey: K.idleAuto) } }
    @Published var idleMinutes: Int { didSet { d.set(idleMinutes, forKey: K.idleMinutes) } }

    // 过渡
    @Published var fadeOutDuration: Double { didSet { d.set(fadeOutDuration, forKey: K.fadeOut) } }
    @Published var fadeInDuration: Double { didSet { d.set(fadeInDuration, forKey: K.fadeIn) } }

    // 唤醒与运行
    @Published var wakeOnInput: Bool { didSet { d.set(wakeOnInput, forKey: K.wakeOnInput) } }
    @Published var wakeGrace: Double { didSet { d.set(wakeGrace, forKey: K.wakeGrace) } }
    @Published var keepAwake: Bool { didSet { d.set(keepAwake, forKey: K.keepAwake) } }

    // 统计
    @Published var totalDarkSeconds: Double { didSet { d.set(totalDarkSeconds, forKey: K.totalDark) } }

    private enum K {
        static let onboardingDone = "onboardingDone", launchAtLogin = "launchAtLogin", showMenuBarIcon = "showMenuBarIcon"
        static let displayName = "displayName", shortcut1 = "shortcut1", shortcut2 = "shortcut2"
        static let hotCorner = "hotCorner", cornerDelay = "cornerDelay", idleAuto = "idleAutoBlackout", idleMinutes = "idleMinutes"
        static let fadeOut = "fadeOutDuration", fadeIn = "fadeInDuration"
        static let wakeOnInput = "wakeOnInput", wakeGrace = "wakeGrace", keepAwake = "keepAwake", totalDark = "totalDarkSeconds"
    }

    private init() {
        onboardingDone = d.bool(forKey: K.onboardingDone)
        // App Store 审核 2.4.5：开机自启必须由用户自己打开；直装版默认开启
        launchAtLogin = d.object(forKey: K.launchAtLogin) as? Bool ?? !Edition.isAppStore
        // 两个版本都默认显示菜单栏图标：没有 Dock 图标，这是找到设置 / 退出的入口（2026-11-14 用户要求）
        showMenuBarIcon = d.object(forKey: K.showMenuBarIcon) as? Bool ?? true
        displayName = d.string(forKey: K.displayName) ?? Settings.defaultDisplayName()
        shortcut1 = Settings.load(d, K.shortcut1) ?? Shortcut(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | cmdKey, label: "⌃⌥⌘B")
        shortcut2 = Settings.load(d, K.shortcut2) ?? Shortcut(keyCode: kVK_Escape, modifiers: cmdKey, label: "⌘Esc")
        hotCorner = HotCornerPosition(rawValue: d.object(forKey: K.hotCorner) as? Int ?? 1) ?? .topLeft
        cornerDelay = d.object(forKey: K.cornerDelay) as? Double ?? 0.3
        idleAutoBlackout = d.bool(forKey: K.idleAuto)
        idleMinutes = Settings.nearestIdleStep(d.object(forKey: K.idleMinutes) as? Int ?? 10)
        fadeOutDuration = d.object(forKey: K.fadeOut) as? Double ?? 0.3
        fadeInDuration = d.object(forKey: K.fadeIn) as? Double ?? 0.5
        wakeOnInput = d.object(forKey: K.wakeOnInput) as? Bool ?? true
        wakeGrace = d.object(forKey: K.wakeGrace) as? Double ?? 1.0
        keepAwake = d.object(forKey: K.keepAwake) as? Bool ?? true
        totalDarkSeconds = d.double(forKey: K.totalDark)
    }

    /// 定时熄灭可选的分钟数（滑条的每一格）
    static let idleSteps = [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120]
    static func nearestIdleStep(_ m: Int) -> Int {
        idleSteps.min(by: { abs($0 - m) < abs($1 - m) }) ?? 10
    }

    private func save(_ s: Shortcut, _ key: String) {
        d.set(["code": s.keyCode, "mods": s.modifiers, "label": s.label], forKey: key)
    }
    private static func load(_ d: UserDefaults, _ key: String) -> Shortcut? {
        guard let m = d.dictionary(forKey: key), let c = m["code"] as? Int, let mods = m["mods"] as? Int,
              let l = m["label"] as? String else { return nil }
        return Shortcut(keyCode: c, modifiers: mods, label: l)
    }

    /// 默认目标：优先 Studio Display / Pro Display 等外接 Apple 显示器，否则主显示器
    static func defaultDisplayName() -> String {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.localizedName.contains("XDR") || $0.localizedName.contains("Studio Display") }) {
            return s.localizedName
        }
        return screens.first?.localizedName ?? ""
    }

    func resetToDefaults() {
        let keepOnboarding = onboardingDone
        let domain = Bundle.main.bundleIdentifier ?? "com.denis.panelrest"
        let total = totalDarkSeconds
        // 试用起点、黑屏前亮度不是用户设置，不能被「恢复默认」清掉
        let keep = ["savedBrightness", "wasActive"].compactMap { k in d.object(forKey: k).map { (k, $0) } }
        d.removePersistentDomain(forName: domain)
        for (k, v) in keep { d.set(v, forKey: k) }
        let fresh = Settings.freshValues()
        launchAtLogin = fresh.launchAtLogin; showMenuBarIcon = fresh.showMenuBarIcon
        displayName = Settings.defaultDisplayName()
        shortcut1 = fresh.s1; shortcut2 = fresh.s2
        hotCorner = .topLeft; cornerDelay = 0.3; idleAutoBlackout = false; idleMinutes = 10
        fadeOutDuration = 0.3; fadeInDuration = 0.5
        wakeOnInput = true; wakeGrace = 1.0; keepAwake = true
        onboardingDone = keepOnboarding; totalDarkSeconds = total
    }
    private static func freshValues() -> (launchAtLogin: Bool, showMenuBarIcon: Bool, s1: Shortcut, s2: Shortcut) {
        (!Edition.isAppStore, true,
         Shortcut(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | cmdKey, label: "⌃⌥⌘B"),
         Shortcut(keyCode: kVK_Escape, modifiers: cmdKey, label: "⌘Esc"))
    }
}

enum Edition {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}
