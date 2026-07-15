import SwiftUI

struct HistorySettingsSection: View {
    @ObservedObject var settings: AppSettings
    let commit: () -> Void
    @StateObject private var operationCoordinator = ResultOperationCoordinator()
    @State private var showClearHistoryConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            usageStatsSection
            historyControls
            historyStorageModeRow
            historyList
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            ResultOperationFeedbackHost(coordinator: operationCoordinator)
                .frame(maxWidth: 420)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .snapAIConfirmDestructive(
            isPresented: $showClearHistoryConfirm,
            title: "清空全部历史记录",
            message: "将永久删除全部 \(settings.history.count) 条历史记录,此操作不可撤销。",
            action: {
                settings.clearHistory()
                commit()
                operationCoordinator.clearFeedback()
            }
        )
    }

    @ViewBuilder
    private var usageStatsSection: some View {
        if !settings.actionUsageCounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("使用统计").font(.subheadline.weight(.semibold))
                let sorted = settings.actionUsageCounts.sorted { $0.value > $1.value }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(sorted, id: \.key) { name, count in
                        HStack {
                            Text(name).lineLimit(1)
                            Spacer()
                            Text("\(count) 次").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                HStack {
                    Text("共 \(settings.history.count) 条记录").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("清空统计") {
                        settings.actionUsageCounts = [:]
                        commit()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("仅清空使用次数统计,不影响历史记录")
                }
            }
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
            Divider()
        }
    }

    private var historyControls: some View {
        HStack {
            Text("历史记录").font(.headline)
            Spacer()
            Stepper("保留 \(settings.historyLimit) 条", value: $settings.historyLimit, in: 0...500, step: 10)
                .onChange(of: settings.historyLimit) { commit() }
            Button("清空全部", role: .destructive) {
                showClearHistoryConfirm = true
            }
            .disabled(settings.history.isEmpty)
            .help("清空全部历史记录(需确认)")
        }
    }

    private var historyStorageModeRow: some View {
        HStack(spacing: 10) {
            Text("保存内容")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $settings.historyContentStorage) {
                ForEach(HistoryContentStorage.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 190)
            .onChange(of: settings.historyContentStorage) { commit() }
            Text(settings.historyContentStorage.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if settings.history.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                Text("暂无历史记录").foregroundStyle(.secondary)
                Text("选中文字或截图后调用动作,结果会自动记录在这里。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 280)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(settings.history) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.displayActionName).font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15)).clipShape(Capsule())
                Text(entry.modelDisplayText).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(entry.dateString).font(.caption2).foregroundStyle(.secondary)
                Button {
                    copyHistoryOutput(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(entry.copyableOutputText == nil)
                .help(entry.copyableOutputText == nil ? "该记录未保存结果" : "复制结果")
            }
            if let source = entry.sourceDisplayText {
                Text(source).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let output = entry.outputDisplayText {
                Text(output).font(.callout)
                    .lineLimit(3)
            } else if entry.sourceDisplayText == nil {
                Text(entry.emptyContentPlaceholder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    private func copyHistoryOutput(_ entry: HistoryEntry) {
        guard let output = entry.copyableOutputText else { return }
        operationCoordinator.copy(text: output,
                                  successMessage: "结果已复制",
                                  emptyMessage: "该记录没有可复制的结果。")
    }
}
