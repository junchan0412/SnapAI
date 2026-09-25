import AppKit
import SwiftUI
import SnapAILogic

/// 双模型对照窗口:同一输入发两个模型,并排展示输出,差异行高亮。
///
/// 设计约束:
/// 1. 非模态普通窗口(可与结果浮窗并存),关闭即释放,无常驻状态。
/// 2. 两侧各一个"复制"按钮,不做写回 —— 对照是选型工具,写回仍走结果窗口。
/// 3. 空输出侧显示占位,不展示空表;完全一致显示中立摘要横幅。
@MainActor
final class ModelCompareWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(comparison: ModelCompare.Comparison, sourceText: String) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = ModelCompareView(comparison: comparison, sourceText: sourceText)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "双模型对照"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 980, height: 640))
        window.minSize = NSSize(width: 760, height: 480)
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct ModelCompareView: View {
    let comparison: ModelCompare.Comparison
    let sourceText: String
    @StateObject private var operationCoordinator = ResultOperationCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            header
            columnHeader
            compareList
            footer
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(SnapAIUI.Surface.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("双模型对照")
                    .font(SnapAIUI.Typography.windowTitle)
                Text(ModelCompare.summaryText(for: comparison))
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            summaryPills
        }
        .padding(24)
        .snapAIChrome()
    }

    private var summaryPills: some View {
        HStack(spacing: 6) {
            pill("修改 \(comparison.summary.changed)", color: SnapAIUI.StatusColor.warning)
            pill("新增 \(comparison.summary.inserted)", color: SnapAIUI.StatusColor.success)
            pill("删除 \(comparison.summary.deleted)", color: SnapAIUI.StatusColor.error)
        }
    }

    private func pill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(SnapAIUI.Typography.sectionLabel)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sideHeader(title: comparison.left.side.title,
                       count: comparison.left.side.characterCount,
                       onCopy: { copy(comparison.left.side.text, label: comparison.left.side.title) })
            Divider()
            sideHeader(title: comparison.right.side.title,
                       count: comparison.right.side.characterCount,
                       onCopy: { copy(comparison.right.side.text, label: comparison.right.side.title) })
        }
        .font(SnapAIUI.Typography.sectionLabel)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .background(SnapAIUI.Surface.quiet)
    }

    private func sideHeader(title: String, count: Int, onCopy: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count) 字")
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.tertiary)
            Button("复制", action: onCopy)
                .buttonStyle(.link)
                .font(SnapAIUI.Typography.metaText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var compareList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(comparison.left.rows) { row in
                    HStack(alignment: .top, spacing: 0) {
                        compareCell(row.original, kind: row.kind)
                        Divider()
                        compareCell(row.revised, kind: row.kind)
                    }
                    .background(rowBackground(row.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .snapAIScrollEdge()
    }

    private func compareCell(_ text: String?, kind: DiffRowKind) -> some View {
        Text(text?.isEmpty == false ? text! : " ")
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
        VStack(spacing: 8) {
            ResultOperationFeedbackHost(coordinator: operationCoordinator)
            HStack(spacing: 12) {
            Text("对照仅用于选型,不写回原文。如需使用某一侧结果,先复制再处理。")
                .font(SnapAIUI.Typography.metaText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            }
        }
        .padding(20)
        .snapAIChrome()
    }

    private func copy(_ text: String, label: String) {
        operationCoordinator.copy(text: text,
                                  successMessage: "已复制\(label)的结果",
                                  emptyMessage: "该侧没有可复制的结果。")
    }
}
