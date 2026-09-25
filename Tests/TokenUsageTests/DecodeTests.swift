import Testing
import Foundation
@testable import TokenUsage

/// 三个客户端的解码测试。
/// fixture 全部来自 2026-09 的真实响应（记录在 AGENTS.md），
/// 端点或字段语义变化时先改这里再动实现。
@Suite("客户端解码")
struct DecodeTests {
    // MARK: DeepSeek

    @Test("DeepSeek：多币种余额全部解码")
    func deepSeekBalance() throws {
        // 多币种账户实测形态：CNY + USD 各一条（接口顺序不保证，解码须全部保留）
        let data = Data(
            """
            {"is_available":true,"balance_infos":[
              {"currency":"CNY","total_balance":"25.31","granted_balance":"0.00","topped_up_balance":"25.31"},
              {"currency":"USD","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}
            ]}
            """.utf8
        )
        let snapshot = try DeepSeekClient.decode(data)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.balances.count == 2)
        let cny = try #require(snapshot.balances.first { $0.currency == "CNY" })
        #expect(cny.total == "25.31")
        #expect(cny.displayText == "¥25.31")
        #expect(cny.isAvailable)
        let usd = try #require(snapshot.balances.first { $0.currency == "USD" })
        #expect(usd.displayText == "$0.00")
    }

    // MARK: Z.AI

    @Test("Z.AI：多窗口 + 档位，忽略 TIME_LIMIT")
    func zaiWindows() throws {
        // 2026-09 实测响应（脱敏后结构原样）
        let data = Data(
            """
            {"code":200,"msg":"Operation successful","data":{"limits":[
              {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":1,"nextResetTime":1790201414056},
              {"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":33,"nextResetTime":1790316633984},
              {"type":"TIME_LIMIT","unit":5,"number":1,"usage":1000,"currentValue":0,"remaining":1000,"percentage":0,"nextResetTime":1792563033998,"usageDetails":[{"modelCode":"search-prime","usage":0}]}
            ],"level":"pro"},"success":true}
            """.utf8
        )
        let snapshot = try ZAIClient.decode(data)
        #expect(snapshot.planLevel == "pro")
        #expect(snapshot.windows.count == 2)

        let fiveHour = try #require(snapshot.windows.first { $0.label == "5 小时窗" })
        #expect(fiveHour.usedPercent == 1)
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1_790_201_414.056))

        let monthly = try #require(snapshot.windows.first { $0.label == "本周" })
        #expect(monthly.usedPercent == 33)
    }

    @Test("Z.AI：窗口标签映射与未知组合回退")
    func zaiLabels() {
        #expect(ZAIClient.windowLabel(unit: 3, number: 5) == "5 小时窗")
        #expect(ZAIClient.windowLabel(unit: 6, number: 1) == "本周")
        #expect(ZAIClient.windowLabel(unit: 5, number: 1) == "本月")
        #expect(ZAIClient.windowLabel(unit: 1, number: 30) == "30 天窗")
        #expect(ZAIClient.windowLabel(unit: 9, number: 2) == "窗口 u9×2")
    }

    // MARK: OpenCode Go

    @Test("OpenCode Go：三窗口解码，毫秒时间戳可解析")
    func goWindows() throws {
        let data = Data(
            """
            {"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-09-23T22:14:31.419Z"},
                      "weekly":{"status":"ok","percent":15,"resetsAt":"2026-09-28T00:00:00.000Z"},
                      "monthly":{"status":"ok","percent":18,"resetsAt":"2026-10-09T02:18:25.000Z"}}}
            """.utf8
        )
        let snapshot = try OpenCodeGoClient.decode(data)
        #expect(snapshot.planLevel == "Go")
        #expect(snapshot.windows.map(\.label) == ["5 小时窗", "本周", "本月"])
        #expect(snapshot.windows.map(\.usedPercent) == [0, 15, 18])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let rolling = try #require(snapshot.windows.first?.resetsAt)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rolling)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 23)
        #expect(parts.hour == 22 && parts.minute == 14 && parts.second == 31)
    }

    @Test("OpenCode Go：越界窗口丢弃而不是 clamp，合法窗口保留")
    func goOutOfRangeWindowsDrop() throws {
        let data = Data(
            """
            {"usage":{"rolling":{"percent":140.0,"resetsAt":"2026-09-23T22:14:31.419Z"},
                      "weekly":{"percent":63.0},
                      "monthly":{"percent":-5.0}}}
            """.utf8
        )
        let snapshot = try OpenCodeGoClient.decode(data)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].label == "本周")
        #expect(snapshot.windows[0].usedPercent == 63)
        #expect(snapshot.windows[0].resetsAt == nil)
    }

    @Test("OpenCode Go：全部窗口无效时报 emptyUsage 而不是假 0%")
    func goAllInvalidThrows() {
        let data = Data(
            """
            {"usage":{"rolling":{"percent":200.0},"weekly":{"percent":null}}}
            """.utf8
        )
        #expect(throws: FetchError.emptyUsage) {
            _ = try OpenCodeGoClient.decode(data)
        }
    }

    // MARK: ChatGPT

    @Test("ChatGPT：5 小时窗 + 周窗 + 套餐档位")
    func chatgptWindows() throws {
        // 2026-09-24 实测响应（Plus 订阅，脱敏后结构原样）
        let data = Data(
            """
            {"user_id":"user-x","account_id":"","email":"x@y.z","plan_type":"plus",
             "rate_limit":{"allowed":true,"limit_reached":false,
               "primary_window":{"used_percent":6,"limit_window_seconds":18000,"reset_after_seconds":3618,"reset_at":1790191057},
               "secondary_window":{"used_percent":78,"limit_window_seconds":604800,"reset_after_seconds":242968,"reset_at":1790430407}},
             "credits":{"has_credits":false,"balance":"0"}}
            """.utf8
        )
        let snapshot = try ChatGPTClient.decode(data)
        #expect(snapshot.planLevel == "plus")
        #expect(snapshot.windows.count == 2)

        let fiveHour = try #require(snapshot.windows.first)
        #expect(fiveHour.label == "5 小时窗")
        #expect(fiveHour.usedPercent == 6)
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1_790_191_057))

        let weekly = try #require(snapshot.windows.last)
        #expect(weekly.label == "本周")
        #expect(weekly.usedPercent == 78)
    }

    @Test("ChatGPT：窗口标签按秒数换算")
    func chatgptLabels() {
        #expect(ChatGPTClient.windowLabel(windowSeconds: 18_000, fallback: "") == "5 小时窗")
        #expect(ChatGPTClient.windowLabel(windowSeconds: 604_800, fallback: "") == "本周")
        #expect(ChatGPTClient.windowLabel(windowSeconds: 86_400, fallback: "") == "1 天窗")
        #expect(ChatGPTClient.windowLabel(windowSeconds: nil, fallback: "5 小时窗") == "5 小时窗")
    }

    // MARK: 凭据互通

    @Test("CredentialTransfer：导入串编解码往返")
    func credentialTransferRoundTrip() throws {
        let keys: [ProviderKind: String] = [
            .deepseek: "sk-ds-test-123",
            .zaiCodingPlan: "sk-zai-test-456",
            .opencodeGo: "sk-go-test-789",
        ]
        let payload = try #require(CredentialTransfer.encode(keys: keys))
        #expect(payload.hasPrefix("tokenusage-import:v1:"))
        let decoded = try #require(CredentialTransfer.decode(payload))
        #expect(decoded == keys)
    }

    @Test("CredentialTransfer：拒绝空串 / 非本格式 / 空 key")
    func credentialTransferRejects() {
        #expect(CredentialTransfer.encode(keys: [:]) == nil)
        #expect(CredentialTransfer.encode(keys: [.deepseek: "  "]) == nil)
        #expect(CredentialTransfer.decode("hello world") == nil)
        #expect(CredentialTransfer.decode("tokenusage-import:v1:not-base64!!") == nil)
        // 只有未知 provider 的 payload 视为无效
        let json = #"{"keys":{"unknown":"x"}}"#
        #expect(CredentialTransfer.decode(
            "tokenusage-import:v1:" + Data(json.utf8)
                .base64EncodedString().replacingOccurrences(of: "+", with: "-")
        ) == nil)
    }

    // MARK: 共享模型

    @Test("快照：worstUsedPercent 取所有窗口最大值")
    func worstUsedPercent() {
        var snapshot = UsageSnapshot()
        snapshot.windows = [
            UsageWindow(label: "本周", usedPercent: 15, resetsAt: nil),
            UsageWindow(label: "本月", usedPercent: 18, resetsAt: nil),
        ]
        #expect(snapshot.worstUsedPercent == 18)
        #expect(UsageSnapshot().worstUsedPercent == nil)
    }
}
