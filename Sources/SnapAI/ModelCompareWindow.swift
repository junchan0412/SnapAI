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

private struct ModelCompareView: View {
    let comparison: ModelCompare.Comparison
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

private struct ModelCompareSessionView: View {
    @ObservedObject var session: ModelCompareSession
    @StateObject private var operations = ResultOperationCoordinator()
    @State private var showDifferences = false
    @State private var showInput = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("双模型对照").font(SnapAIUI.Typography.windowTitle)
                    Text("确认后将相同输入分别发送给两个模型，产生两次独立请求及相应费用。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(session.inputSummary + (session.localOnly ? " · 仅本地路线" : " · 可包含云端路线"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.isRunning {
                    Button("全部停止") { session.cancelAll() }
                } else if !session.hasStarted {
                    Button("开始双模型生成") { session.start() }
                        .buttonStyle(.borderedProminent).disabled(!session.canStart)
                }
            }
            if let reason = session.unavailableReason {
                Text(reason).foregroundStyle(.secondary)
            }
            if let error = session.preparationError {
                Text(error).foregroundStyle(.red)
            }
            if session.messages.isEmpty {
                Text("尚无可重放的请求，请先在结果窗口提交一次输入。")
            }
            HStack {
                routePicker("左侧模型", selection: $session.leftRouteID)
                routePicker("右侧模型", selection: $session.rightRouteID)
            }
            DisclosureGroup("发送内容预览", isExpanded: $showInput) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.redactionEnabled ? "文本已按当前规则脱敏；图片中的文字不会自动脱敏。" : "文本脱敏未开启。")
                            .foregroundStyle(.secondary)
                        ForEach(Array(session.messages.enumerated()), id: \.offset) { _, message in
                            VStack(alignment: .leading) {
                                Text(message.role.rawValue).font(.caption).foregroundStyle(.secondary)
                                Text(message.content).textSelection(.enabled)
                                if let data = message.imageData, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 200)
            }
            if let comparison = session.comparison {
                Toggle("查看行差异（最多 1,000 行）", isOn: $showDifferences)
                if showDifferences {
                    ModelCompareView(comparison: comparison)
                } else {
                    requests
                }
            } else {
                requests
            }
            ResultOperationFeedbackHost(coordinator: operations)
            Text("选中并复制只更新剪贴板，不会写回原文。失败或停止的输出标记为部分结果。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 480)
        .background(SnapAIUI.Surface.canvas)
    }

    private func routePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(session.routes) { route in
                Text("\(route.diagnosticProviderName) / \(route.diagnosticModelName)\(route.isLocalEndpoint ? "（本地）" : "（云端）")")
                    .tag(ModelCompareSession.routeID(route))
            }
        }.disabled(session.hasStarted)
    }

    private var requests: some View {
        HStack(alignment: .top, spacing: 12) {
            requestColumn(session.left)
            Divider()
            requestColumn(session.right)
        }.frame(maxHeight: .infinity)
    }

    @ViewBuilder private func requestColumn(_ request: ModelCompareRequest?) -> some View {
        if let request {
            ModelCompareRequestView(request: request,
                                    selected: session.selectedRouteID == ModelCompareSession.routeID(request.route)) {
                session.choose(request)
                operations.copy(text: request.output,
                                successMessage: "已选中并复制\(request.title)的结果",
                                emptyMessage: "该侧没有可复制的结果。")
            }
        } else {
            Text("选择模型后点击“开始双模型生成”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ModelCompareRequestView: View {
    @ObservedObject var request: ModelCompareRequest
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.title).font(.headline).lineLimit(2)
            if request.isRunning {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text("\(request.status.rawValue) · \(request.elapsed(at: context.date), specifier: "%.1f") 秒")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("\(request.status.rawValue) · \(request.elapsed(), specifier: "%.1f") 秒")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let first = request.firstTokenMilliseconds {
                Text("首个响应片段：\(first) ms").font(.caption).foregroundStyle(.secondary)
            }
            if let error = request.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !request.output.isEmpty && (request.status == .failed || request.status == .cancelled) {
                Text("部分结果").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if request.isRunning { Button("停止此侧") { request.cancel() } }
                Button(selected ? "已选中 · 再次复制" : "选中并复制", action: choose)
                    .disabled(!request.canChoose)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !request.thinking.isEmpty {
                        DisclosureGroup("思考过程") {
                            Text(request.thinking).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Text(request.output.isEmpty ? "等待模型返回…" : request.output)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
