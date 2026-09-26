import Testing
import Foundation
@testable import TokenUsage

/// 重置时间展示风格的格式化测试。
/// 倒计时是纯算术，跨年判定只查「有没有年份」——具体字样随系统语言/ICU 版本变，不做精确断言。
@Suite("重置时间展示")
struct ResetTimeStyleTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("倒计时：≥1 天补「N 天」前缀")
    func countdownWithDays() {
        let text = ResetTimeStyle.countdownText(from: epoch, to: epoch.addingTimeInterval(2 * 86_400 + 4 * 3600 + 12 * 60 + 30))
        #expect(text == "2 天 04:12:30")
    }

    @Test("倒计时：不足 1 天给 HH:MM:SS（小时段不补零）")
    func countdownHours() {
        let text = ResetTimeStyle.countdownText(from: epoch, to: epoch.addingTimeInterval(5 * 3600 + 60 + 9))
        #expect(text == "5:01:09")
    }

    @Test("倒计时：不足 1 小时只给 MM:SS")
    func countdownMinutes() {
        let text = ResetTimeStyle.countdownText(from: epoch, to: epoch.addingTimeInterval(12 * 60 + 30))
        #expect(text == "12:30")
    }

    @Test("倒计时：已到期返回 nil（调用方显示「即将重置」）")
    func countdownExpired() {
        #expect(ResetTimeStyle.countdownText(from: epoch, to: epoch) == nil)
        #expect(ResetTimeStyle.countdownText(from: epoch, to: epoch.addingTimeInterval(-5)) == nil)
    }

    @Test("绝对时间：固定中文 24 小时制，同年省略年份、跨年补上")
    func absoluteTextIsChinese() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let target = calendar.date(from: DateComponents(year: 2024, month: 9, day: 27, hour: 20, minute: 52))!
        let sameYear = ResetTimeStyle.absoluteText(
            target,
            now: calendar.date(from: DateComponents(year: 2024, month: 9, day: 26))!,
            locale: ResetTimeStyle.displayLocale,
            timeZone: shanghai
        )
        let crossYear = ResetTimeStyle.absoluteText(
            target,
            now: calendar.date(from: DateComponents(year: 2025, month: 1, day: 5))!,
            locale: ResetTimeStyle.displayLocale,
            timeZone: shanghai
        )
        #expect(sameYear == "9月27日 20:52")
        #expect(crossYear == "2024年9月27日 20:52")
    }

    @Test("默认 locale 就是中文（不跟系统语言）")
    func defaultLocaleIsChinese() {
        #expect(ResetTimeStyle.displayLocale.identifier == "zh_CN")
        #expect(ResetTimeStyle.absoluteText(epoch) == ResetTimeStyle.absoluteText(epoch, locale: ResetTimeStyle.displayLocale))
    }
}
