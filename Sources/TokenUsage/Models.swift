import Foundation

/// V1 支持的订阅数据源（rawValue 同时用作 Keychain 的 account 键）。
enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepseek
    case zaiCodingPlan = "zai-coding-plan"
    case opencodeGo = "opencode-go"
    case chatgpt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .zaiCodingPlan: "Z.AI Coding Plan"
        case .opencodeGo: "OpenCode Go"
        case .chatgpt: "ChatGPT"
        }
    }

    /// 凭据是否走「用户粘贴 key → Keychain」；chatgpt 走 OAuth，直接读 ~/.codex/auth.json。
    var usesStoredKey: Bool { self != .chatgpt }

    /// 小组件圆心 monogram（电池小组件的设备图标位）。
    var monogram: String {
        switch self {
        case .deepseek: "DS"
        case .zaiCodingPlan: "Z"
        case .opencodeGo: "GO"
        case .chatgpt: "AI"
        }
    }
}

/// 单个额度窗口：已用百分比 + 重置时间（缺失为 nil）。
struct UsageWindow: Identifiable, Equatable, Sendable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var id: String { label }

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// DeepSeek 特有：账户余额（多币种账户会有多条，如 CNY + USD，全部展示）。
struct BalanceInfo: Identifiable, Equatable, Sendable {
    let currency: String
    let total: String
    let isAvailable: Bool

    var id: String { currency }

    /// 展示文本：CNY → ¥、USD → $ 前缀，其他币种跟在数字后。
    var displayText: String {
        switch currency {
        case "CNY": "¥\(total)"
        case "USD": "$\(total)"
        default: "\(total) \(currency)"
        }
    }
}

/// 一次成功刷新的统一快照：三个 provider 都归一到这个形状。
struct UsageSnapshot: Equatable, Sendable {
    var windows: [UsageWindow] = []
    var balances: [BalanceInfo] = []
    /// 套餐档位（Z.AI 返回如 "pro"；OpenCode Go 固定 "Go"）。
    var planLevel: String?

    /// 所有窗口里最紧的已用百分比，用于菜单栏标题。
    var worstUsedPercent: Double? {
        windows.map(\.usedPercent).max()
    }
}

extension Double {
    /// 33 → "33"，10.4 → "10.4"：整数不带小数位，非整数保留一位。
    var compactPercentText: String {
        self == self.rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }
}

enum FetchError: LocalizedError, Equatable, Sendable {
    /// 401 / 403：key 失效或无权限。
    case invalidKey
    case http(Int)
    /// 200 但响应里没有可用的窗口（不展示「健康的 0%」假数据）。
    case emptyUsage
    case badResponse
    /// 本地凭据缺失（如未登录 Codex CLI）。
    case credentialsMissing(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: "API key 失效或无权限（401/403）"
        case .http(let code): "服务端返回 HTTP \(code)"
        case .emptyUsage: "响应中没有可用的额度窗口"
        case .badResponse: "响应无法解码"
        case .credentialsMissing(let message): message
        }
    }
}
