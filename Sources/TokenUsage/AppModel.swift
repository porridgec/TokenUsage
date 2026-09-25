import Foundation
import Observation
#if os(iOS)
import WidgetKit
#endif

/// 全局状态：已配置的 provider、各家的最新快照 / 错误、刷新调度。
/// 每 5 分钟自动刷新一次；打开菜单面板也会触发一次。
@MainActor
@Observable
final class AppModel {
    /// 当前配置了 key 的 provider（读 Keychain 得出，保存 / 删除后刷新）。
    private(set) var providers: [ProviderKind] = []
    private(set) var snapshots: [ProviderKind: UsageSnapshot] = [:]
    private(set) var errors: [ProviderKind: String] = [:]
    private(set) var lastRefreshAt: Date?
    private(set) var isRefreshing = false

    /// 菜单栏环形图标的取值。
    enum MenuBarRingValue {
        /// 已用百分比（环长 = 已用，颜色按用量分级）
        case percent(Double)
        /// 余额维度：满绿环 = 可用，灰环 = 不可用
        case balanceAvailable(Bool)
        /// 无数据
        case none
    }

    /// 按设置计算菜单栏图标取值。
    /// - providerRaw："all"（默认，全部）或 ProviderKind.rawValue
    /// - metricRaw："tightest"（默认）/ "5h" / "weekly" / "monthly" / "balance"
    /// 所选维度无数据时回退到最紧窗口。
    func menuBarRingValue() -> MenuBarRingValue {
        let defaults = UserDefaults.standard
        let providerRaw = defaults.string(forKey: "menuBarProvider") ?? "all"
        let metricRaw = defaults.string(forKey: "menuBarMetric") ?? "tightest"

        let candidates = snapshots.keys.filter { providerRaw == "all" || $0.rawValue == providerRaw }

        switch metricRaw {
        case "balance":
            for provider in candidates {
                if let balance = snapshots[provider]?.balances.first(where: \.isAvailable) {
                    _ = balance
                    return .balanceAvailable(true)
                }
            }
            for provider in candidates where !(snapshots[provider]?.balances.isEmpty ?? true) {
                return .balanceAvailable(false)
            }
            return .none
        case "5h", "weekly", "monthly":
            let label = switch metricRaw {
            case "5h": "5 小时窗"
            case "weekly": "本周"
            default: "本月"
            }
            let values = candidates.compactMap { provider in
                snapshots[provider]?.windows.first(where: { $0.label == label })?.usedPercent
            }
            if let worst = values.max() {
                return .percent(worst)
            }
        default:
            break
        }

        // 最紧窗口（默认，或所选维度无数据时的回退）
        let all = candidates.flatMap { snapshots[$0]?.windows ?? [] }.map(\.usedPercent)
        guard let worst = all.max() else { return .none }
        return .percent(worst)
    }

    /// 菜单栏图标设置变化后调用：立即重绘图标（不重新拉网络）。
    func menuBarSettingsChanged() {
        didRefresh?()
    }

    private var autoRefreshTask: Task<Void, Never>?

    /// 每次刷新完成后回调（StatusBarController 用它更新菜单栏标题/图标）。
    var didRefresh: (() -> Void)?

    init() {
        KeychainStore.migrateLegacyItems()
        if ProcessInfo.processInfo.arguments.contains("--demo-data") {
            // 文档截图用演示数据（README 截图），不触发网络与定时刷新
            applyDemoData()
        } else {
            reloadProviders()
            startAutoRefresh()
        }
    }

    private func applyDemoData() {
        providers = [.deepseek, .zaiCodingPlan, .opencodeGo]
        snapshots = [
            .zaiCodingPlan: UsageSnapshot(
                windows: [
                    UsageWindow(label: "5 小时窗", usedPercent: 34, resetsAt: Date().addingTimeInterval(3_600)),
                    UsageWindow(label: "本周", usedPercent: 51, resetsAt: Date().addingTimeInterval(172_800)),
                ],
                planLevel: "pro"
            ),
            .opencodeGo: UsageSnapshot(
                windows: [
                    UsageWindow(label: "5 小时窗", usedPercent: 10, resetsAt: Date().addingTimeInterval(3_600)),
                    UsageWindow(label: "本周", usedPercent: 15, resetsAt: Date().addingTimeInterval(200_000)),
                    UsageWindow(label: "本月", usedPercent: 18, resetsAt: Date().addingTimeInterval(1_000_000)),
                ],
                planLevel: "Go"
            ),
            .deepseek: UsageSnapshot(
                balances: [
                    BalanceInfo(currency: "CNY", total: "25.31", isAvailable: true),
                    BalanceInfo(currency: "USD", total: "0.00", isAvailable: true),
                ]
            ),
        ]
        lastRefreshAt = Date()
        didRefresh?()
    }

