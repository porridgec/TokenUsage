import Foundation

/// Mac → iOS 的凭据离线导入（方案 D，iCloud 钥匙串的兜底）。
/// 格式：`tokenusage-import:v1:<base64url(JSON)>`，JSON 为 `{keys: {provider rawValue: key}}`。
/// Mac 侧「导出到 iOS」生成二维码，iOS 侧扫码或粘贴导入。
enum CredentialTransfer {
    private static let prefix = "tokenusage-import:v1:"

    struct Payload: Codable {
        var keys: [String: String]
    }

    /// 打包成导入串（返回值包含明文 key，只用于生成二维码 / 粘贴，不得写日志或仓库）。
    static func encode(keys: [ProviderKind: String]) -> String? {
        var raw: [String: String] = [:]
        for (provider, key) in keys {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                raw[provider.rawValue] = trimmed
            }
        }
        guard !raw.isEmpty, let data = try? JSONEncoder().encode(Payload(keys: raw)) else {
            return nil
        }
        var base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while base64.count % 4 != 0 { base64 += "=" }
        return prefix + base64
    }

    /// 解析导入串；非本格式或无可识别 provider 时返回 nil。
    static func decode(_ string: String) -> [ProviderKind: String]? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        var base64 = String(trimmed.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        var result: [ProviderKind: String] = [:]
        for (rawValue, key) in payload.keys {
            if let provider = ProviderKind(rawValue: rawValue), !key.isEmpty {
                result[provider] = key
            }
        }
        return result.isEmpty ? nil : result
    }
}
