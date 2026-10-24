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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("已保存会话").font(.title2)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("恢复全部轮次和原图，不会自动发送请求。会话仅保存在本机，并遵守历史保存上限；关闭正文保存后会清除已保存会话。")
                .font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            if sessions.isEmpty {
                Text("暂无可恢复会话。请在允许保存完整历史时完成一次提问。")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.preview.isEmpty ? session.actionName : session.preview).lineLimit(2)
                            Text("\(session.actionName) · \(session.messageCount) 条消息\(session.hasImage ? " · 含图片" : "")\(session.parentSessionID != nil ? " · 分支" : "")\(session.isCompressed ? " · 已压缩" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(session.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") { open(session) }
                        Button("删除", role: .destructive) { pendingDeletion = session }
                    }.padding(.vertical, 6)
                }
            }
        }
        .padding(20).frame(minWidth: 580, minHeight: 440)
        .task { reload() }
        .confirmationDialog("删除此会话及其图片？", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
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
        }
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

struct ResultConversationView: View {
    @ObservedObject var vm: ResultViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var boundaryID = ""
    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("会话与分支").font(.title2)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let session = vm.conversationSession {
                Text("\(session.messages.filter { $0.role != .system }.count) 条消息\(session.parentSessionID != nil ? " · 当前为分支" : "")")
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let data = session.sourceImageData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                                .accessibilityLabel("会话原图，仅保存在本机")
                        }
                        ForEach(session.messages.filter { $0.role != .system }) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.role == .user ? "你" : "\(message.providerName) / \(message.modelName)\(message.isComplete ? "" : " · 部分回复")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(message.content).textSelection(.enabled)
                                if message.role == .assistant {
                                    Button("从此处创建分支") {
                                        vm.branchConversation(through: message.id)
                                        dismiss()
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(8)
                }
                if let compression = session.activeCompression {
                    Text("已用摘要替代前 \(session.compressedMessageCount) 条消息；原始内容仍保留。")
                        .font(.callout)
                    Text(compression.summary).lineLimit(4).textSelection(.enabled)
                    Button("撤销压缩，恢复完整上下文") { vm.disableConversationCompression() }
                }
                Divider()
                Text("压缩上下文").font(.headline)
                Text("填写并确认摘要后，下次追问只发送摘要和其后的消息。摘要应保留事实、约束和未完成任务；被压缩轮次中的图片不会再次上传。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("压缩到", selection: $boundaryID) {
                    Text("选择已完成的回复").tag("")
                    ForEach(session.messages.filter { $0.role == .assistant && $0.isComplete }) { message in
                        Text(String(message.content.prefix(55))).tag(message.id)
                    }
                }
                TextEditor(text: $summary).frame(height: 90).border(Color.secondary.opacity(0.3))
                    .accessibilityLabel("确认要用于后续请求的摘要")
                Button("确认使用此摘要") {
                    vm.compressConversation(through: boundaryID, summary: summary)
                    summary = ""
                }.disabled(boundaryID.isEmpty || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text("完成一次提问后即可查看轮次、创建分支和压缩上下文。")
            }
            ResultOperationFeedbackHost(coordinator: vm.operationCoordinator)
        }
        .padding(20).frame(width: 620, height: 700)
        .disabled(vm.isGenerating)
    }
}
