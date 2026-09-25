import WidgetKit
import SwiftUI

@main
struct TokenUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenUsageWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SnapshotStore.Snapshot
}

/// 快照由 app 前台刷新写入 App Group 容器，widget 只读，不碰网络和 key。
struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: SnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct TokenUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenUsageWidget", provider: SnapshotTimelineProvider()) { entry in
            TokenUsageWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("订阅额度")
        .description("最紧窗口的用量环形总览")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TokenUsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: Small：环形 + 中心百分比

private struct SmallView: View {
    let entry: SnapshotEntry

    var body: some View {
        if entry.snapshot.providers.isEmpty {
            emptyView
        } else {
            VStack(spacing: 6) {
                ZStack {
                    // 电池语义：弧长与中心数字均为剩余（越绿越健康）
                    UsageRingView(usedPercent: entry.snapshot.worstUsedPercent, lineWidth: 6)
                        .frame(width: 64, height: 64)
                    Text(
                        entry.snapshot.worstUsedPercent
                            .map { "\((100 - $0).compactPercentText)%" } ?? "—"
                    )
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                }
                Text("更新 \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge")
                .font(.title2)
            Text("打开 App 完成配置")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Medium：电池小组件风格——provider 圆环并排（大环粗线），圆心 monogram，下方大号百分比

private struct MediumView: View {
    let entry: SnapshotEntry

    var body: some View {
        if entry.snapshot.providers.isEmpty {
            SmallView(entry: entry).emptyState
        } else {
            HStack(spacing: 10) {
                ForEach(entry.snapshot.providers) { provider in
                    ProviderRingItem(provider: provider)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Text("更新 \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
            }
        }
    }
}

/// 电池小组件风格的单个 provider：环的填充 = 剩余额度（越长越健康），
/// 圆心 monogram，下方大号数值（剩余百分比 / 余额）。
private struct ProviderRingItem: View {
    let provider: SnapshotStore.Snapshot.ProviderSnapshot

    /// 选定窗口的已用百分比（无此窗口时回退最紧窗口）。
    private var usedPercent: Double? {
        let kind = SnapshotStore.preferredWindowKind
        if let matched = provider.windows.first(where: { $0.label == kind.windowLabel }) {
            return matched.usedPercent
        }
        return provider.windows.map(\.usedPercent).max()
    }

    /// DeepSeek 无用量窗口：有余额即满环（绿色 = 账户可用）。
    private var fillPercent: Double {
        guard let used = usedPercent else { return provider.balances.isEmpty ? 0 : 100 }
        return 100 - used
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.28), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(max(fillPercent / 100, 0.02), 1))
                    .stroke(UsageRingView.arcColor(usedPercent ?? 0), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(provider.monogram)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 64, height: 64)
            Text(valueText)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var valueText: String {
        if !provider.balances.isEmpty {
            return provider.balances.first { $0.hasPrefix("¥") } ?? provider.balances.first ?? "—"
        }
        guard let used = usedPercent else { return "—" }
        return "剩 \((100 - used).compactPercentText)%"
    }
}

private extension SmallView {
    var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge")
                .font(.title2)
            Text("打开 App 完成配置")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SnapshotStore.Snapshot {
    /// 占位快照（placeholder 预览用，不含真实数据）。
    static let sample = Self(
        updatedAt: .now,
        providers: [
            .init(
                name: "Z.AI Coding Plan", monogram: "Z", planLevel: "pro",
                windows: [
                    .init(label: "5 小时窗", usedPercent: 34, resetsAt: nil),
                    .init(label: "本周", usedPercent: 51, resetsAt: nil),
                ],
                balances: []
            ),
            .init(
                name: "OpenCode Go", monogram: "GO", planLevel: "Go",
                windows: [
                    .init(label: "5 小时窗", usedPercent: 10, resetsAt: nil),
                    .init(label: "本周", usedPercent: 15, resetsAt: nil),
                    .init(label: "本月", usedPercent: 18, resetsAt: nil),
                ],
                balances: []
            ),
            .init(name: "DeepSeek", monogram: "DS", planLevel: nil, windows: [], balances: ["¥25.31", "$0.00"]),
        ]
    )
}

private extension Double {
    var compactPercent: String {
        self == self.rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }
}

// MARK: - Xcode Canvas 预览


#Preview("Large", as: .systemMedium) {
    TokenUsageWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("Medium", as: .systemMedium) {
    TokenUsageWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("Small", as: .systemSmall) {
    TokenUsageWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("空状态 Small", as: .systemSmall) {
    TokenUsageWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .empty)
}
