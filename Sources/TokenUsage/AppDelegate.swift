import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 文档截图用的隐藏启动参数（README 生成脚本）。
        // --appearance=dark|light：固定外观，避免 README 截图跟着系统外观设置变来变去
        // （系统外观与 app 域的 AppleInterfaceStyle 都压不住，只能在运行时设 NSApp.appearance）
        let arguments = CommandLine.arguments
        for argument in arguments where argument.hasPrefix("--appearance=") {
            let name = String(argument.dropFirst("--appearance=".count))
            NSApp.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
        }

        let model = AppModel()
        self.model = model
        let statusBar = StatusBarController(model: model)
        self.statusBar = statusBar

        // 文档截图用的隐藏启动参数（README 生成脚本）
        if arguments.contains("--show-panel") {
            statusBar.showPanelForScreenshot()
        }
        if arguments.contains("--show-settings") {
            statusBar.openSettings()
        }
        for argument in arguments where argument.hasPrefix("--shot=") {
            let value = String(argument.dropFirst("--shot=".count))
            let parts = value.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            statusBar.captureWindow(named: String(parts[0]), to: String(parts[1]))
        }
    }
}
