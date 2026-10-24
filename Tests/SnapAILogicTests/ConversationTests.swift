import Foundation
import SQLite3
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

private func conversationExpect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    let passed = try condition()
    expect(passed, message)
}

private func conversationFixture(date: Date = Date(timeIntervalSince1970: 1_000)) -> ConversationSession {
    let image = Data((0..<4_096).map { UInt8($0 % 256) })
    let messages: [ChatMessage] = [
        ChatMessage(role: .system, content: "保留格式与数字。"),
        ChatMessage(role: .user, content: "图表中的\u{0}成本为 42.5。", imageData: image, imageMimeType: "image/jpeg"),
        ChatMessage(role: .assistant, content: "成本是 42.5。"),
        ChatMessage(role: .user, content: "换算成百分比。"),
        ChatMessage(role: .assistant, content: "缺少分母，无法换算。")
    ]
    return ConversationSession(date: date, action: AIAction(name: "分析", prompt: "分析 {{text}}"),
                               sourceText: "图表原文 👩🏽‍💻\n第二行", sourceImageData: image,
                               sourceImageMimeType: "image/jpeg",
                               messages: messages.enumerated().map { offset, message in
        ConversationMessage(message, id: "message-\(offset)", date: date,
                            providerName: message.role == .assistant ? "Provider \(offset)" : "",
                            modelName: message.role == .assistant ? "model-\(offset)" : "")
    })
}

private func withConversationStore(_ body: (URL, ConversationStore) throws -> Void) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("SnapAI-ConversationTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let url = directory.appendingPathComponent("conversations.sqlite")
        try body(url, ConversationStore(url: url))
    } catch {
        expect(false, "conversation operation failed: \(error)")
    }
}

func testConversationStoreRestoresAllTurnsAndOriginalImage() {
    withConversationStore { url, store in
        var session = conversationFixture()
        session.messages[2].content = String(repeating: "长回复，没有截断。\n", count: 20_000)
        session.messages[4].isComplete = false
        // OCR-only payload still retains its original image for restoring or resending.
        session.messages[1].imageData = nil
        try conversationExpect(try store.save(session, historyLimit: 50, contentStorage: .full).get(), "session is stored")
        let reopened = ConversationStore(url: url)
        let loaded = try reopened.load(id: session.id).get()
        expect(loaded == session, "reopening restores exact long text, all roles, turn metadata and image bytes")
        expect(loaded?.sourceImageData == session.sourceImageData && loaded?.messages[1].imageData == nil,
               "original image and OCR-only payload remain distinct")
        try conversationExpect(try reopened.list(limit: 50).get() == [session.summary], "list shows a lightweight session summary")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        expect(permissions?.intValue == 0o600, "conversation database restricts read access to its owner")
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            expect(false, "can inspect stored binary payload")
            return
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT typeof(payload), substr(payload, 1, 8) FROM conversation_sessions;", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        expect(sqlite3_step(statement) == SQLITE_ROW, "stored conversation can be queried")
        if let type = sqlite3_column_text(statement, 0), let pointer = sqlite3_column_blob(statement, 1) {
            expect(String(cString: type) == "blob" && Data(bytes: pointer, count: 8) == Data("bplist00".utf8),
                   "image-containing snapshot uses binary plist BLOB, not text image encoding")
        } else {
            expect(false, "stored payload has binary bytes")
        }
    }
}

func testConversationBranchPreservesOriginalAndSelectedPrefix() {
    withConversationStore { url, store in
        let source = conversationFixture()
        _ = try store.save(source, historyLimit: 50, contentStorage: .full).get()
        var branch = try source.branch(throughMessageID: source.messages[2].id,
                                       date: Date(timeIntervalSince1970: 2_000))
        expect(branch.id != source.id && branch.parentSessionID == source.id,
               "a branch has its own id and records the original version")
        expect(branch.branchPointMessageID == source.messages[2].id && branch.messages == Array(source.messages.prefix(3)),
               "a branch contains the exact selected prefix")
        branch.messages.append(ConversationMessage(ChatMessage(role: .user, content: "新的方向。")))
        branch.messages[2].content = "分支修改。"
        _ = try store.save(branch, historyLimit: 50, contentStorage: .full).get()
        let reopened = ConversationStore(url: url)
        try conversationExpect(try reopened.load(id: source.id).get() == source, "saving a branch never overwrites original turns")
        try conversationExpect(try reopened.load(id: branch.id).get() == branch, "independent branch survives reopening")
        expect(branch.sourceImageData == source.sourceImageData, "branch retains original image")
        do {
            _ = try source.branch(throughMessageID: "missing")
            expect(false, "unknown branch point must not silently branch elsewhere")
        } catch { }
    }
}

