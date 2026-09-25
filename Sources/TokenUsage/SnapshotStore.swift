import Foundation

/// App → 小组件 的快照共享。
/// 数据流约定（AGENTS.md）：app 每次刷新把快照 JSON 写进 App Group 容器，
/// 小组件只读这份快照，不发起网络请求、不读取 API key。
enum SnapshotStore {
    static let suiteName = "group.com.tokenusage.ios"
    private static let key = "sharedSnapshot"

    /// 小组件圆环展示哪个窗口：app 设置页写入，widget 读取（存 App Group UserDefaults）。
    enum WidgetWindowKind: String, CaseIterable, Sendable {
        case fiveHour = "5h"
        case weekly = "weekly"
        case monthly = "monthly"

        var displayName: String {
            switch self {
            case .fiveHour: "5 小时窗"
            case .weekly: "每周"
            case .monthly: "每月"
            }
        }

        /// 对应快照里的窗口 label（各 provider 命名一致：5 小时窗 / 本周 / 本月）。
        var windowLabel: String {
            switch self {
            case .fiveHour: "5 小时窗"
            case .weekly: "本周"
            case .monthly: "本月"
            }
        }
    }

    private static let windowKindKey = "widgetWindowKind"

    static var preferredWindowKind: WidgetWindowKind {
        get {
            guard let raw = UserDefaults(suiteName: suiteName)?.string(forKey: windowKindKey),
                  let kind = WidgetWindowKind(rawValue: raw)
            else { return .fiveHour }
            return kind
        }
        set {
            UserDefaults(suiteName: suiteName)?.set(newValue.rawValue, forKey: windowKindKey)
        }
    }

    /// 小组件可直接渲染的快照（只含展示所需字段，不含任何 key）。
    struct Snapshot: Codable, Sendable, Equatable {
        struct ProviderSnapshot: Codable, Sendable, Equatable, Identifiable {
            struct Window: Codable, Sendable, Equatable, Identifiable {
                let label: String
                let usedPercent: Double
                let resetsAt: Date?
                var id: String { label }
            }
            var id: String { name }
            let name: String
            let monogram: String
            let planLevel: String?
            let windows: [Window]
            /// DeepSeek 各币种余额展示文本（如 "¥25.31"、"$0.00"），空数组表示无余额类数据。
            let balances: [String]
        }
        let updatedAt: Date
        let providers: [ProviderSnapshot]

        var worstUsedPercent: Double? {
            providers.flatMap(\.windows).map(\.usedPercent).max()
        }

        static let empty = Snapshot(updatedAt: .distantPast, providers: [])
    }

    static func save(providers: [ProviderKind], snapshots: [ProviderKind: UsageSnapshot]) {
        let snapshot = Snapshot(
            updatedAt: Date(),
            providers: providers.compactMap { provider in
                guard let usage = snapshots[provider] else { return nil }
                return Snapshot.ProviderSnapshot(
                    name: provider.displayName,
                    monogram: provider.monogram,
                    planLevel: usage.planLevel,
                    windows: usage.windows.map {
                        Snapshot.ProviderSnapshot.Window(
                            label: $0.label,
                            usedPercent: $0.usedPercent,
                            resetsAt: $0.resetsAt
                        )
                    },
                    balances: usage.balances.map(\.displayText)
                )
            }
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
    }

    static func load() -> Snapshot {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
