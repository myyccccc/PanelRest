import WidgetKit
import SwiftUI
import AppIntents
import AppKit

// 控制中心 / 菜单栏里的「立即黑屏」按钮（macOS 26+）。
// 用户在「控制中心 › 编辑控制」里添加，可以拖动位置、调大小。
// 扩展本身不能改显示器：点一下只是通知 PanelRest 主程序去黑屏。

@main
struct PanelRestControlsBundle: WidgetBundle {
    var body: some Widget { BlackoutControl() }
}

struct BlackoutControl: ControlWidget {
    static let kind = "com.denis.panelrest.blackout"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: BlackoutIntent()) {
                Label("立即黑屏", systemImage: "moon.haze")
            }
        }
        .displayName("立即黑屏")
        .description("屏幕全黑，后台照常运行")
    }
}

struct BlackoutIntent: AppIntent {
    static let title: LocalizedStringResource = "立即黑屏"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.denis.panelrest").isEmpty
        if running {
            // 主程序在运行：发 Darwin 通知（沙盒内允许），主程序收到后黑屏
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName("com.denis.panelrest.blackout" as CFString), nil, nil, true)
        } else if let url = URL(string: "panelrest://blackout") {
            // 没在运行：用网址打开它，启动后再黑屏
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}
