import AppKit
import SnapAILogic
import SwiftUI

struct ConversationLibraryView: View {
    let settings: AppSettings
    let restore: (ConversationSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ConversationSessionSummary] = []
    @State private var error: String?
    @State private var pendingDeletion: ConversationSessionSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已保存会话")
                        .font(SnapAIUI.Typography.windowTitle)
                    Text("从本机恢复完整提问与追问记录（不会自动发起网络请求）。")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            SnapAIFormDivider(inset: 0)

            if let error {
                SnapAITransientNoticeBanner(title: error) { self.error = nil }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            if sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("暂无可恢复会话")
                        .font(SnapAIUI.Typography.sectionTitle)
                    Text("开启完整历史记录后，多轮问答会自动保存在本机。")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 560, height: 440)
        .background(SnapAIUI.Surface.canvas)
        .task { reload() }
        .confirmationDialog("删除此会话及其本机图片？",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let session = pendingDeletion {
                    if case .failure = settings.persistenceConversationStore.delete(id: session.id) {
                        error = "删除失败，请稍后重试。"
                    }
                    pendingDeletion = nil
                    reload()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func sessionRow(_ session: ConversationSessionSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.hasImage ? "photo.on.rectangle" : "text.bubble")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(SnapAIUI.Surface.selected,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.preview.isEmpty ? session.actionName : session.preview)
                    .font(SnapAIUI.Typography.bodyText.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(session.actionName)
                    Text("·")
                    Text("\(session.messageCount) 条消息")
                    if session.parentSessionID != nil {
                        Text("· 分支")
                    }
                    Text("·")
                    Text(session.updatedAt, format: .dateTime.month().day().hour().minute())
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("恢复") { open(session) }
                .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))

            Button {
                pendingDeletion = session
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
            .help("删除会话")
            .accessibilityLabel("删除会话")
        }
        .padding(12)
        .snapAIGlassCard(radius: 9)
    }

    private func reload() {
        switch settings.persistenceConversationStore.list(limit: settings.historyLimit) {
        case .success(let values): sessions = values
        case .failure: error = "读取会话失败，现有记录仍保留。"
        }
    }

    private func open(_ summary: ConversationSessionSummary) {
        switch settings.persistenceConversationStore.load(id: summary.id) {
        case .success(let session?): restore(session); dismiss()
        case .success(nil): reload()
        case .failure: error = "恢复失败，请稍后重试。"
        }
    }
}

/// 结果面板内联多轮对话流视图：展示当前生成轮之前的历史问答，并支持一键从任一轮回复创建分支。
struct ResultInlineConversationThread: View {
    let priorTurns: [ConversationMessage]
    let activeFollowUpPrompt: String?
    let sourceImageData: Data?
    let isGenerating: Bool
    var onCopyCode: (String) -> Void
    var onBranch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let data = sourceImageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.6)
                    }
                    .accessibilityLabel("会话原图，仅保存在本机")
            }

            ForEach(Array(priorTurns.enumerated()), id: \.element.id) { index, message in
                if message.role == .user {
                    // 首条 user 消息已在顶部「原文」胶囊展示，仅从第二轮追问起展示用户气泡
                    if index > 0 {
                        userPromptBubble(message.content)
                    }
                } else if message.role == .assistant {
                    priorAssistantCard(message)
                }
            }

            if let prompt = activeFollowUpPrompt, !prompt.isEmpty {
                userPromptBubble(prompt)
            }
        }
    }

    private func userPromptBubble(_ content: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(content)
                .font(SnapAIUI.Typography.bodyText)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.6)
                }
        }
    }

    private func priorAssistantCard(_ message: ConversationMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownView(text: message.content, onCopyCode: onCopyCode)
                .font(SnapAIUI.Typography.readingText)
                .lineSpacing(4)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                let modelLabel = [message.providerName, message.modelName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !modelLabel.isEmpty {
                    Text(modelLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if !message.isComplete {
                    Text("部分回复")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(SnapAIUI.StatusColor.warning)
                }
                Spacer(minLength: 4)
                Button {
                    onBranch(message.id)
                } label: {
                    Label("从此处分支", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isGenerating)
                .help("保留到此轮回复并开启新分支继续追问")
            }
            .padding(.top, 2)

            SnapAIFormDivider(inset: 0)
                .padding(.top, 4)
        }
    }
}
