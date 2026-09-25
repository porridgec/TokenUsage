import SwiftUI

/// 环形进度图标（电池语义）：弧长 = **剩余**百分比，剩余越多弧越长且越绿；
/// 输入为已用百分比（剩余 = 100 - 已用），颜色分级绿/橙/红。
/// 双端共享：macOS 菜单栏、iOS 主界面与小组件。
struct UsageRingView: View {
    let usedPercent: Double?
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: lineWidth)
            if let used = usedPercent {
                let remaining = 100 - used
                Circle()
                    .trim(from: 0, to: min(max(remaining / 100, 0.02), 1))
                    .stroke(Self.arcColor(used), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    static func arcColor(_ used: Double) -> Color {
        switch used {
        case ..<60: .green
        case ..<85: .orange
        default: .red
        }
    }
}
