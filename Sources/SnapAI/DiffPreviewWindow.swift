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
    let original: String
    let revised: String
    var onDecision: (DiffPreviewDecision) -> Void

    @State private var didCopyRevised = false

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
            pill("修改 \(summary.changed)", color: SnapAIUI.StatusColor.warning)
            pill("新增 \(summary.inserted)", color: SnapAIUI.StatusColor.success)
            pill("删除 \(summary.deleted)", color: SnapAIUI.StatusColor.error)
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

    @ViewBuilder
    private var diffList: some View {
        if !summary.hasChanges {
            // 无变化时的空状态占位,避免一片空白让用户困惑。
            VStack(spacing: 10) {
                Image(systemName: "equal.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("文本没有检测到变化")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("原文与替换结果一致,无需写回。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        diffRow(row)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.vertical, 1)
    }

    private enum DiffSide {
        case original
        case revised
    }

    private func diffCell(_ text: String?, kind: DiffRowKind, side: DiffSide) -> some View {
        // 色盲友好:用 +/− 符号区分增删行,不依赖颜色。
        let symbol = leadingSymbol(kind: kind, side: side)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol { Text(symbol).foregroundStyle(foreground(kind: kind, side: side, hasText: text != nil)) }
            Text(text?.isEmpty == false ? text! : " ")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(foreground(kind: kind, side: side, hasText: text != nil))
    }

    /// 行首符号:仅增/删侧显示 +/−,辅助色盲用户识别变更类型。
    private func leadingSymbol(kind: DiffRowKind, side: DiffSide) -> String? {
        switch (kind, side) {
        case (.inserted, .revised): return "+"
        case (.deleted, .original): return "−"
        default: return nil
        }
    }

    private func foreground(kind: DiffRowKind, side: DiffSide, hasText: Bool) -> Color {
        guard hasText else { return .secondary.opacity(0.45) }
        switch (kind, side) {
        case (.deleted, .original):
            return SnapAIUI.StatusColor.error
        case (.inserted, .revised):
            return SnapAIUI.StatusColor.success
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
            return SnapAIUI.StatusColor.success.opacity(0.08)
        case .deleted:
            return SnapAIUI.StatusColor.error.opacity(0.08)
        case .changed:
            return SnapAIUI.StatusColor.warning.opacity(0.10)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isTruncated {
                Button {
                    exportFullDiff()
                } label: {
                    Label("导出完整差异", systemImage: "square.and.arrow.down")
                }
                .help("预览被截断,导出完整的原文/替换结果以便核对")
            }
            Button("取消") {
                onDecision(.cancel)
            }
            .keyboardShortcut(.cancelAction)
            Button {
                copyRevised()
            } label: {
                Label(didCopyRevised ? "已复制" : "复制结果",
                      systemImage: didCopyRevised ? "checkmark" : "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command])
            .help("复制替换结果 (⌘C)")
            Button("替换原文") {
                onDecision(.replace)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!summary.hasChanges)
            .help(summary.hasChanges ? "写回触发 SnapAI 时的应用 (↩)" : "没有变化,无需替换")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.18), value: didCopyRevised)
    }

    private var footerMessage: String {
        if isTruncated {
            return "大型文本仅显示前 1000 行预览。确认后仍会写回完整结果,并恢复当前剪贴板。"
        }
        return summary.hasChanges ? "确认后会写回触发 SnapAI 时的应用,并恢复当前剪贴板。" : "文本没有检测到变化。"
    }

    private func copyRevised() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(revised, forType: .string)
        didCopyRevised = true
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
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
