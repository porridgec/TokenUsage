import Foundation

/// Z.AI Coding Plan 额度查询。
/// 端点契约（AGENTS.md，2026-09 实测）：GET /api/monitor/usage/quota/limit，
/// Bearer + User-Agent: opencode/1.18.31（带此 UA 实测可用）。
/// data.limits[] 里只取 TOKENS_LIMIT；多条用 unit/number 区分窗口
/// （实测 5 小时窗 unit=3,number=5，月窗 unit=6,number=1）。
/// TIME_LIMIT 是附加工具额度（search 等），V1 忽略。
struct ZAIClient: Sendable {
    private static let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    private static let userAgent = "opencode/1.18.31"

    func fetchQuota(key: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.checkStatus(response)
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw FetchError.badResponse
        }
        var windows: [UsageWindow] = []
        for limit in dto.data.limits where limit.type == "TOKENS_LIMIT" {
            guard let percentage = limit.percentage else { continue }
            let reset = limit.nextResetTime.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            windows.append(
                UsageWindow(
                    label: windowLabel(unit: limit.unit, number: limit.number),
                    usedPercent: percentage,
                    resetsAt: reset
                )
            )
        }
        return UsageSnapshot(windows: windows, balances: [], planLevel: dto.data.level)
    }

    /// 窗口语义按实测映射，未知组合退化为通用标签而不是丢数据。
    /// unit 枚举：1=天、3=小时、5=月、6=周（OpenClaw 源码映射 1/3/5 + 官网
    /// 「5 小时 + 每周」双窗口结构确认 6=周；OpenClaw 自己没映射 6，会显示 "Tokens (Limit)"）。
    static func windowLabel(unit: Int?, number: Int?) -> String {
        let n = number ?? 0
        return switch unit {
        case 1: "\(n) 天窗"
        case 3: "\(n) 小时窗"
        case 5: n == 1 ? "本月" : "\(n) 个月窗"
        case 6: "本周"
        default: "窗口 u\(unit ?? -1)×\(n)"
        }
    }

    private struct DTO: Decodable {
        struct DataDTO: Decodable {
            struct LimitDTO: Decodable {
                let type: String
                let unit: Int?
                let number: Int?
                let percentage: Double?
                /// 毫秒时间戳。
                let nextResetTime: Int64?
            }
            let limits: [LimitDTO]
            let level: String?
        }
        let data: DataDTO
    }
}
