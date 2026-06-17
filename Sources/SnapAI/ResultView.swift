import SwiftUI

/// 流式输出时的闪烁光标。用 TimelineView 驱动,无需 @State(兼容 CLT 环境)。
struct TypingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary)
                .frame(width: 7, height: 15)
                .opacity(on ? 1 : 0.15)
        }
    }
}

/// 浮动结果面板的 SwiftUI 内容
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

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.action.icon.isEmpty ? "sparkles" : vm.action.icon)
                .foregroundStyle(.tint)
            Text(vm.action.name.isEmpty ? "SnapAI" : vm.action.name)
                .font(.headline)
            if vm.isStreaming {
                ProgressView().controlSize(.small).padding(.leading, 2)
            }

            // 翻译类:语言切换(#7)
            if vm.isTranslation {
                Menu {
                    ForEach(TargetLanguage.allCases) { lang in
                        Button {
                            vm.changeLanguage(lang)
                        } label: {
                            if lang == vm.targetLanguage {
                                Label(lang.rawValue, systemImage: "checkmark")
                            } else { Text(lang.rawValue) }
                        }
                    }
                } label: {
                    Label(vm.targetLanguage.rawValue, systemImage: "globe")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(vm.isStreaming)
            }

            Spacer()
            Button {
                vm.isPinned.toggle()
            } label: {
                Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(vm.isPinned ? Color.accentColor : .secondary)
                    .rotationEffect(.degrees(vm.isPinned ? 0 : 45))
            }
            .buttonStyle(.plain)
            .help(vm.isPinned ? "已固定:点击外部不会关闭" : "固定窗口(点击外部不关闭)")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 可编辑原文(#5)
                    if !vm.sourceText.isEmpty || vm.action.name.isEmpty == false {
                        sourceEditor
                    }

                    if let err = vm.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if vm.output.isEmpty && vm.isStreaming {
                        HStack(spacing: 6) {
                            Text("思考中").foregroundStyle(.secondary)
                            TypingCursor()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("output")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            MarkdownView(text: vm.output)
                            if vm.isStreaming {
                                TypingCursor()
                            }
                        }
                        .id("output")
                    }
                }
                .padding(14)
            }
            .onChange(of: vm.output) {
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: $vm.sourceText)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 32, maxHeight: 90)
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(vm.isStreaming)
            Button {
                vm.resendEdited()
            } label: {
                Label("用此文本重新发送", systemImage: "arrow.up.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(vm.isStreaming)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            // 指标行(#9)
            if vm.charCount > 0 || vm.elapsed > 0 {
                HStack(spacing: 10) {
                    if vm.elapsed > 0 {
                        Label(String(format: "%.1fs", vm.elapsed), systemImage: "clock")
                    }
                    if vm.charCount > 0 {
                        Label("\(vm.charCount) 字", systemImage: "textformat")
                    }
                    Spacer()
                    if !vm.settings.activeModel.isEmpty {
                        Text(vm.settings.activeModel).truncationMode(.middle).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("追问…", text: $vm.followUp, onCommit: vm.sendFollowUp)
                    .textFieldStyle(.roundedBorder)
                    .disabled(vm.isStreaming)

                Button {
                    vm.copyOutput()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制结果")
                .disabled(vm.output.isEmpty)

                Button {
                    vm.replaceOriginal()
                } label: {
                    Image(systemName: "arrow.uturn.left.square")
                }
                .help("用结果替换原文位置")
                .disabled(vm.output.isEmpty || vm.isStreaming)

                if vm.isStreaming {
                    Button {
                        vm.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("停止")
                } else {
                    Button {
                        vm.regenerate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重新生成")
                    .disabled(vm.sourceText.isEmpty)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
