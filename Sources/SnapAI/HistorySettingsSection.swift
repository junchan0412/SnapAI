import SwiftUI
import AppKit

struct HistorySettingsSection: View {
    @ObservedObject var settings: AppSettings
    let commit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            usageStatsSection
            historyControls
            historyStorageModeRow
            historyList
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
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
            Button("清空") { settings.clearHistory() }
                .disabled(settings.history.isEmpty)
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
            Text("暂无历史记录").foregroundStyle(.secondary)
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }
}
