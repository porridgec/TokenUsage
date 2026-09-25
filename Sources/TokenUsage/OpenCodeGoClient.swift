import Foundation

/// OpenCode Go 用量查询。
/// 端点契约（AGENTS.md，2026-09 实测，参考实现 TokenBar agent_opencode_go.rs）：
/// GET https://opencode.ai/zen/go/v1/usage，Bearer 认证，不需要 x-opencode-session。
/// 返回 usage.{rolling,weekly,monthly}，percent 为已用百分比，resetsAt 为 ISO8601。
/// 单窗口 percent 越界（>100 或非有限）应丢弃该窗口，不要 clamp 成 100%。
struct OpenCodeGoClient: Sendable {
    private static let url = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    func fetchUsage(key: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.checkStatus(response)
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw FetchError.badResponse
        }
        // 各窗口独立解码：一个坏窗口只丢自己，不影响其余。
        // rolling 实为约 5 小时的滚动窗口，与 Z.AI 的 5 小时窗同名对齐。
        let pairs: [(label: String, window: DTO.Window?)] = [
            ("5 小时窗", dto.usage.rolling),
            ("本周", dto.usage.weekly),
            ("本月", dto.usage.monthly),
        ]
        var windows: [UsageWindow] = []
        for pair in pairs {
            guard let window = pair.window,
                  let percent = window.percent,
                  percent.isFinite,
                  percent >= 0,
                  percent <= 100
            else { continue }
            windows.append(
                UsageWindow(label: pair.label, usedPercent: percent, resetsAt: parseDate(window.resetsAt))
            )
        }
        // 200 但没有任何可用窗口：更可能是坏响应而不是真的 0%，不展示假数据。
        guard !windows.isEmpty else { throw FetchError.emptyUsage }
        return UsageSnapshot(windows: windows, balances: [], planLevel: "Go")
    }

    /// 兼容带 / 不带毫秒的 ISO8601（实测两种都出现过）。
    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: string)
    }

    private struct DTO: Decodable {
        struct Window: Decodable {
            let percent: Double?
            let resetsAt: String?
        }
        struct Windows: Decodable {
            let rolling: Window?
            let weekly: Window?
            let monthly: Window?
        }
        let usage: Windows
    }
}
