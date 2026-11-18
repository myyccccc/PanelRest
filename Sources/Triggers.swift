import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SystemConfiguration
import IOKit.pwr_mgt
import IOKit.hid

// MARK: - 真实输入监听
// 真实的鼠标 / 键盘 / 触控板事件 eventSourceUnixProcessID == 0；
// 软件模拟的（AI 点击、移动、打字）带着发出它的进程号 → 不算。
// 需要「输入监控」权限才能收到其他 App 的事件；没有权限时退回 HID 空闲计时。
let debugInput = ProcessInfo.processInfo.environment["PR_DEBUG"] != nil

final class RealInput: ObservableObject {
    static let shared = RealInput()
    @Published private(set) var hasPermission = CGPreflightListenEventAccess()
    private var tap: CFMachPort?
    /// 没有「输入监控」权限时用的全局鼠标监听（系统允许，无需权限；键盘需要权限才收得到）
    private var mouseMonitor: Any?
    private var permTimer: Timer?
    private var lockedFallbackTimer: Timer?
    private(set) var lastRealAt = Date()
    private(set) var lastRealLoc = CGPoint(x: -99_999, y: -99_999)
    /// 最近一次被程序（AI）移动光标的时间
    private(set) var lastFakeMoveAt = Date.distantPast
    /// 锁屏（屏保要求密码、⌃⌘Q 等）期间监听可能收不到事件，改用 HID 空闲计时兜底
    private(set) var screenLocked = false

    private static let moveTypes: Set<CGEventType> = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    func start() {
        PhysicalHID.shared.start()
        refresh()
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked = true }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked = false }
        permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        // 只在锁屏时用 HID 空闲计时兜底（锁屏时 AI 无法操作，且用户需要看到登录界面）。
        // 平时绝不用它：AI 的模拟事件也会重置这个计时，会误点亮屏幕。
        lockedFallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.screenLocked else { return }
            let b = Blackout.shared
            if b.active, Self.hidIdle() < Date().timeIntervalSince(b.armedAt) { b.realInputDetected() }
        }
    }

    func requestPermission() {
        CGRequestListenEventAccess()
        refresh()
    }

    func refresh() {
        let ok = CGPreflightListenEventAccess()
        if ok != hasPermission { hasPermission = ok }
        if ok && tap == nil { createTap() }
        if ok { PhysicalHID.shared.start() }
        if tap != nil {
            if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        } else if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
                .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .swipe, .magnify, .rotate
            ]) { e in
                guard let cg = e.cgEvent else { return }
                RealInput.shared.process(cg.type, cg)
            }
        }
    }

    static func hidIdle() -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// 距离用户最后一次亲手操作过去了多少秒（只算真实硬件输入）
    var secondsSinceRealInput: Double { Date().timeIntervalSince(lastRealAt) }
    /// 鼠标总能区分（无权限时用全局鼠标监听）；键盘需要「输入监控」
    var canTellApart: Bool { tap != nil || mouseMonitor != nil }

    /// 真实硬件事件 eventSourceUnixProcessID == 0；AI 等程序模拟的事件带着发出它的进程号
    fileprivate func process(_ type: CGEventType, _ event: CGEvent) {
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard pid == 0 else {
            if debugInput { print("synthetic input ignored type=\(type.rawValue) pid=\(pid)") }
            if Self.moveTypes.contains(type) { lastFakeMoveAt = Date() }
            return
        }
        // 第二道关：事件自称来自硬件，还得物理设备（USB / 蓝牙键鼠、触控板）真的发过信号。
        // 有些 AI 工具的模拟事件不带进程号，靠这一条拦下。设备信号可能比事件晚到，稍等再判断一次。
        let loc = event.location
        if PhysicalHID.shared.recentlyActive { markReal(type, loc); return }
        // 设备信号还没到：先记下，信号一到（0.5 秒内）立即确认，不再固定等待
        pending = (Date(), type, loc)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let p = self.pending, Date().timeIntervalSince(p.at) >= 0.5 else { return }
            self.pending = nil
            if PhysicalHID.shared.recentlyActive { self.markReal(p.type, p.loc) }
            else if debugInput { print("pid0 but no physical HID → ignored type=\(p.type.rawValue)") }
        }
    }

    /// 自称来自硬件、正在等物理设备信号确认的事件
    private var pending: (at: Date, type: CGEventType, loc: CGPoint)?

    /// 物理设备刚发来信号：确认 0.5 秒内等待中的事件
    fileprivate func physicalSignal() {
        guard let p = pending else { return }
        pending = nil
        if Date().timeIntervalSince(p.at) < 0.5 { markReal(p.type, p.loc) }
    }

    private func markReal(_ type: CGEventType, _ loc: CGPoint) {
        if debugInput { print("real input type=\(type.rawValue) active=\(Blackout.shared.active)") }
        lastRealAt = Date()
        if Self.moveTypes.contains(type) { lastRealLoc = loc }
        if Blackout.shared.active { Blackout.shared.realInputDetected() }
    }

    private func createTap() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                    .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown]
        var mask: CGEventMask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        mask |= (1 << 29) // 触控板手势
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
            let me = RealInput.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            } else {
                me.process(type, event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
        if let tap { CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes) }
    }
}

