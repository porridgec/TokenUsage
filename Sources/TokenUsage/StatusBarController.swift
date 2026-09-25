import AppKit
import SwiftUI

/// 菜单栏控制器：NSStatusItem（内嵌 SwiftUI 环形图标）+ NSPopover 面板 + NSWindow 设置窗口。
/// - 不用 MenuBarExtra：其 label 无法图标 + 文字并排（组合时只取 Text、丢掉 Image）。
/// - 图标不用 NSImage：macOS 26 会给非 template 的彩色图片自动套圆角玻璃底板（「外方内圆」），
///   改用 NSHostingView 直接嵌 SwiftUI 视图 —— 纯圆环 + 圆心剩余百分比数字。
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var shotPanelWindow: NSWindow?
    private let iconView: PassThroughHostingView<MenuBarIconView>

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.iconView = PassThroughHostingView(
            rootView: MenuBarIconView(value: model.menuBarRingValue())
        )
        super.init()

        if let button = statusItem.button {
            button.addSubview(iconView)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuContent(model: model) { [weak self] in
                self?.openSettings()
            }
        )

        model.didRefresh = { [weak self] in self?.updateButton() }
        updateButton()
    }

    /// 菜单栏图标取值由设置（显示订阅 / 用量维度）决定。
    private func updateButton() {
        iconView.rootView = MenuBarIconView(value: model.menuBarRingValue())
    }

    // MARK: 文档截图支持（README 生成脚本用）

    /// 打开弹出面板（配合 --show-panel）。延迟到状态栏按钮挂载完成后再显示。
    func showPanelForScreenshot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 显示瞬间存下 panel 引用（延迟截取时再取 view.window 可能已为 nil）
            self.shotPanelWindow = self.popover.contentViewController?.view.window
            NSLog("TokenUsage[shot] panel shown, window=%@", self.shotPanelWindow == nil ? "nil" : "ok")
        }
    }

    /// 自拍自家窗口并写 PNG。
    /// - settings：`screencapture -l <windowID>`（本进程窗口免屏幕录制权限）
    /// - popover：NSPopover 的临时面板 screencapture 抓不到，改用 ImageRenderer
    ///   离屏渲染内容视图（macOS 26 SDK 已禁用 CGWindowListCreateImage）。
    func captureWindow(named: String, to path: String) {
        let delay: TimeInterval = named == "settings" ? 0.6 : 2.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            switch named {
            case "settings":
                guard let window = self.settingsWindow else {
                    NSLog("TokenUsage[shot] %@: window not found", named)
                    return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
                try? process.run()
                process.waitUntilExit()
                NSLog("TokenUsage[shot] %@ -> %@ (exit %d)", named, path, process.terminationStatus)
            case "popover":
                // NSPopover 面板无法被 screencapture 截取、ImageRenderer 离屏渲染
                // 又会丢环境配色（ProgressView 变黄块、primary 文字不可读），
                // 改用真实 NSWindow 承载 MenuContent 截图，观感与真机面板一致。
                let window = KeyableBorderlessWindow(
                    contentViewController: NSHostingController(
                        rootView: MenuContent(model: self.model, onOpenSettings: {})
                    )
                )
                window.styleMask = [.borderless]
                window.setContentSize(NSSize(width: 354, height: 470))
                window.center()
                // 激活 + makeKey：非 key 窗口的控件会以灰显（inactive）外观渲染；
                // accessory app 必须先 activate 再 makeKey，顺序反了会静默失败
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeKey()
                NSLog("TokenUsage[shot] window isKey=%d", window.isKeyWindow ? 1 : 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
                    try? process.run()
                    process.waitUntilExit()
                    window.close()
                    NSLog("TokenUsage[shot] popover -> %@ (exit %d)", path, process.terminationStatus)
                }
            default:
                break
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            // 必须先激活 app 再弹面板：accessory app 未激活时弹出的 popover
            // 会以「非焦点」外观渲染（配色全部变灰），需要点一下才恢复。
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(rootView: SettingsView(model: model))
            )
            window.title = "TokenUsage 设置"
            window.setContentSize(NSSize(width: 520, height: 460))
            window.center()
            settingsWindow = window
        }
        // 同 togglePopover：先激活再前置，避免窗口以非焦点（灰显）状态出现
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// 点击穿透的 NSHostingView：让点击落到状态栏按钮上（触发 popover）。
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 无边框窗口默认不能成为 key 窗口（控件会灰显），子类化放行。
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// 菜单栏图标：纯圆环（弧长 = 剩余额度，剩余越多越绿）+ 圆心剩余百分比数字。
struct MenuBarIconView: View {
    let value: AppModel.MenuBarRingValue

    var body: some View {
        ZStack {
            switch value {
            case .percent(let usedPercent):
                let remaining = 100 - usedPercent
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(max(remaining / 100, 0.02), 1))
                    .stroke(
                        UsageRingView.arcColor(usedPercent),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(remainingText(remaining))
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            case .balanceAvailable(let available):
                Circle()
                    .stroke(
                        available ? Color.green : Color.gray.opacity(0.6),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                Text(available ? "¥" : "—")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            case .none:
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 3)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func remainingText(_ remaining: Double) -> String {
        String(Int(remaining.rounded()))
    }
}
