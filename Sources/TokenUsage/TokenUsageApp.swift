import SwiftUI
import AppKit

@main
struct TokenUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // SPM executable 没有 Info.plist，用运行时设置代替 LSUIElement：
        // 不出现在 Dock，只以菜单栏形态存在。
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    // 菜单栏图标 / 面板 / 设置窗口都由 AppDelegate + StatusBarController 用 AppKit 管理
    // （原因见 StatusBarController 顶部注释）；Scene 仅作占位。
    var body: some Scene {
        Settings { EmptyView() }
    }
}