// MARK: - 物理输入设备
/// 直接监听物理键盘、鼠标、触控板（IOHIDManager）。软件模拟的事件不经过这些设备；
/// 按设备类型匹配（任何品牌的鼠标、轨迹球、键盘、触控板、数位板、触摸屏、媒体键），连接方式不限（USB、蓝牙、内建）。
/// 虚拟设备（Transport = Virtual，如 Logi Options+ 的改键键盘）不算，它们的原始按键仍会从真实设备上报；
/// 例外：Karabiner 会独占真实键盘、改由它的虚拟键盘发出，所以算真人。
/// 兜底：需要「输入监控」权限；拿不到设备，或启动后从没收到过任何物理信号（设备被别的软件独占、看不到），
/// 都退回只看进程号，保证任何人都能唤醒。
final class PhysicalHID {
    static let shared = PhysicalHID()
    private var manager: IOHIDManager?
    private(set) var working = false
    private(set) var lastActiveAt = Date.distantPast
    /// 启动后收到过物理信号，说明这台电脑的设备看得见，才启用这道检查
    private var everSeen = false

    /// 最近 0.5 秒内物理设备有输入；监听不可用时视为通过
    var recentlyActive: Bool { !working || !everSeen || Date().timeIntervalSince(lastActiveAt) < 0.5 }

