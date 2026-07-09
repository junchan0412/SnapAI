import AppKit
import SwiftUI
import SnapAILogic

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
                                   isTruncated: isTruncated) { selected in
            decision = selected
            delegate.isResolved = true
            NSApp.stopModal()
        }
        delegate.onClose = {
            decision = .cancel
            NSApp.stopModal()
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "替换前预览"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.level = .floating
        window.setContentSize(NSSize(width: 820, height: 560))
        window.minSize = NSSize(width: 700, height: 460)
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
    var onDecision: (DiffPreviewDecision) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnHeader
            diffList
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("确认替换原文")
                    .font(.headline)
                Text(actionName.isEmpty ? "请检查变更后再写回当前应用。" : "动作: \(actionName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            summaryPills
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var summaryPills: some View {
        HStack(spacing: 6) {
            pill("修改 \(summary.changed)", color: .orange)
            pill("新增 \(summary.inserted)", color: .green)
            pill("删除 \(summary.deleted)", color: .red)
        }
    }

    private func pill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("原文")
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Text("将替换为")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var diffList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    diffRow(row)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func diffRow(_ row: TextDiffRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            diffCell(row.original, kind: row.kind, side: .original)
            Divider()
            diffCell(row.revised, kind: row.kind, side: .revised)
        }
        .background(rowBackground(row.kind))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.vertical, 1)
    }

    private enum DiffSide {
        case original
        case revised
    }

    private func diffCell(_ text: String?, kind: DiffRowKind, side: DiffSide) -> some View {
        Text(text?.isEmpty == false ? text! : " ")
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(foreground(kind: kind, side: side, hasText: text != nil))
    }

    private func foreground(kind: DiffRowKind, side: DiffSide, hasText: Bool) -> Color {
        guard hasText else { return .secondary.opacity(0.45) }
        switch (kind, side) {
        case (.deleted, .original):
            return .red
        case (.inserted, .revised):
            return .green
        case (.changed, _):
            return .primary
        default:
            return .primary
        }
    }

    private func rowBackground(_ kind: DiffRowKind) -> Color {
        switch kind {
        case .unchanged:
            return Color.clear
        case .inserted:
            return Color.green.opacity(0.08)
        case .deleted:
            return Color.red.opacity(0.08)
        case .changed:
            return Color.orange.opacity(0.10)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("取消") {
                onDecision(.cancel)
            }
            .keyboardShortcut(.cancelAction)
            Button("复制结果") {
                onDecision(.copy)
            }
            Button("替换原文") {
                onDecision(.replace)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var footerMessage: String {
        if isTruncated {
            return "大型文本仅显示前 1000 行预览。确认后仍会写回完整结果，并恢复当前剪贴板。"
        }
        return summary.hasChanges ? "确认后会写回触发 SnapAI 时的应用，并恢复当前剪贴板。" : "文本没有检测到变化。"
    }
}
