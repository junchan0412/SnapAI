import SnapAILogic
import SwiftUI

struct HistorySettingsSection: View {
    @ObservedObject var settings: AppSettings
    let commit: () -> Void
    @StateObject private var operationCoordinator = ResultOperationCoordinator()
    @State private var showClearHistoryConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    historyControls
                    Divider()
                    historyStorageModeRow
                }
                .snapAISurface(padding: 16)
                usageStatsSection
                HStack(spacing: 8) {
                    Text("历史记录")
                        .font(SnapAIUI.Typography.sectionTitle)
                    Text("\(settings.history.count) 条")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空全部", role: .destructive) {
                        showClearHistoryConfirm = true
                    }
                    .controlSize(.small)
                    .disabled(settings.history.isEmpty)
                    .help("清空全部历史记录（需确认）")
                }
                historyList
            }
            .padding(SnapAIUI.edgePadding)
        }
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
                guard settings.clearHistory() else {
                    operationCoordinator.showError("清空历史失败，现有记录未被删除。请稍后重试。")
                    return
                }
                commit()
                operationCoordinator.clearFeedback()
            }
        )
    }

    @ViewBuilder
    private var usageStatsSection: some View {
        if !settings.actionUsageCounts.isEmpty {
            DisclosureGroup {
                let sorted = settings.actionUsageCounts.sorted { $0.value > $1.value }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SnapAIUI.tightSpacing) {
                    ForEach(sorted, id: \.key) { name, count in
                        HStack {
                            Text(name).lineLimit(1)
                            Spacer()
                            Text("\(count) 次").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(SnapAIUI.Typography.metaText)
                        .padding(10)
                        .background(SnapAIUI.Surface.quiet)
                        .clipShape(RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous))
                    }
                }
                .padding(.top, 12)
                HStack {
                    Text("按动作累计的使用次数")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空统计") {
                        settings.actionUsageCounts = [:]
                        commit()
                    }
                    .controlSize(.small)
                    .help("仅清空使用次数统计,不影响历史记录")
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Text("使用统计")
                        .font(SnapAIUI.Typography.sectionTitle)
                    Spacer()
                    Text("共 \(settings.actionUsageCounts.values.reduce(0, +)) 次")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .snapAISurface(padding: 16, fillOpacity: SnapAIUI.quietFillOpacity)
        }
    }

    private var historyControls: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("记录保留")
                    .font(SnapAIUI.Typography.sectionTitle)
                Text("超过上限的旧记录会移除，设为 0 可关闭历史记录。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Stepper("保留 \(settings.historyLimit) 条", value: $settings.historyLimit, in: 0...500, step: 10)
                .font(SnapAIUI.Typography.metaText)
                .fixedSize()
                .onChange(of: settings.historyLimit) { commit() }
        }
    }

    private var historyStorageModeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("保存内容")
                    .font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                Picker("保存内容", selection: $settings.historyContentStorage) {
                    ForEach(HistoryContentStorage.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 240)
                .onChange(of: settings.historyContentStorage) { commit() }
            }
            Text(settings.historyContentStorage.description)
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if settings.history.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text(settings.historyLimit == 0 ? "历史记录已关闭" : "完成一次提问，留下有用的结果")
                    .font(SnapAIUI.Typography.sectionTitle)
                Text(settings.historyLimit == 0 ? "将保留条数设为大于 0，即可记录之后的提问。" : "原文和结果会按上方的保存偏好记录在这里。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 340)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(settings.history) { entry in
                    historyRow(entry)
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.displayActionName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(entry.modelDisplayText).font(SnapAIUI.Typography.metaText).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(entry.dateString).font(SnapAIUI.Typography.metaText).foregroundStyle(.secondary)
                    .fixedSize()
                Button {
                    copyHistoryOutput(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(SnapAIIconButtonStyle(circular: false))
                .disabled(entry.copyableOutputText == nil)
                .help(entry.copyableOutputText == nil ? "该记录未保存结果" : "复制结果")
                .accessibilityLabel("复制\(entry.displayActionName)的结果")
            }
            if let source = entry.sourceDisplayText {
                Text(String(source.prefix(180))).font(SnapAIUI.Typography.metaText).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let output = entry.outputDisplayText {
                Text(String(output.prefix(320))).font(SnapAIUI.Typography.bodyText)
                    .lineLimit(3)
            } else if entry.sourceDisplayText == nil {
                Text(entry.emptyContentPlaceholder)
                    .font(SnapAIUI.Typography.bodyText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .snapAISurface(padding: 16, fillOpacity: SnapAIUI.quietFillOpacity)
    }

    private func copyHistoryOutput(_ entry: HistoryEntry) {
        guard let output = entry.copyableOutputText else { return }
        operationCoordinator.copy(text: output,
                                  successMessage: "结果已复制",
                                  emptyMessage: "该记录没有可复制的结果。")
    }
}