    func start() {
        guard !working else { return }
        if let m = manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)); manager = nil }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_Digitizer],   // 数位板
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_Pen],         // 手写笔
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchScreen], // 触摸屏
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: 0x0C],                      // 妙控板多点触控
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl], // 媒体键、遥控器
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, match as CFArray)
        IOHIDManagerRegisterInputValueCallback(m, { _, _, _, value in
            PhysicalHID.shared.handle(value)
        }, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        let devices = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? []
        let physical = devices.filter { !Self.isVirtual($0) }
        working = r == kIOReturnSuccess && !physical.isEmpty
        if debugInput {
            print("PhysicalHID open=\(String(r, radix: 16)) devices=\(devices.count) physical=\(physical.count) working=\(working)")
            for d in devices { print("  HID", Self.prop(d, kIOHIDProductKey) ?? "?", Self.prop(d, kIOHIDTransportKey) ?? "?") }
        }
    }

    private static func prop(_ d: IOHIDDevice, _ k: String) -> String? {
        IOHIDDeviceGetProperty(d, k as CFString) as? String
    }
    private static func isVirtual(_ d: IOHIDDevice) -> Bool {
        let t = (prop(d, kIOHIDTransportKey) ?? "").lowercased()
        guard t.contains("virtual") else { return false }   // 没写连接方式的（部分内建设备）按真实设备算
        let name = ((prop(d, kIOHIDProductKey) ?? "") + (prop(d, kIOHIDManufacturerKey) ?? "")).lowercased()
        return !name.contains("karabiner")
    }

    /// 设备分类缓存（每秒可能上百次回调，避免反复读设备属性）
    private struct Kind { let virtual: Bool; let touchpad: Bool }
    private var kinds: [IOHIDDevice: Kind] = [:]
    private func kind(_ d: IOHIDDevice) -> Kind {
        if let k = kinds[d] { return k }
        let pairs = (IOHIDDeviceGetProperty(d, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]]) ?? []
        let touchpad = pairs.contains { $0[kIOHIDDeviceUsagePageKey] == kHIDPage_Digitizer
            && [kHIDUsage_Dig_TouchPad, 0x0C].contains($0[kIOHIDDeviceUsageKey] ?? -1) }
        let k = Kind(virtual: Self.isVirtual(d), touchpad: touchpad)
        kinds[d] = k
        return k
    }
    /// 移动 / 触控类信号的时间（连续两次才直接唤醒，过滤单次抖动）
    private var lastMotionAt = Date.distantPast

    private func handle(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(el)
        let k = kind(device)
        guard !k.virtual else { return }
        let page = Int(IOHIDElementGetUsagePage(el))
        // 妙控板 / 内建触控板的触摸只走苹果自定义页（0xFF00 多点触控数据），不走通用移动页
        let touch = k.touchpad && page == 0xFF00
        // 只认按键、移动、滚动、触控；忽略其他厂商自定义的周期性上报
        guard touch || [kHIDPage_GenericDesktop, kHIDPage_KeyboardOrKeypad, kHIDPage_Button, kHIDPage_Digitizer, kHIDPage_Consumer].contains(page) else { return }
        if touch { guard IOHIDValueGetLength(value) > 0 else { return } }
        else { guard IOHIDValueGetIntegerValue(value) != 0 else { return } }
        let now = Date()
        lastActiveAt = now
        if !everSeen { everSeen = true; if debugInput { print("PhysicalHID first signal from", Self.prop(device, kIOHIDProductKey) ?? "?") } }
        RealInput.shared.physicalSignal()
        guard Blackout.shared.active else { return }
        // 物理设备的信号软件模拟不出来，本身就证明是真人：直接唤醒，不必等系统事件
        if page == kHIDPage_KeyboardOrKeypad || page == kHIDPage_Button {
            Blackout.shared.realInputDetected()
        } else if page != kHIDPage_Consumer {
            if now.timeIntervalSince(lastMotionAt) < 0.3 { Blackout.shared.realInputDetected() }
            lastMotionAt = now
        }
    }
}

// MARK: - 触发角：亲手把鼠标移到角落停一会 → 黑屏
final class HotCorner {
    static let shared = HotCorner()
    private var timer: Timer?
    private var enteredAt: Date?
    private var needsLeave = false   // 触发过后必须先离开角落才能再次触发

    func start() {
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let s = Settings.shared
        guard s.hotCorner != .off else { enteredAt = nil; return }
        let inCorner = Self.isInCorner(NSEvent.mouseLocation, s.hotCorner, display: s.displayName) && cursorFromRealMove()
        if !inCorner { enteredAt = nil; needsLeave = false; return }
        if Blackout.shared.active || needsLeave { return }
        if enteredAt == nil { enteredAt = Date() }
        if Date().timeIntervalSince(enteredAt!) >= s.cornerDelay {
            needsLeave = true; enteredAt = nil
            Blackout.shared.start()
        }
    }

