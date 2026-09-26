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

    /// 展示风格由设置页决定（默认值倒计时），改完立即生效，无需重启。
    @AppStorage("resetTimeStyle") private var resetTimeStyle = ResetTimeStyle.countdown.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(window.label)
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                // 电池语义：条长 = 剩余额度，与环形图标一致（绿=充足，随消耗缩短变橙/红）
                RemainingBar(remainingPercent: window.remainingPercent, tint: tint)
                Text("剩 \(window.remainingPercent.compactPercentText)%")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
            if let resetsAt = window.resetsAt {
                resetTimeText(resetsAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .padding(.leading, 76)
            }
        }
    }

    /// 倒计时需要逐秒重绘（TimelineView 1 秒节奏）；绝对时间是静态文本，零额外开销。
    @ViewBuilder
    private func resetTimeText(_ resetsAt: Date) -> some View {
        if style == .countdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let countdown = ResetTimeStyle.countdownText(from: context.date, to: resetsAt) {
                    Text("重置 \(countdown) 后")
                } else {
                    Text("即将重置")
                }
            }
        } else {
            Text("重置 \(ResetTimeStyle.absoluteText(resetsAt))")
        }
    }

    private var style: ResetTimeStyle {
        ResetTimeStyle(rawValue: resetTimeStyle) ?? .countdown
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

/// 自绘电池条：胶囊轨道 + 按剩余比例的填充。
/// 不用 ProgressView 的原因（macOS 26 实测）：真实 NSPopover 里 `.tint` 首帧不生效、
/// 回落系统 accent 蓝，要等数值变化触发重绘才上色；纯形状 + 显式颜色完全可控，
/// 顺带免疫「非焦点窗口控件灰显」那类问题（面板未激活时打开也保持正确配色）。
private struct RemainingBar: View {
    let remainingPercent: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(min(max(remainingPercent, 0), 100) / 100)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * fraction, 4))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: remainingPercent)
    }
}
