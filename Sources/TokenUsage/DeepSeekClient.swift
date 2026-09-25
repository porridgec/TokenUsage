import Foundation

/// DeepSeek 余额查询。
/// 端点契约（AGENTS.md，官方文档 api-docs.deepseek.com →「查询余额」）：
/// GET /user/balance，Bearer 认证，返回 is_available + balance_infos[]。
struct DeepSeekClient: Sendable {
    private static let url = URL(string: "https://api.deepseek.com/user/balance")!

    func fetchBalance(key: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.checkStatus(response)
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let dto = try? decoder.decode(DTO.self, from: data) else {
            throw FetchError.badResponse
        }
        // 多币种账户返回多条 balance_infos（如 CNY + USD），全部保留、按接口顺序展示。
        return UsageSnapshot(
            windows: [],
            balances: dto.balanceInfos.map {
                BalanceInfo(currency: $0.currency, total: $0.totalBalance, isAvailable: dto.isAvailable)
            },
            planLevel: nil
        )
    }

    private struct DTO: Decodable {
        struct BalanceInfoDTO: Decodable {
            let currency: String
            let totalBalance: String
        }
        let isAvailable: Bool
        let balanceInfos: [BalanceInfoDTO]
    }
}