    /// 光标当前位置必须就是最后一次真实鼠标移动的位置；AI 模拟移动或瞬移过去的对不上
    private func cursorFromRealMove() -> Bool {
        let r = RealInput.shared
        guard r.canTellApart else { return true }
        // AI 刚把光标瞬移过来：这时真人哪怕轻碰一下鼠标也不算「亲手移到角落」
        guard Date().timeIntervalSince(r.lastFakeMoveAt) > 1.0 else { return false }
        guard let cur = CGEvent(source: nil)?.location else { return false }
        return abs(cur.x - r.lastRealLoc.x) < 2 && abs(cur.y - r.lastRealLoc.y) < 2
    }

    static func isInCorner(_ p: NSPoint, _ corner: HotCornerPosition, display: String) -> Bool {
        let named = NSScreen.screens.filter { $0.localizedName == display }
        let m: CGFloat = 3
        for sc in (named.isEmpty ? NSScreen.screens : named) {
            let f = sc.frame
            guard p.x >= f.minX - 1, p.x <= f.maxX + 1, p.y >= f.minY - 1, p.y <= f.maxY + 1 else { continue }
            let left = p.x <= f.minX + m, right = p.x >= f.maxX - m - 1
            let top = p.y >= f.maxY - m - 1, bottom = p.y <= f.minY + m
            switch corner {
            case .topLeft: if left && top { return true }
            case .topRight: if right && top { return true }
            case .bottomLeft: if left && bottom { return true }
            case .bottomRight: if right && bottom { return true }
            case .off: break
            }
        }
        return false
    }
}

// MARK: - 系统触发角（直装版可直接替换；App Store 版沙盒内只能引导用户去系统设置）
enum SystemHotCorner {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    static func openSettings() { NSWorkspace.shared.open(settingsURL) }

    #if !APPSTORE
    /// 当前系统该角的动作代码（0/1 = 无，10 = 关闭显示器，13 = 锁定屏幕 …）
    static func action(at corner: HotCornerPosition) -> Int? {
        guard let key = corner.dockKey else { return nil }
        return UserDefaults(suiteName: "com.apple.dock")?.object(forKey: key) as? Int
    }
    static func hasConflict(_ corner: HotCornerPosition) -> Bool {
        guard let a = action(at: corner) else { return false }
        return a > 1
    }
    static func actionName(_ a: Int) -> String {
        switch a {
        case 2: String(localized: "调度中心"); case 3: String(localized: "应用程序窗口"); case 4: String(localized: "桌面")
        case 5: String(localized: "启动屏幕保护程序"); case 6: String(localized: "停用屏幕保护程序"); case 7: String(localized: "程序坞")
        case 10: String(localized: "关闭显示器"); case 11: String(localized: "启动台")
        case 12: String(localized: "通知中心"); case 13: String(localized: "锁定屏幕"); case 14: String(localized: "快速备忘录")
        default: String(localized: "其他功能")
        }
    }
    /// 把系统该角改成「无操作」，交给 PanelRest
    static func clear(_ corner: HotCornerPosition) {
        guard let key = corner.dockKey else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "com.apple.dock", key, "-int", "1"]
        try? p.run(); p.waitUntilExit()
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        k.arguments = ["Dock"]
        try? k.run()
    }
    #endif
}

// MARK: - 全局快捷键（Carbon，无需任何权限）
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    /// 注册失败（被其他 App 占用）的快捷键序号
    private(set) var failed: Set<Int> = []

    func register() {
        unregister()
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { Blackout.shared.toggle() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        failed = []
        let s = Settings.shared
        for (i, k) in [s.shortcut1, s.shortcut2].enumerated() where k.isSet {
            // 两个快捷键设成同一个：第二个不必再注册，也不算「被其他 App 占用」
            if i == 1, s.shortcut1.isSet, k.keyCode == s.shortcut1.keyCode, k.modifiers == s.shortcut1.modifiers { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53524553), id: UInt32(i + 1))
            if RegisterEventHotKey(UInt32(k.keyCode), UInt32(k.modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                failed.insert(i + 1)
            }
        }
    }
    func unregister() { refs.forEach { UnregisterEventHotKey($0) }; refs = [] }
    /// 至少有一个快捷键注册成功（可以用它唤醒）
    var hasWorkingShortcut: Bool { !refs.isEmpty }
}

