import SwiftUI

/// 菜单栏下拉面板：各 provider 的额度卡片 + 刷新 / 设置入口。
struct MenuContent: View {
    let model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if model.providers.isEmpty {
                emptyState
            } else {
                ForEach(model.providers) { provider in
                    ProviderCard(
                        provider: provider,
                        snapshot: model.snapshots[provider],
                        errorMessage: model.errors[provider]
                    )
                }
            }

            Divider()

            HStack {
                if let lastRefreshAt = model.lastRefreshAt {
                    Text("更新于 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isRefreshing)
                Button("设置…") { onOpenSettings() }
            }
        }
        .padding(12)
        .frame(width: 330)
        .onAppear {
            Task { await model.refreshAll() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key")
                .font(.title2)
            Text("尚未配置任何 API key")
                .font(.headline)
            Text("在设置中添加 DeepSeek / Z.AI / OpenCode Go 的 key")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("打开设置") { onOpenSettings() }
        }
        .padding(.vertical, 12)
    }
}