func testConversationCompressionIsVisibleReversibleAndRetainsOriginalTurns() {
    withConversationStore { url, store in
        var session = conversationFixture()
        let original = session.messages
        let compression = try session.compress(throughMessageID: original[2].id, summary: "成本为 42.5。")
        expect(session.messages == original && session.sourceImageData != nil,
               "compression leaves original text and image bytes intact")
        expect(session.activeCompression == compression && session.compressedMessageCount == 2,
               "active summary and exact compressed turn count are available for UI")
        let context = session.contextMessages
        expect(context.map(\.role) == [.system, .user, .user, .assistant],
               "compression preserves system instructions and every newer turn")
        expect(context[1].content.contains("成本为 42.5。") && context[2...] == original[3...].map(\.chatMessage)[...],
               "the approved summary replaces only the selected old prefix in request context")
        _ = try store.save(session, historyLimit: 50, contentStorage: .full).get()
        guard var reopened = try ConversationStore(url: url).load(id: session.id).get() else {
            expect(false, "compressed session can be reopened")
            return
        }
        expect(reopened == session, "summary, original transcript and active selection survive reopening")
        try reopened.activateCompression(id: nil)
        expect(reopened.contextMessages == original.map(\.chatMessage), "disabling compression restores exact original payload")
        expect(reopened.compressions == [compression], "disabling compression retains its visible history")
        try reopened.activateCompression(id: compression.id)
        expect(reopened.contextMessages == context, "a prior approved summary can be reactivated")
        let earlyBranch = try reopened.branch(throughMessageID: original[1].id)
        expect(earlyBranch.activeCompressionID == nil && earlyBranch.compressions.isEmpty,
               "a branch before the summary boundary does not include future conversation through that summary")
        let lateBranch = try reopened.branch(throughMessageID: original[4].id)
        expect(lateBranch.activeCompression == compression, "a branch after the boundary retains approved context selection")
    }
}

func testConversationCompressionRejectsUnusableBoundariesWithoutMutation() {
    var session = conversationFixture()
    let original = session
    for (boundary, summary) in [("missing", "摘要"), (session.messages[1].id, "摘要"), (session.messages[2].id, " \n ")] {
        do {
            _ = try session.compress(throughMessageID: boundary, summary: summary)
            expect(false, "invalid compression input is rejected")
        } catch { }
        expect(session == original, "failed compression cannot mutate transcript or active context")
    }
    session.messages[2].isComplete = false
    do {
        _ = try session.compress(throughMessageID: session.messages[2].id, summary: "部分结果摘要")
        expect(false, "partial output cannot be used as a completed compression boundary")
    } catch { }
    do {
        try session.activateCompression(id: "missing")
        expect(false, "unknown compression is rejected")
    } catch { }
    expect(session.activeCompressionID == nil, "failed activation leaves full context selected")
}

func testConversationStoreHonorsHistoryAndPrivacyPolicies() {
    withConversationStore { _, store in
        for policy in 0..<4 {
            var session = conversationFixture()
            try conversationExpect(try store.save(session, historyLimit: 50, contentStorage: .full).get(), "fixture initially persists")
            if policy == 0 { session.action.saveHistory = false }
            let saved = try store.save(session, historyLimit: policy == 1 ? 0 : 50,
                                       contentStorage: policy == 2 ? .metadataOnly : .full,
                                       protectsContent: policy == 3).get()
            expect(!saved, "action history, zero retention, metadata-only and protected-content gates reject transcript persistence")
            try conversationExpect(try store.load(id: session.id).get() == nil, "a newly protected session does not leave its old full snapshot behind")
        }
        try conversationExpect(try store.list(limit: 50).get().isEmpty, "no preview or image metadata leaks from non-persisted conversations")
    }
}

func testConversationStoreRetentionUpsertAndDeletion() {
    withConversationStore { _, store in
        var first = conversationFixture(date: Date(timeIntervalSince1970: 1))
        let second = conversationFixture(date: Date(timeIntervalSince1970: 2))
        let third = conversationFixture(date: Date(timeIntervalSince1970: 3))
        _ = try store.save(first, historyLimit: 2, contentStorage: .full).get()
        _ = try store.save(second, historyLimit: 2, contentStorage: .full).get()
        first.updatedAt = Date(timeIntervalSince1970: 4)
        first.messages.append(ConversationMessage(ChatMessage(role: .user, content: "继续。")))
        _ = try store.save(first, historyLimit: 2, contentStorage: .full).get()
        _ = try store.save(third, historyLimit: 2, contentStorage: .full).get()
        try conversationExpect(try store.list(limit: 10).get().map(\.id) == [first.id, third.id],
               "retention orders by latest activity and updating a session does not create another row")
        try conversationExpect(try store.load(id: second.id).get() == nil, "pruned conversations cannot be restored")
        try store.delete(id: first.id).get()
        try conversationExpect(try store.load(id: first.id).get() == nil, "deleted conversation cannot be restored")
        try store.deleteAll().get()
        try conversationExpect(try store.list(limit: 10).get().isEmpty, "clear removes all sessions")
        _ = try store.save(third, historyLimit: 2, contentStorage: .full).get()
        try store.prune(limit: 0).get()
        try conversationExpect(try store.list(limit: 10).get().isEmpty, "zero retention removes existing snapshots")
    }
}

func testConversationStoreReportsCorruptionAndWriteFailure() {
    withConversationStore { url, store in
        let session = conversationFixture()
        _ = try store.save(session, historyLimit: 50, contentStorage: .full).get()
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            expect(false, "fixture database opens")
            return
        }
        defer { sqlite3_close(db) }
        expect(sqlite3_exec(db, "UPDATE conversation_sessions SET payload = X'001122';", nil, nil, nil) == SQLITE_OK,
               "fixture corrupts persisted payload")
        switch store.load(id: session.id) {
        case .success: expect(false, "corruption cannot appear as an empty successful transcript")
        case .failure: break
        }
        expect(sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK, "fixture takes database write lock")
        defer { sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
        switch store.save(session, historyLimit: 50, contentStorage: .full) {
        case .success: expect(false, "failed persistence must not report the session as saved")
        case .failure: break
        }
    }
}