// MARK: - 空闲自动黑屏（只按亲手操作计时，AI 在后台操作不会推迟它）
final class IdleWatcher {
    static let shared = IdleWatcher()
    private var timer: Timer?
    private var firedForThisIdle = false
    private var lastBlockedAt = Date.distantPast
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }
    private func tick() {
        let s = Settings.shared
        guard s.idleAutoBlackout else { return }
        // 播放视频、演示等期间系统也不会关屏：同样当作「有人在看」，结束后重新计时
        if !Blackout.shared.active && Self.otherAppKeepsDisplayOn() { lastBlockedAt = Date() }
        let idle = min(RealInput.shared.secondsSinceRealInput, Date().timeIntervalSince(lastBlockedAt))
        if debugInput { print(String(format: "idle tick: real=%.0fs blocked=%.0fs need=%ds", RealInput.shared.secondsSinceRealInput, Date().timeIntervalSince(lastBlockedAt), s.idleMinutes * 60)) }
        if idle < Double(s.idleMinutes * 60) { firedForThisIdle = false; return }
        if !firedForThisIdle && !Blackout.shared.active {
            firedForThisIdle = true
            Blackout.shared.start()
        }
    }
}

// MARK: - 系统自带的「不活跃时关闭显示器」
// 它比 PanelRest 的定时更短时，显示器会先被系统真正关掉（截图、AI 操作会受影响）
enum SystemDisplaySleep {
    /// 当前电源下系统关闭显示器的分钟数；0 = 永不，nil = 读不到
    static var minutes: Int? {
        let key = "State:/IOKit/PowerManagement/CurrentSettings" as CFString
        guard let d = SCDynamicStoreCopyValue(nil, key) as? [String: Any] else { return nil }
        return (d["Display Sleep Timer"] as? NSNumber)?.intValue
    }
    /// 会抢在 PanelRest 前面关闭显示器时，返回系统的分钟数
    static func conflict(idleMinutes: Int) -> Int? {
        guard let m = minutes, m > 0, m <= idleMinutes else { return nil }
        return m
    }
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!)
    }
    /// 弹窗提醒；用户可直接去系统设置调整
    static func alert(systemMinutes m: Int) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = String(localized: "系统会先关闭显示器")
        a.informativeText = String(localized: "系统「关闭显示器」的时间（\(m) 分钟）比这里短，显示器会先被系统关掉。")
        a.addButton(withTitle: String(localized: "打开系统设置"))
        a.addButton(withTitle: String(localized: "好"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { openSettings() }
    }
}

extension IdleWatcher {
    /// 有其他 App 持有「阻止显示器休眠」（视频播放器、Keynote、会议软件等）
    /// 前台 App（例如正在全屏播放视频）要求保持显示器亮着时返回 true。
    /// 后台程序（AI 代理、Claude、下载工具等）的「阻止显示器休眠」不算，否则 AI 干活时定时永远不会触发。
    static func otherAppKeepsDisplayOn() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              front != ProcessInfo.processInfo.processIdentifier else { return false }
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let byPid = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let mine = byPid[NSNumber(value: front)] ?? []
        return mine.contains { a in
            (a[kIOPMAssertionTypeKey as String] as? String) == (kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
                && ((a[kIOPMAssertionLevelKey as String] as? NSNumber)?.intValue ?? 0) > 0
        }
    }
}

// MARK: - 开机自启
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    /// 按设置登记或取消；每次启动都会调用，保证重装、更新后仍然有效
    static func apply() {
        do {
            if Settings.shared.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PanelRest login item: \(error.localizedDescription)")
        }
    }
    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

