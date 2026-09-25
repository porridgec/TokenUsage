import SwiftUI

/// iOS 主界面：大号环形总览 + 各 provider 卡片 + 下拉刷新。
struct iOSMainView: View {
    let model: AppModel

    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewHeader
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
                }
                .padding(16)
            }
            .navigationTitle("订阅额度")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .refreshable {
                await model.refreshAll()
            }
            .onAppear {
                Task { await model.refreshAll() }
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SettingsView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showsSettings = false }
                            }
                        }
                }
            }
        }
    }

    /// 顶部大号环形总览：弧长 = 最紧窗口用量，中心显示百分比。
    private var overviewHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                UsageRingView(usedPercent: model.worstUsedPercent, lineWidth: 10)
                    .frame(width: 130, height: 130)
                if let worst = model.worstUsedPercent {
                    // 电池语义：大数字 = 剩余百分比（环长同为剩余，越绿越健康）
                    let remaining = 100 - worst
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("剩")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(remaining.compactPercentText)%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(UsageRingView.arcColor(worst))
                    }
                } else {
                    Image(systemName: "gauge")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            if let lastRefreshAt = model.lastRefreshAt {
                Text("更新于 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("尚未配置任何 API key")
                .font(.headline)
            Text("点右上角设置，添加 DeepSeek / Z.AI / OpenCode Go 的 key；\n或从 Mac 版扫码导入。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}