    func isConfigured(_ provider: ProviderKind) -> Bool {
        providers.contains(provider)
    }

    /// 菜单栏标题：所有窗口里最紧的已用百分比。
    var worstUsedPercent: Double? {
        snapshots.values.flatMap(\.windows).map(\.usedPercent).max()
    }

    /// 当前平台上可用的 provider：ChatGPT 凭据来自 ~/.codex/auth.json，仅 macOS 提供。
    static var availableProviders: [ProviderKind] {
        #if os(macOS)
        ProviderKind.allCases
        #else
        ProviderKind.allCases.filter(\.usesStoredKey)
        #endif
    }

    func reloadProviders() {
        providers = Self.availableProviders.filter { provider in
            provider.usesStoredKey
                ? KeychainStore.loadKey(for: provider) != nil
                : ChatGPTClient.Credentials.exists()
        }
        // 清掉已删除 provider 的残留快照，避免菜单栏标题吃到旧数据。
        for stale in snapshots.keys where !providers.contains(stale) {
            snapshots[stale] = nil
            errors[stale] = nil
        }
    }

    func refreshAll() async {
        reloadProviders()
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 并发拉取三家；错误就地转成展示文案（FetchOutcome 保证 Sendable）。
        let results = await withTaskGroup(of: (ProviderKind, FetchOutcome).self) { group in
            for provider in providers {
                let key = provider.usesStoredKey ? KeychainStore.loadKey(for: provider) : nil
                if provider.usesStoredKey && key == nil { continue }
                group.addTask {
                    switch await Self.fetch(provider: provider, key: key) {
                    case .success(let snapshot):
                        return (provider, FetchOutcome(snapshot: snapshot))
                    case .failure(let error):
                        return (provider, FetchOutcome(errorMessage: Self.describe(error)))
                    }
                }
            }
            var collected: [(ProviderKind, FetchOutcome)] = []
            for await pair in group { collected.append(pair) }
            return collected
        }

        for (provider, outcome) in results {
            if let snapshot = outcome.snapshot {
                snapshots[provider] = snapshot
                errors[provider] = nil
            } else if let message = outcome.errorMessage {
                errors[provider] = message
            }
        }
        lastRefreshAt = Date()
        didRefresh?()
        // iOS：把最新快照写入 App Group 容器，供桌面小组件读取（widget 不碰网络和 key）。
        #if os(iOS)
        SnapshotStore.save(providers: providers, snapshots: snapshots)
        // 立即请求刷新小组件时间线，不必等 30 分钟周期
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// key 保存 / 删除后的入口：刷新配置并立即拉一次。
    func providerDidChange() async {
        reloadProviders()
        await refreshAll()
    }

    private func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    /// 一次拉取的结果：成功给快照，失败给文案（String 保证跨任务传递）。
    private struct FetchOutcome: Sendable {
        var snapshot: UsageSnapshot?
        var errorMessage: String?

        init(snapshot: UsageSnapshot) {
            self.snapshot = snapshot
            self.errorMessage = nil
        }

        init(errorMessage: String) {
            self.snapshot = nil
            self.errorMessage = errorMessage
        }
    }

    private nonisolated static func fetch(provider: ProviderKind, key: String?) async -> Result<UsageSnapshot, any Error> {
        do {
            let snapshot: UsageSnapshot
            switch provider {
            case .deepseek: snapshot = try await DeepSeekClient().fetchBalance(key: key ?? "")
            case .zaiCodingPlan: snapshot = try await ZAIClient().fetchQuota(key: key ?? "")
            case .opencodeGo: snapshot = try await OpenCodeGoClient().fetchUsage(key: key ?? "")
            case .chatgpt:
                #if os(macOS)
                snapshot = try await ChatGPTClient().fetchUsage()
                #else
                throw FetchError.credentialsMissing("iOS 版暂不支持 ChatGPT 数据源")
                #endif
            }
            return .success(snapshot)
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
