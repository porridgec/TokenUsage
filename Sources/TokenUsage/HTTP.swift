import Foundation

/// 三个客户端共用的 HTTP 状态检查：401/403 归一成 invalidKey。
enum HTTP {
    static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw FetchError.invalidKey
        default: throw FetchError.http(http.statusCode)
        }
    }
}
