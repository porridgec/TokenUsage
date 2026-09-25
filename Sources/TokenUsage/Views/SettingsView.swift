import SwiftUI
#if os(iOS)
import WidgetKit
#endif

/// 设置窗口：管理三个 provider 的 API key（只存 Keychain）。
struct SettingsView: View {
    let model: AppModel

    @State private var drafts: [ProviderKind: String] = [:]
    @State private var keychainErrorMessage: String?
    @State private var showsQRExport = false
    @State private var showsScanner = false
    #if os(macOS)
    @AppStorage("menuBarProvider") private var menuBarProvider = "all"
    @AppStorage("menuBarMetric") private var menuBarMetric = "tightest"
    #endif
    #if os(iOS)
    /// 小组件圆环窗口选择：直写 App Group（widget 同源读取），改动后立刻刷新小组件。
    @AppStorage(
        "widgetWindowKind",
        store: UserDefaults(suiteName: SnapshotStore.suiteName)
    )
    private var widgetWindowKind: SnapshotStore.WidgetWindowKind = .fiveHour
    #endif

    var body: some View {
        Form {
            ForEach(ProviderKind.allCases.filter(\.usesStoredKey)) { provider in
                ProviderKeySection(
                    provider: provider,
                    model: model,
                    keyText: keyBinding(for: provider),
                    onSave: { save(provider) },
                    onRemove: { remove(provider) }
                )
            }
            #if os(macOS)
            chatgptSection
            Section("菜单栏图标") {
                Picker("显示订阅", selection: $menuBarProvider) {
                    Text("全部").tag("all")
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .onChange(of: menuBarProvider) {
                    model.menuBarSettingsChanged()
                }
                Picker("用量维度", selection: $menuBarMetric) {
                    Text("最紧窗口").tag("tightest")
                    Text("5 小时窗").tag("5h")
                    Text("每周").tag("weekly")
                    Text("每月").tag("monthly")
                    Text("余额").tag("balance")
                }
                .onChange(of: menuBarMetric) {
                    model.menuBarSettingsChanged()
                }
                Text("环长 = 已用百分比（绿→橙→红）；余额维度仅 DeepSeek 有数据，满绿环 = 可用。所选维度无数据时回退到最紧窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("iOS 导入") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("导出到 iOS（二维码）…") { showsQRExport = true }
                    Text("把已保存的 API key 打包成二维码，用 iPhone 版「设置 → 从 Mac 导入」扫码，离线完成导入。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            #else
            Section("从 Mac 导入") {
                Button("扫码 / 粘贴导入…") { showsScanner = true }
            }
            Section("小组件") {
                Picker("圆环显示窗口", selection: $widgetWindowKind) {
                    ForEach(SnapshotStore.WidgetWindowKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: widgetWindowKind) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                Text("Medium 小组件每个圆环取该窗口的已用百分比；provider 无此窗口时回退到最紧窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
            Section("说明") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key 仅存入钥匙串（Keychain），不写入仓库、UserDefaults 或日志。")
                    Text("iPhone 版可在「设置 → 从 Mac 导入」扫码或粘贴导入。")
                    Text("删除后界面会立即移除该数据源。")
                    if let keychainErrorMessage {
                        Text(keychainErrorMessage).foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .sheet(isPresented: $showsQRExport) {
            QRExportView()
        }
        #else
        .sheet(isPresented: $showsScanner) {
            QRScannerScreen(model: model)
        }
        #endif
    }

    /// ChatGPT 订阅走 Codex CLI 的 OAuth 凭据（~/.codex/auth.json），不需要粘贴 key。
    private var chatgptSection: some View {
        Section("ChatGPT（Plus / Pro 订阅）") {
            VStack(alignment: .leading, spacing: 6) {
                Text("通过 Codex CLI 登录后自动读取 ~/.codex/auth.json，无需粘贴 key。")
                Text(model.isConfigured(.chatgpt)
                    ? "✓ 已检测到登录凭据"
                    : "✗ 未检测到：请先在终端运行一次 codex 完成 ChatGPT 登录")
                Text("token 过期（401）时在终端运行一次 codex 即可刷新。")
            }
            .font(.caption)
            .foregroundStyle(model.isConfigured(.chatgpt) ? .secondary : Color.orange)
        }
    }

    private func keyBinding(for provider: ProviderKind) -> Binding<String> {
        Binding(
            get: { drafts[provider] ?? "" },
            set: { drafts[provider] = $0 }
        )
    }

    private func save(_ provider: ProviderKind) {
        let key = (drafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainStore.saveKey(key, for: provider)
            keychainErrorMessage = nil
        } catch {
            keychainErrorMessage = error.localizedDescription
            return
        }
        drafts[provider] = nil
        Task { await model.providerDidChange() }
    }

    private func remove(_ provider: ProviderKind) {
        KeychainStore.deleteKey(for: provider)
        drafts[provider] = nil
        model.reloadProviders()
        Task { await model.refreshAll() }
    }
}

/// 单个 provider 的 key 编辑区块。
private struct ProviderKeySection: View {
    let provider: ProviderKind
    let model: AppModel
    @Binding var keyText: String
    let onSave: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Section(provider.displayName) {
            SecureField("API Key", text: $keyText)
                .onSubmit(onSave)
            HStack {
                Button("保存并刷新", action: onSave)
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("删除", role: .destructive, action: onRemove)
                    .disabled(!model.isConfigured(provider))
                Spacer()
                if model.isConfigured(provider) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(model.errors[provider] == nil ? Color.secondary : Color.red)
                }
            }
        }
    }

    private var statusText: String {
        if model.errors[provider] != nil {
            return "已配置 · 上次刷新出错"
        }
        return "已配置 · 上次刷新正常"
    }
}

#if os(macOS)
import CoreImage.CIFilterBuiltins

/// 「导出到 iOS」面板：把已保存的 key 打包成二维码。
private struct QRExportView: View {
    private var payload: String? {
        var keys: [ProviderKind: String] = [:]
        for provider in ProviderKind.allCases where provider.usesStoredKey {
            if let key = KeychainStore.loadKey(for: provider) {
                keys[provider] = key
            }
        }
        return CredentialTransfer.encode(keys: keys)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("用 iPhone 扫码导入").font(.headline)
            if let payload, let image = QRCodeGenerator.image(for: payload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .frame(width: 240, height: 240)
            } else {
                Text("没有可导出的 key")
                    .frame(width: 240, height: 240)
                    .foregroundStyle(.secondary)
            }
            Text("二维码包含已保存的 API key，请勿截图外传。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 380, height: 440)
    }
}

enum QRCodeGenerator {
    /// CIQRCodeGenerator 生成的是 1pt 单元的小图，按 scale 放大后包成 NSImage。
    static func image(for string: String, scale: CGFloat = 10) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let representation = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
#endif
