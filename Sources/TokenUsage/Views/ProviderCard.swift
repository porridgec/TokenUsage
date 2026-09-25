import SwiftUI

// 以下两个视图双端共享（macOS 菜单栏面板 / iOS 主界面）。

/// 单个 provider 的额度卡片。
struct ProviderCard: View {
    let provider: ProviderKind
    let snapshot: UsageSnapshot?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName).font(.headline)
                Spacer()
                if let planLevel = snapshot?.planLevel {
                    Text(planLevel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quinary, in: Capsule())
                }
            }

            if let snapshot {
                ForEach(snapshot.windows) { window in
                    WindowRow(window: window)
                }
                // 多币种余额逐行展示（DeepSeek 账户可能同时有 CNY 和 USD）
                ForEach(snapshot.balances) { balance in
                    Text("余额 \(balance.displayText)")
                        .font(.subheadline)
                        .foregroundStyle(balance.isAvailable ? .primary : .secondary)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quinary.opacity(0.5))
        )
    }
}

/// 单个窗口行：标签 + 用量条 + 剩余百分比 + 重置时间。
struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(window.label)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                // 电池语义：条长 = 剩余额度，与环形图标一致（绿=充足，随消耗缩短变橙/红）
                ProgressView(value: min(max(window.remainingPercent, 0), 100), total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint)
                Text("剩 \(window.remainingPercent.compactPercentText)%")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            if let resetsAt = window.resetsAt {
                Text("重置 \(resetsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 72)
            }
        }
    }

    /// 剩余 <15% 红、<40% 橙、≥40% 绿（与环形图标阈值一致）。
    private var tint: Color {
        switch window.remainingPercent {
        case ..<15: .red
        case ..<40: .orange
        default: .green
        }
    }
}
