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

/// 重置时间的展示风格（设置页二选一，macOS 面板与 iOS 主界面共享）。
enum ResetTimeStyle: String, CaseIterable, Identifiable, Sendable {
    /// 倒计时：「重置 2 天 04:12:30 后」，逐秒跳动。
    case countdown
    /// 绝对时间：「重置 9月27日 20:52」，跨年时补上年份。
    case absolute

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .countdown: "重置倒计时"
        case .absolute: "重置时间"
        }
    }

    /// 设置页里的示例文案。
    var hint: String {
        switch self {
        case .countdown: "例：重置 2 天 04:12:30 后，逐秒跳动。"
        case .absolute: "例：重置 9月27日 20:52，跨年时自动补年份。"
        }
    }

    /// 倒计时文案：1 天 04:12:30 / 04:12:30 / 12:30（不足 1 小时省略小时段）。
    /// 已到期返回 nil，由调用方显示「即将重置」。
    static func countdownText(from now: Date, to target: Date) -> String? {
        let total = Int(target.timeIntervalSince(now))
        guard total > 0 else { return nil }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours >= 24 {
            return "\(hours / 24) 天 \(String(format: "%02d:%02d:%02d", hours % 24, minutes, seconds))"
        }
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 绝对时间文案：同年内省略年份（否则每月都写「2026年」太啰嗦），跨年补上。
    static func absoluteText(_ date: Date, now: Date = .now, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
            .month(.abbreviated)
            .day()
            .hour()
            .minute()
            .locale(locale)
        if !sameYear {
            style = style.year()
        }
        return date.formatted(style)
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
