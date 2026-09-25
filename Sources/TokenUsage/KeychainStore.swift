import Foundation
import Security

/// API key 的 Keychain 存取：服务名固定，account 用 ProviderKind 的 rawValue。
/// 约定（AGENTS.md）：key 只存 Keychain，不得写入仓库、UserDefaults 明文或日志输出。
///
/// 跨设备互通（方案 A）：
/// - Mac 端条目以 kSecAttrSynchronizable=true 写入 app 默认 app-id 组
///   （$(AppIdentifierPrefix)com.tokenusage.dev，即 TeamID + bundle id，随 Xcode
///   keychain-access-groups entitlement），iCloud 钥匙串负责跨设备同步。
/// - iOS 端在 entitlements 里声明 keychain-access-groups 包含同一个组
///   （同 Team ID 即合法），即可读取同步过来的条目。
/// - 兜底（方案 D）：QR 离线导入（CredentialTransfer）。
enum KeychainStore {
    private static let service = "com.tokenusage.apikey"

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            "Keychain 操作失败（OSStatus \(statusValue)）"
        }

        var statusValue: OSStatus {
            if case .status(let value) = self { value } else { -1 }
        }
    }

    // MARK: - 对外 API

    /// 写入 key。优先写「可随 iCloud 钥匙串同步」的条目；同步写入失败（如 -34018）
    /// 时退回普通条目，跨设备导入走 QR（CredentialTransfer）。
    /// kSecAttrSynchronizable 不能原地 update，统一「先删再写」。
    static func saveKey(_ key: String, for provider: ProviderKind) throws {
        deleteKey(for: provider)
        let syncStatus = add(key: key, provider: provider, synchronizable: true)
        if syncStatus != errSecSuccess {
            NSLog("TokenUsage[Keychain] sync add failed for %@: %d, falling back to local", provider.rawValue, syncStatus)
            let status = add(key: key, provider: provider, synchronizable: false)
            NSLog("TokenUsage[Keychain] local add status: %d", status)
            guard status == errSecSuccess else {
                throw KeychainError.status(status)
            }
        }
    }

    static func loadKey(for provider: ProviderKind) -> String? {
        var query = baseQuery(provider: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteKey(for provider: ProviderKind) {
        // macOS 26 上 synchronizableAny 的删除查询不匹配非同步条目，
        // 必须按 true/false 各删一遍（都删干净，避免 -25299 重复）。
        for flag in [kCFBooleanTrue as Any, kCFBooleanFalse as Any] {
            var query = baseQuery(provider: provider)
            query[kSecAttrSynchronizable as String] = flag
            SecItemDelete(query as CFDictionary)
        }
    }

    /// 把旧版本条目（不带同步属性）迁移为可同步条目；app 启动时调用一次。
    static func migrateLegacyItems() {
        for provider in ProviderKind.allCases where provider.usesStoredKey {
            // 只查「明确不同步」的旧条目，读到就按新属性重写。
            var legacy = baseQuery(provider: provider)
            legacy[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
            legacy[kSecReturnData as String] = true
            legacy[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(legacy as CFDictionary, &result)
            NSLog("TokenUsage[migrate] %@ legacy(sync=false) query status=%d", provider.rawValue, status)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let key = String(data: data, encoding: .utf8)
            else { continue }
            do {
                try saveKey(key, for: provider)
                NSLog("TokenUsage[migrate] %@ rewritten as synchronizable", provider.rawValue)
            } catch {
                NSLog("TokenUsage[migrate] %@ rewrite failed: %@", provider.rawValue, error.localizedDescription)
            }
        }
    }

    // MARK: - 私有

    private static func baseQuery(provider: ProviderKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            // 同时匹配「可同步 / 不可同步」条目，迁移期与正常期都能读到。
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    private static func add(key: String, provider: ProviderKind, synchronizable: Bool) -> OSStatus {
        var add = baseQuery(provider: provider)
        add[kSecAttrSynchronizable as String] = (synchronizable ? kCFBooleanTrue : kCFBooleanFalse) as Any
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }
}
