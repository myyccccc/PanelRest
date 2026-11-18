import AppKit
import IOKit.pwr_mgt

// MARK: - 背光亮度（仅直装版：私有 DisplayServices，App Store 不允许）
enum Backlight {
    #if APPSTORE
    static var available: Bool { false }
    static func get(_ id: CGDirectDisplayID) -> Float? { nil }
    static func set(_ id: CGDirectDisplayID, _ v: Float) {}
    #else
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    static var available: Bool { getFn != nil && setFn != nil }
    static func get(_ id: CGDirectDisplayID) -> Float? {
        var v: Float = 0
        guard let f = getFn, f(id, &v) == 0 else { return nil }
        return v
    }
    static func set(_ id: CGDirectDisplayID, _ v: Float) { _ = setFn?(id, v) }
    #endif
}

// MARK: - 黑屏期间保持唤醒（不让系统睡眠或显示器休眠，否则后台 AI 会停）
final class KeepAwake {
    static let shared = KeepAwake()
    private var assertion: IOPMAssertionID = 0
    func begin() {
        guard assertion == 0 else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "PanelRest: display blacked out, background tasks keep running" as CFString, &assertion)
    }
    func end() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion); assertion = 0
    }
}

// MARK: - 黑屏引擎
final class Blackout: ObservableObject {
    static let shared = Blackout()
    @Published private(set) var active = false

    private var targets: [CGDirectDisplayID] = []
    private var reapplyTimer: Timer?
    private var fadeTimer: Timer?
    private var fading = false
    private var waking = false
    private var level: Float = 1            // 1 = 正常画面，0 = 全黑
    private var startedAt: Date?
    private(set) var armedAt = Date.distantFuture
    private let d = UserDefaults.standard

    static func displays() -> [(id: CGDirectDisplayID, name: String)] {
        NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (n, s.localizedName)
        }
    }
    private func targetIDs() -> [CGDirectDisplayID] {
        let all = Blackout.displays()
        let hit = all.filter { $0.name == Settings.shared.displayName }.map(\.id)
        return hit.isEmpty ? all.prefix(1).map(\.id) : hit
    }
    private var savedBrightness: Float {
        let v = d.float(forKey: "savedBrightness"); return v > 0.01 ? v : 0.6
    }

    /// 上次异常退出时亮度停在 0：启动时恢复
    func recoverIfNeeded() {
        guard d.bool(forKey: "wasActive") else { return }
        if Backlight.available { for id in targetIDs() { Backlight.set(id, savedBrightness) } }
        CGDisplayRestoreColorSyncSettings()
        d.set(false, forKey: "wasActive")
    }

    func toggle() {
        if waking { redarken() } else if active { wake() } else { start() }
    }

    /// 正在渐亮时又按了快捷键：掉头重新变黑
    private func redarken() {
        guard active, waking else { return }
        waking = false
        armedAt = Date().addingTimeInterval(Settings.shared.fadeOutDuration + Settings.shared.wakeGrace)
        animate(to: 0, duration: Settings.shared.fadeOutDuration) { [weak self] in
            guard let self else { return }
            self.applyBlack()
            self.reapplyTimer?.invalidate()
            self.reapplyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.applyBlack() }
        }
    }

    // MARK: 黑屏
    func start() {
        guard !active else { return }
        targets = targetIDs()
        guard !targets.isEmpty else { NSSound.beep(); return }
        if let b = targets.first.flatMap(Backlight.get), b > 0.01 { d.set(b, forKey: "savedBrightness") }
        d.set(true, forKey: "wasActive")
        active = true
        level = 1
        startedAt = Date()
        let s = Settings.shared
        if s.keepAwake { KeepAwake.shared.begin() }
        // 按完快捷键松手、手离开鼠标的余波不算：渐暗结束后再过「忽略时间」才开始监听
        armedAt = Date().addingTimeInterval(s.fadeOutDuration + s.wakeGrace)
        animate(to: 0, duration: s.fadeOutDuration) { [weak self] in
            guard let self else { return }
            self.applyBlack()
            // ColorSync / 夜览 / 显示器重新配置可能重置 gamma，持续重新施加
            self.reapplyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.applyBlack() }
        }
    }

    private func applyBlack() {
        guard active, !fading else { return }
        for id in targets {
            Backlight.set(id, 0)                                          // 直装版：背光调到最低
            CGSetDisplayTransferByFormula(id, 0, 0, 1, 0, 0, 1, 0, 0, 1)  // 画面输出全黑 → mini-LED 分区熄灭
        }
    }

    // MARK: 恢复
    func wake() {
        // 已在渐亮：不要因为手还在动就反复从头开始（以前每次移动都重启动画，越动越慢）
        guard active, !waking else { return }
        waking = true
        if debugInput { print("WAKE from:\n" + Thread.callStackSymbols.prefix(6).joined(separator: "\n")) }
        reapplyTimer?.invalidate(); reapplyTimer = nil
        animate(to: 1, duration: Settings.shared.fadeInDuration) { [weak self] in self?.finish() }
    }

    /// 立即恢复（退出 App 时）
    func wakeNow() {
        guard active else { return }
        reapplyTimer?.invalidate(); fadeTimer?.invalidate(); fading = false
        finish()
    }

    private func finish() {
        CGDisplayRestoreColorSyncSettings()
        if Backlight.available { for id in targets { Backlight.set(id, savedBrightness) } }
        d.set(false, forKey: "wasActive")
        if let s = startedAt { Settings.shared.totalDarkSeconds += Date().timeIntervalSince(s) }
        startedAt = nil
        KeepAwake.shared.end()
        level = 1
        active = false
        waking = false
        armedAt = .distantFuture
    }

    /// 由真实输入触发唤醒
    func realInputDetected() {
        // 关了自动恢复但没有可用快捷键时仍然允许，避免屏幕黑着无法恢复
        guard active, Settings.shared.wakeOnInput || !HotKeys.shared.hasWorkingShortcut, Date() >= armedAt else { return }
        wake()
    }

    // MARK: 渐变（ease-in-out，中途反向时按剩余距离缩短时间）
    private func animate(to goal: Float, duration: Double, done: @escaping () -> Void) {
        fadeTimer?.invalidate()
        fading = true
        let from = level, bright = savedBrightness, start = Date()
        let dur = duration * Double(abs(goal - from))
        // 点亮：背光立刻回到原亮度，只渐变画面；曲线先快后慢，手一碰就能看到画面出来。
        // 熄灭：背光和画面一起渐暗，曲线两头缓。
        let waking = goal > from
        if waking, Backlight.available { for id in targets { Backlight.set(id, bright) } }
        let step: () -> Bool = { [weak self] in
            guard let self else { return true }
            let p = dur <= 0.001 ? 1 : min(1, Date().timeIntervalSince(start) / dur)
            let e = Float(waking ? 1 - pow(1 - p, 3) : (p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2))
            self.level = from + (goal - from) * e
            let l = self.level
            for id in self.targets {
                CGSetDisplayTransferByFormula(id, 0, l, 1, 0, l, 1, 0, l, 1)
                if !waking, Backlight.available { Backlight.set(id, bright * l) }
            }
            return p >= 1
        }
        if step() { fading = false; done(); return }
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            if step() { t.invalidate(); self?.fadeTimer = nil; self?.fading = false; done() }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    /// 设置页「预览过渡」：渐暗 → 停 1 秒 → 渐亮
    func preview() {
        guard !active else { return }
        start()
        armedAt = .distantFuture
        DispatchQueue.main.asyncAfter(deadline: .now() + Settings.shared.fadeOutDuration + 1.0) { [weak self] in self?.wake() }
    }
}
