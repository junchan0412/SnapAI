import AppKit
import SwiftUI
import SnapAILogic

@MainActor
final class ModelCompareWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var session: ModelCompareSession?

    func show(session: ModelCompareSession) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.session = session
        let view = ModelCompareSessionView(session: session)
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
        session?.close()
        session = nil
        window = nil
    }
}

private struct ModelCompareSessionView: View {
    @ObservedObject var session: ModelCompareSession
    @StateObject private var operations = ResultOperationCoordinator()
    @State private var showDifferences = false
    @State private var showInput = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            SnapAIFormDivider(inset: 0)
            modelSelectionBar

            if showInput {
                SnapAIFormDivider(inset: 0)
                inputPreviewSection
            }

            SnapAIFormDivider(inset: 0)

            if let reason = session.unavailableReason {
                SnapAIIncompleteResultBanner(title: reason, systemImage: "info.circle") {}
                    .padding(14)
            }
            if let error = session.preparationError {
                SnapAITransientNoticeBanner(title: error) {}
                    .padding(14)
            }

            if let comparison = session.comparison, showDifferences {
                ModelCompareDiffView(comparison: comparison)
            } else {
                requestsColumns
            }

            SnapAIFormDivider(inset: 0)
            footerBar
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(SnapAIUI.Surface.canvas)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("双模型并排对照")
                    .font(SnapAIUI.Typography.windowTitle)
                Text("\(session.inputSummary) · \(session.localOnly ? "仅本地模型" : "允许云端模型")")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                showInput.toggle()
            } label: {
                Label(showInput ? "收起发送内容" : "查看发送内容", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))

            if session.comparison != nil {
                Toggle(isOn: $showDifferences) {
                    Label("文本差异", systemImage: "arrow.left.arrow.right")
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }

            if session.isRunning {
                Button("全部停止") { session.cancelAll() }
                    .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
            } else if !session.hasStarted {
                Button {
                    session.start()
                } label: {
                    Label("开始双路生成", systemImage: "play.fill")
                }
                .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
                .disabled(!session.canStart)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var modelSelectionBar: some View {
        HStack(spacing: 16) {
            routePicker("模型 A", selection: $session.leftRouteID)
            Divider().frame(height: 18)
            routePicker("模型 B", selection: $session.rightRouteID)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(SnapAIUI.Surface.quiet)
    }

    private func routePicker(_ title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(SnapAIUI.Typography.metaText.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(session.routes) { route in
                    Text("\(route.diagnosticProviderName) · \(route.diagnosticModelName)")
                        .tag(ModelCompareSession.routeID(route))
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .disabled(session.hasStarted)
        }
    }

    private var inputPreviewSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.redactionEnabled ? "发送文本已执行本地脱敏。" : "当前未启用本地文本脱敏。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.role.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(message.content)
                            .font(SnapAIUI.Typography.metaText)
                            .textSelection(.enabled)
                        if let data = message.imageData, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .snapAIGlassCard(radius: 7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 160)
        .background(SnapAIUI.Surface.quiet)
    }

    private var requestsColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            requestColumn(session.left)
            Divider()
            requestColumn(session.right)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func requestColumn(_ request: ModelCompareRequest?) -> some View {
        if let request {
            ModelCompareRequestView(
                request: request,
                selected: session.selectedRouteID == ModelCompareSession.routeID(request.route),
                onCopyCode: { code in
                    operations.copy(text: code, successMessage: "代码已复制", emptyMessage: "代码块为空。")
                },
                choose: {
                    session.choose(request)
                    operations.copy(text: request.output,
                                    successMessage: "已选用并复制 \(request.title) 的回答",
                                    emptyMessage: "该侧没有可复制的结果。")
                }
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(session.messages.isEmpty ? "请先在结果面板发起一次提问" : "选择两侧模型后点击右上角「开始双路生成」")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footerBar: some View {
        VStack(spacing: 6) {
            ResultOperationFeedbackHost(coordinator: operations)
            HStack {
                Text("点击任一侧「选用并复制」可将结果写入剪贴板（不会自动覆盖原文档）。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct ModelCompareRequestView: View {
    @ObservedObject var request: ModelCompareRequest
    let selected: Bool
    var onCopyCode: (String) -> Void
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title)
                        .font(SnapAIUI.Typography.sectionTitle)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if request.isRunning {
                            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                                Text("\(request.status.rawValue) · \(request.elapsed(at: context.date), specifier: "%.1f")s")
                            }
                        } else {
                            Text("\(request.status.rawValue) · \(request.elapsed(), specifier: "%.1f")s")
                        }
                        if let first = request.firstTokenMilliseconds {
                            Text("· 首字 \(first) ms")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Spacer()
                if request.isRunning {
                    Button("停止") { request.cancel() }
                        .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                }
                Button(selected ? "已选用 · 复制" : "选用并复制", action: choose)
                    .buttonStyle(selected
                                 ? AnyCompareButtonStyle(SnapAIPrimaryButtonStyle(compact: true))
                                 : AnyCompareButtonStyle(SnapAISecondaryButtonStyle(compact: true)))
                    .disabled(!request.canChoose)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            SnapAIFormDivider(inset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = request.errorMessage {
                        SnapAITransientNoticeBanner(title: error) {}
                    }
                    if !request.thinking.isEmpty {
                        DisclosureGroup("推理过程") {
                            Text(request.thinking)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 4)
                        }
                        .font(SnapAIUI.Typography.metaText)
                    }
                    if request.output.isEmpty {
                        Text(request.isRunning ? "正在生成回答…" : "暂无输出")
                            .font(SnapAIUI.Typography.bodyText)
                            .foregroundStyle(.secondary)
                    } else if request.isRunning {
                        Text(request.output)
                            .font(SnapAIUI.Typography.readingText)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownView(text: request.output, onCopyCode: onCopyCode)
                            .font(SnapAIUI.Typography.readingText)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .snapAIScrollEdge()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(selected ? Color.accentColor.opacity(0.03) : Color.clear)
    }
}

private struct ModelCompareDiffView: View {
    let comparison: ModelCompare.Comparison

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("\(comparison.left.side.title)（\(comparison.left.side.characterCount) 字）")
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Text("\(comparison.right.side.title)（\(comparison.right.side.characterCount) 字）")
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(SnapAIUI.Typography.sectionLabel)
            .foregroundStyle(.secondary)
            .frame(height: 32)
            .background(SnapAIUI.Surface.quiet)

            SnapAIFormDivider(inset: 0)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(comparison.left.rows) { row in
                        HStack(alignment: .top, spacing: 0) {
                            compareCell(row.original)
                            Divider()
                            compareCell(row.revised)
                        }
                        .background(rowBackground(row.kind))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(12)
            }
            .snapAIScrollEdge()
        }
    }

    private func compareCell(_ text: String?) -> some View {
        Text(text?.isEmpty == false ? text! : " ")
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func rowBackground(_ kind: DiffRowKind) -> Color {
        switch kind {
        case .unchanged: return Color.clear
        case .inserted: return SnapAIUI.StatusColor.success.opacity(0.08)
        case .deleted: return SnapAIUI.StatusColor.error.opacity(0.08)
        case .changed: return SnapAIUI.StatusColor.warning.opacity(0.09)
        }
    }
}

private struct AnyCompareButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
