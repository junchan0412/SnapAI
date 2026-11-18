import AppKit
import SwiftUI
import SnapAILogic
import UniformTypeIdentifiers

enum DiffPreviewDecision {
    case replace
    case copy
    case cancel
}

@MainActor
final class DiffPreviewWindowController {
    private static let maxPreviewRows = 1_000

    static func present(original: String,
                        revised: String,
                        actionName: String) -> DiffPreviewDecision {
        var decision: DiffPreviewDecision = .cancel
        let rows = TextDiff.rows(original: original, revised: revised, maxRows: maxPreviewRows)
        let summary = TextDiff.summary(for: rows)
        let isTruncated = rows.count >= maxPreviewRows

        let window = NSWindow()
        let delegate = ModalCloseDelegate()
        let view = DiffPreviewView(actionName: actionName,
                                   rows: rows,
                                   summary: summary,
                                   isTruncated: isTruncated,
                                   original: original,
                                   revised: revised) { selected in
            decision = selected
            delegate.isResolved = true
            NSApp.stopModal()
        }
        delegate.onClose = {
            decision = .cancel
            NSApp.stopModal()
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "替换前差异确认"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.level = .floating
        window.setContentSize(NSSize(width: 840, height: 540))
        window.minSize = NSSize(width: 680, height: 440)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.close()
        return decision
    }
}

private final class ModalCloseDelegate: NSObject, NSWindowDelegate {
    var isResolved = false
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        guard !isResolved else { return }
        isResolved = true
        onClose?()
    }
}

private struct DiffPreviewView: View {
    let actionName: String
    let rows: [TextDiffRow]
    let summary: TextDiffSummary
    let isTruncated: Bool
    let original: String
    let revised: String
    var onDecision: (DiffPreviewDecision) -> Void

    @State private var didCopyRevised = false
    @StateObject private var operationCoordinator = ResultOperationCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            header
            SnapAIFormDivider(inset: 0)
            columnHeader
            SnapAIFormDivider(inset: 0)
            diffList
            SnapAIFormDivider(inset: 0)
            footer
        }
        .frame(minWidth: 680, minHeight: 440)
        .background(SnapAIUI.Surface.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("确认写回替换")
                    .font(SnapAIUI.Typography.windowTitle)
                Text(actionName.isEmpty ? "核对变更后写回原应用，剪贴板内容会自动保护并还原。" : "「\(actionName)」生成结果对比，确认后写回原应用。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            summaryPills
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .snapAIChrome()
    }

    private var summaryPills: some View {
        HStack(spacing: 6) {
            SnapAIStatusPill(title: "修改 \(summary.changed)", systemImage: "pencil", tint: SnapAIUI.StatusColor.warning, filled: summary.changed > 0)
            SnapAIStatusPill(title: "新增 \(summary.inserted)", systemImage: "plus", tint: SnapAIUI.StatusColor.success, filled: summary.inserted > 0)
            SnapAIStatusPill(title: "删除 \(summary.deleted)", systemImage: "minus", tint: SnapAIUI.StatusColor.error, filled: summary.deleted > 0)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("捕获时原文")
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Text("替换后文本")
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(SnapAIUI.Typography.sectionLabel)
        .foregroundStyle(.secondary)
        .frame(height: 32)
        .background(SnapAIUI.Surface.quiet)
    }

    @ViewBuilder
    private var diffList: some View {
        if !summary.hasChanges {
            VStack(spacing: 8) {
                Image(systemName: "equal.circle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("原文与结果完全一致")
                    .font(SnapAIUI.Typography.sectionTitle)
                Text("无需执行写回操作。")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        diffRow(row)
                    }
                }
                .padding(12)
            }
        }
    }

    private func diffRow(_ row: TextDiffRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            diffCell(row.original, kind: row.kind, side: .original)
            Divider()
            diffCell(row.revised, kind: row.kind, side: .revised)
        }
        .background(rowBackground(row.kind))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private enum DiffSide {
        case original
        case revised
    }

    private func diffCell(_ text: String?, kind: DiffRowKind, side: DiffSide) -> some View {
        let symbol = leadingSymbol(kind: kind, side: side)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(symbol ?? " ")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(foreground(kind: kind, side: side, hasText: text != nil))
                .frame(width: 12)
            Text(text?.isEmpty == false ? text! : " ")
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(2)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func leadingSymbol(kind: DiffRowKind, side: DiffSide) -> String? {
        switch (kind, side) {
        case (.inserted, .revised): return "+"
        case (.deleted, .original): return "−"
        case (.changed, _): return "~"
        default: return nil
        }
    }

    private func foreground(kind: DiffRowKind, side: DiffSide, hasText: Bool) -> Color {
        guard hasText else { return .secondary.opacity(0.45) }
        switch (kind, side) {
        case (.deleted, .original): return SnapAIUI.StatusColor.error
        case (.inserted, .revised): return SnapAIUI.StatusColor.success
        case (.changed, _): return SnapAIUI.StatusColor.warning
        default: return .primary
        }
    }

    private func rowBackground(_ kind: DiffRowKind) -> Color {
        switch kind {
        case .unchanged: return Color.clear
        case .inserted: return SnapAIUI.StatusColor.success.opacity(0.08)
        case .deleted: return SnapAIUI.StatusColor.error.opacity(0.08)
        case .changed: return SnapAIUI.StatusColor.warning.opacity(0.09)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResultOperationFeedbackHost(coordinator: operationCoordinator)
            HStack(spacing: 10) {
                if isTruncated {
                    Button {
                        exportFullDiff()
                    } label: {
                        Label("导出完整差异…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                }

                Button {
                    copyRevised()
                } label: {
                    Label(didCopyRevised ? "已复制" : "仅复制结果",
                          systemImage: didCopyRevised ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .keyboardShortcut("c", modifiers: [.command])

                if isTruncated {
                    Text("大文本仅预览前 1000 行，写回仍使用完整结果")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("取消") {
                    onDecision(.cancel)
                }
                .buttonStyle(SnapAISecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("确认替换 (↩)") {
                    onDecision(.replace)
                }
                .buttonStyle(SnapAIPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!summary.hasChanges)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .snapAIChrome()
    }

    private func copyRevised() {
        operationCoordinator.copy(text: revised,
                                  successMessage: "替换结果已复制",
                                  emptyMessage: "替换结果为空，没有可复制的内容。")
        didCopyRevised = operationCoordinator.feedback?.kind == .success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopyRevised = false }
    }

    private func exportFullDiff() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SnapAI-Diff"
        panel.allowedContentTypes = [.utf8PlainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = """
        # 替换前预览完整内容

        ## 原文

        \(original)

        ## 将替换为

        \(revised)
        """
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            operationCoordinator.showSuccess("完整差异已导出")
        } catch {
            operationCoordinator.showError("导出失败：\(SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription, limit: 160))")
        }
    }
}
