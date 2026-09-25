import Foundation

/// ChatGPT（Plus/Pro 订阅）用量查询。
/// 端点契约（AGENTS.md，2026-09 实测 200 + OpenClaw provider-usage.fetch.codex.ts 双重确认）：
/// GET https://chatgpt.com/backend-api/wham/usage
/// 头：Bearer <access_token>、ChatGPT-Account-Id、originator、Accept: application/json
/// 返回 rate_limit.primary_window（5 小时）/ secondary_window（周）的
/// used_percent + reset_at（Unix 秒），以及 plan_type / credits.balance。
/// 凭据不进 Keychain：直接读 Codex CLI 登录写的 ~/.codex/auth.json（tokens.access_token / account_id）。
struct ChatGPTClient: Sendable {
    private static let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    func fetchUsage() async throws -> UsageSnapshot {
        let credentials = try Self.Credentials.load()
        var request = URLRequest(url: Self.url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("tokenusage/0.1", forHTTPHeaderField: "User-Agent")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.checkStatus(response)
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> UsageSnapshot {
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw FetchError.badResponse
        }
        var windows: [UsageWindow] = []
        if let primary = dto.rateLimit?.primaryWindow {
            windows.append(
                UsageWindow(
                    label: windowLabel(windowSeconds: primary.limitWindowSeconds, fallback: "5 小时窗"),
                    usedPercent: primary.usedPercent ?? 0,
                    resetsAt: primary.resetAt.map { Date(timeIntervalSince1970: $0) }
                )
            )
        }
        if let secondary = dto.rateLimit?.secondaryWindow {
            windows.append(
                UsageWindow(
                    label: windowLabel(windowSeconds: secondary.limitWindowSeconds, fallback: "本周"),
                    usedPercent: secondary.usedPercent ?? 0,
                    resetsAt: secondary.resetAt.map { Date(timeIntervalSince1970: $0) }
                )
            )
        }
        guard !windows.isEmpty else { throw FetchError.emptyUsage }
        return UsageSnapshot(windows: windows, balances: [], planLevel: dto.planType)
    }

    /// 主窗口按秒数换算（实测 18000s = 5 小时）；副窗口 ≥7 天标「本周」，
    /// 不足一天标「n 小时窗」，整天数标「n 天窗」。
    static func windowLabel(windowSeconds: Int?, fallback: String) -> String {
        guard let seconds = windowSeconds, seconds > 0 else { return fallback }
        let hours = Int((Double(seconds) / 3600).rounded())
        if hours >= 168 { return "本周" }
        if hours >= 24 { return "\(hours / 24) 天窗" }
        return "\(hours) 小时窗"
    }

    // MARK: 凭据

    struct Credentials: Sendable {
        let accessToken: String
        let accountId: String?

        static var authFileURL: URL {
            #if os(macOS)
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
            #else
            // iOS 无 Codex CLI，此路径不会被使用（availableProviders 已按平台过滤）。
            URL(fileURLWithPath: "/dev/null")
            #endif
        }

        static func exists() -> Bool {
            #if os(macOS)
            FileManager.default.fileExists(atPath: authFileURL.path)
            #else
            false
            #endif
        }

        static func load() throws -> Credentials {
            #if os(macOS)
            guard let data = try? Data(contentsOf: authFileURL),
                  let dto = try? JSONDecoder().decode(AuthDTO.self, from: data),
                  let token = dto.tokens?.accessToken, !token.isEmpty
            else {
                throw FetchError.credentialsMissing(
                    "未找到 Codex CLI 登录凭据（~/.codex/auth.json）。\n请先在终端运行一次 codex 完成 ChatGPT 登录。"
                )
            }
            // 401 时提示跑一次 codex 刷新 token（V1 不做自动刷新，避免 refresh token 轮换风险）。
            return Credentials(accessToken: token, accountId: dto.tokens?.accountId)
            #else
            throw FetchError.credentialsMissing("iOS 版暂不支持 ChatGPT 数据源")
            #endif
        }

        private struct AuthDTO: Decodable {
            struct TokensDTO: Decodable {
                let accessToken: String
                let accountId: String?

                enum CodingKeys: String, CodingKey {
                    case accessToken = "access_token"
                    case accountId = "account_id"
                }
            }
            let tokens: TokensDTO?
        }
    }

    // MARK: 响应模型

    private struct DTO: Decodable {
        struct RateLimit: Decodable {
            struct Window: Decodable {
                let usedPercent: Double?
                let limitWindowSeconds: Int?
                /// Unix 秒。
                let resetAt: Double?

                enum CodingKeys: String, CodingKey {
                    case usedPercent = "used_percent"
                    case limitWindowSeconds = "limit_window_seconds"
                    case resetAt = "reset_at"
                }
            }
            let primaryWindow: Window?
            let secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }
        let rateLimit: RateLimit?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
            case planType = "plan_type"
        }
    }
}
