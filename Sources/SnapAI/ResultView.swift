import SwiftUI
import AppKit

struct TypingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 7, height: 15)
                .opacity(on ? 1 : 0.15)
        }
    }
}

struct ResultView: View {
    @ObservedObject var vm: ResultViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: vm.action.icon.isEmpty ? "sparkles" : vm.action.icon).foregroundStyle(.tint)
                Text(vm.action.name.isEmpty ? "SnapAI" : vm.action.name).font(.headline)
                if vm.isStreaming { ProgressView().controlSize(.small).padding(.leading, 2) }

                // #7 翻译类语言切换
                if vm.isTranslation {
                    Menu {
                        ForEach(TargetLanguage.allCases) { lang in
                            Button {
                                vm.changeLanguage(lang)
                            } label: {
                                if lang == vm.targetLanguage { Label(lang.rawValue, systemImage: "checkmark") }
                                else { Text(lang.rawValue) }
                            }
                        }
                    } label: {
                        Label(vm.targetLanguage.rawValue, systemImage: "globe").font(.caption)
                    }
                    .menuStyle(.borderlessButton).fixedSize().disabled(vm.isStreaming)
                }

                Spacer()
                Button { vm.isPinned.toggle() } label: {
                    Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(vm.isPinned ? Color.accentColor : .secondary)
                        .rotationEffect(.degrees(vm.isPinned ? 0 : 45))
                }
                .buttonStyle(.plain)
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            // #4 动作切换栏
            actionSwitcher
        }
    }

    @ViewBuilder
    private var actionSwitcher: some View {
        let enabled = vm.settings.enabledActions
        if enabled.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(enabled) { act in
                        Button {
                            if act.id != vm.action.id { vm.switchAction(act) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: act.icon.isEmpty ? "sparkles" : act.icon).font(.caption2)
                                Text(act.name).font(.caption2)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(act.id == vm.action.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(act.id == vm.action.id ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(act.id == vm.action.id ? Color.accentColor : .primary)
                        .disabled(vm.isStreaming)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sourceEditor

                    // #2 thinking 展开/折叠
                    if !vm.thinkingText.isEmpty {
                        DisclosureGroup(
                            isExpanded: Binding(get: { vm.showThinking }, set: { vm.showThinking = $0 }),
                            content: {
                                Text(vm.thinkingText).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8).background(Color.primary.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            },
                            label: {
                                Label("思考过程", systemImage: "brain").font(.caption).foregroundStyle(.secondary)
                            }
                        )
                    }

                    if let err = vm.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // #12 重试按钮
                            Button { vm.retry() } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                            }
                            .controlSize(.small)
                        }
                    }

                    if vm.output.isEmpty && vm.isStreaming {
                        HStack(spacing: 6) {
                            Text("思考中").foregroundStyle(.secondary)
                            TypingCursor()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).id("output")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            MarkdownView(text: vm.output)
                            if vm.isStreaming { TypingCursor() }
                        }
                        .id("output")
                    }
                }
                .padding(14)
            }
            .onChange(of: vm.output) {
                withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("output", anchor: .bottom) }
            }
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: $vm.sourceText)
                .font(.callout).scrollContentBackground(.hidden)
                .frame(minHeight: 32, maxHeight: 90).padding(6)
                .background(Color.primary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(vm.isStreaming)
            Button { vm.resendEdited() } label: {
                Label("用此文本重新发送", systemImage: "arrow.up.circle").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.tint).disabled(vm.isStreaming)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            // 指标行
            if vm.charCount > 0 || vm.elapsed > 0 {
                HStack(spacing: 10) {
                    if vm.elapsed > 0 { Label(String(format: "%.1fs", vm.elapsed), systemImage: "clock") }
                    if vm.charCount > 0 { Label("\(vm.charCount) 字", systemImage: "textformat") }
                    Spacer()
                    Text(vm.settings.activeModel).truncationMode(.middle).lineLimit(1)
                }
                .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                FollowUpField(text: $vm.followUp, onSubmit: vm.sendFollowUp,
                              onHistoryUp: vm.followUpHistoryUp,
                              onHistoryDown: vm.followUpHistoryDown)
                    .disabled(vm.isStreaming)

                Button { vm.copyOutput() } label: { Image(systemName: "doc.on.doc") }
                    .help("复制结果").disabled(vm.output.isEmpty)

                Button { vm.replaceOriginal() } label: { Image(systemName: "arrow.uturn.left.square") }
                    .help("替换原文").disabled(vm.output.isEmpty || vm.isStreaming)

                Button { vm.appendToDocument() } label: { Image(systemName: "text.badge.plus") }
                    .help("追加到文档").disabled(vm.output.isEmpty || vm.isStreaming)

                // #7 导出
                Button { exportConversation() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("导出对话").disabled(vm.output.isEmpty)

                if vm.isStreaming {
                    Button { vm.cancel() } label: { Image(systemName: "stop.fill") }.help("停止")
                } else {
                    Button { vm.regenerate() } label: { Image(systemName: "arrow.clockwise") }
                        .help("重新生成").disabled(vm.sourceText.isEmpty)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 导出(#7)

    private func exportConversation() {
        var md = "# \(vm.action.name) — \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))\n\n"
        md += "**原文:**\n\n\(vm.sourceText)\n\n---\n\n"
        md += vm.completeText
        md += "\n\n---\n*模型: \(vm.settings.activeModel) |耗时: \(String(format: "%.1f", vm.elapsed))s*"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(vm.action.name)-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .text]
        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 追问框(#5 支持↑/↓浏览历史)

struct FollowUpField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = "追问…"
        f.bezelStyle = .roundedBezel
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FollowUpField
        init(_ parent: FollowUpField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit(); return true
            }
            if selector == #selector(NSResponder.moveUp(_:)) {
                parent.onHistoryUp(); return true
            }
            if selector == #selector(NSResponder.moveDown(_:)) {
                parent.onHistoryDown(); return true
            }
            return false
        }
    }
}
