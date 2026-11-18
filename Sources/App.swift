import AppKit
import SwiftUI
import ServiceManagement

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // 没有 Dock 图标
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    static var shared: AppDelegate?
    private var statusItem: NSStatusItem?
    private var onboardingWindow: NSWindow?
    private let launchedAt = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        if debugInput { setvbuf(stdout, nil, _IOLBF, 0) }
        Blackout.shared.recoverIfNeeded()
        RealInput.shared.start()
        HotKeys.shared.register()
        HotCorner.shared.start()
        IdleWatcher.shared.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Blackout.shared.wake()
        }
        updateStatusItem()
        listenForControlCenter()
        // 自测：PanelRest --check-playback → 打印「有 App 在播放视频等，要求屏幕保持亮着」的判断结果后退出
        if CommandLine.arguments.contains("--check-playback") {
            print("playback-keeps-display-on=\(IdleWatcher.otherAppKeepsDisplayOn())")
            exit(0)
        }
        // 自测：PanelRest --selftest 3 → 黑屏 3 秒后恢复并退出（不弹引导）
        if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
            let secs = Double(CommandLine.arguments.dropFirst(i + 1).first ?? "") ?? 3
            Blackout.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                Blackout.shared.wake()
                DispatchQueue.main.asyncAfter(deadline: .now() + Settings.shared.fadeInDuration + 0.3) { NSApp.terminate(nil) }
            }
            return
        }
        #if DEBUG
        // 调试版不能成为开机启动项（否则开机会启动编译缓存里的那份）
        try? SMAppService.mainApp.unregister()
        #else
        LoginItem.apply()
        #endif
        if !Settings.shared.onboardingDone || CommandLine.arguments.contains("--onboarding") { showOnboarding() }
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showSettings() }
        }
    }

    func applicationWillTerminate(_ n: Notification) { Blackout.shared.wakeNow() }

    // MARK: 控制中心按钮（扩展发 Darwin 通知；主程序没在运行时用 panelrest://blackout 打开）
    private func listenForControlCenter() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared?.blackoutFromControl() }
        }, "com.denis.panelrest.blackout" as CFString, nil, .deliverImmediately)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "panelrest" && $0.host == "blackout" }) { blackoutFromControl() }
    }
    /// 稍等控制中心面板收起再黑屏；已黑屏时不做事（黑屏中看不到控制中心）
    func blackoutFromControl() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !Blackout.shared.active { Blackout.shared.start() }
        }
    }

    /// 没有 Dock / 菜单栏图标时，在「应用程序」里再次打开 PanelRest 即弹出设置
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        // 开机时登录项可能重复启动一次，前 15 秒的「再次打开」不弹窗
        guard Date().timeIntervalSince(launchedAt) > 15 else { return false }
        Settings.shared.onboardingDone ? showSettings() : showOnboarding()
        return false
    }

    // MARK: 菜单栏：左键弹出设置面板，右键小菜单（设置 / 退出）
    func updateStatusItem() {
        if Settings.shared.showMenuBarIcon {
            ensureStatusItem()
        } else if let it = statusItem, !settingsShown {
            NSStatusBar.system.removeStatusItem(it)
            statusItem = nil
        }
    }
    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        it.button?.image = NSImage(systemSymbolName: "moon.haze", accessibilityDescription: "PanelRest")
        it.button?.target = self
        it.button?.action = #selector(statusClicked(_:))
        it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = it
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            closeSettings()
            let m = NSMenu()
            let settings = NSMenuItem(title: String(localized: "设置…"), action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self
            m.addItem(settings)
            m.addItem(.separator())
            m.addItem(NSMenuItem(title: String(localized: "退出 PanelRest"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem?.menu = m
            sender.performClick(nil)
            statusItem?.menu = nil
        } else if settingsShown {
            closeSettings()
        } else {
            showSettings()
        }
    }
    @objc func openSettings() { showSettings() }

    // MARK: 设置面板（系统 NSPopover：液态玻璃、箭头、圆角都由系统处理）
    private var popover: NSPopover?
    var settingsShown: Bool { popover?.isShown == true }

    /// 从菜单栏图标弹出；图标被关掉时临时放出来，面板关闭后再收起
    func showSettings() {
        ensureStatusItem()
        guard let button = statusItem?.button else { return }
        if popover == nil {
            let p = NSPopover()
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = [.preferredContentSize]
            p.contentViewController = host
            p.behavior = .transient
            p.delegate = self
            popover = p
        }
        NSApp.activate(ignoringOtherApps: true)
        // 刚创建的图标还没排好位置，稍等再弹
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.popover, !p.isShown else { return }
            p.animates = true                    // 弹出 / 收起保留系统淡入淡出
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
            // 切换标签时高度变化不做动画：顶边贴着箭头，底边直接到位，不弹跳
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { p.animates = false }
        }
    }

    func closeSettings() {
        popover?.animates = true
        popover?.performClose(nil)
    }

    func popoverDidClose(_ n: Notification) {
        if !Settings.shared.showMenuBarIcon { updateStatusItem() }
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(onFinish: { [weak self] in
                Settings.shared.onboardingDone = true
                self?.onboardingWindow?.close()
            })))
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        // 引导窗口被直接关掉也算看过，避免每次开机都弹
        if (n.object as? NSWindow) === onboardingWindow { Settings.shared.onboardingDone = true }
    }
}

