import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        let statusBar = StatusBarController(model: model)
        self.statusBar = statusBar

        // 文档截图用的隐藏启动参数（README 生成脚本）
        let arguments = CommandLine.arguments
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
