import Foundation

package struct ConversationMessage: Codable, Equatable, Identifiable {
    package enum Role: String, Codable { case system, user, assistant }

    package var id: String
    package var date: Date
    package var role: Role
    package var content: String
    package var imageData: Data?
    package var imageMimeType: String
    package var providerName: String
    package var modelName: String
    package var isComplete: Bool

    package init(_ message: ChatMessage, id: String = UUID().uuidString,
                 date: Date = Date(), providerName: String = "", modelName: String = "",
                 isComplete: Bool = true) {
        self.id = id
        self.date = date
        switch message.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        }
        content = message.content
        imageData = message.imageData
        imageMimeType = message.imageMimeType
        self.providerName = providerName
        self.modelName = modelName
        self.isComplete = isComplete
    }

    package var chatMessage: ChatMessage {
        let chatRole: ChatMessage.Role
        switch role {
        case .system: chatRole = .system
        case .user: chatRole = .user
        case .assistant: chatRole = .assistant
        }
        return ChatMessage(role: chatRole, content: content,
                           imageData: imageData, imageMimeType: imageMimeType)
    }
}

package struct ConversationCompression: Codable, Equatable, Identifiable {
    package var id: String
    package var date: Date
    package var throughMessageID: String
    package var summary: String
}

package struct ConversationSession: Codable, Equatable, Identifiable {
    package var id: String
    package var createdAt: Date
    package var updatedAt: Date
    package var action: AIAction
    package var sourceText: String
    package var sourceImageData: Data?
    package var sourceImageMimeType: String
    package var sourceImageWasSubmitted: Bool?
    package var messages: [ConversationMessage]
    package private(set) var parentSessionID: String?
    package private(set) var branchPointMessageID: String?
    package private(set) var compressions: [ConversationCompression]
    package private(set) var activeCompressionID: String?

    package init(id: String = UUID().uuidString, date: Date = Date(), action: AIAction,
                 sourceText: String, sourceImageData: Data? = nil,
                 sourceImageMimeType: String = "image/png", sourceImageWasSubmitted: Bool = true, messages: [ConversationMessage] = []) {
        self.id = id
        createdAt = date
        updatedAt = date
        self.action = action
        self.sourceText = sourceText
        self.sourceImageData = sourceImageData
        self.sourceImageMimeType = sourceImageMimeType
        self.sourceImageWasSubmitted = sourceImageWasSubmitted
        self.messages = messages
        compressions = []
    }

    package var activeCompression: ConversationCompression? {
        compressions.first { $0.id == activeCompressionID }
    }

    package var contextMessages: [ChatMessage] {
        guard let compression = activeCompression,
              let boundary = messages.firstIndex(where: { $0.id == compression.throughMessageID }) else {
            return messages.map(\.chatMessage)
        }
        let systems = messages[...boundary].filter { $0.role == .system }.map(\.chatMessage)
        let summary = ChatMessage(role: .user, content: "以下是已确认的先前对话摘要：\n\n\(compression.summary)")
        return systems + [summary] + messages.dropFirst(boundary + 1).map(\.chatMessage)
    }

    package var compressedMessageCount: Int {
        guard let compression = activeCompression,
              let boundary = messages.firstIndex(where: { $0.id == compression.throughMessageID }) else { return 0 }
        return messages[...boundary].filter { $0.role != .system }.count
    }

    @discardableResult
    package mutating func compress(throughMessageID: String, summary: String,
                                   date: Date = Date()) throws -> ConversationCompression {
        guard let boundary = messages.firstIndex(where: { $0.id == throughMessageID }),
              messages[boundary].role == .assistant, messages[boundary].isComplete,
              messages[...boundary].contains(where: { $0.role == .user }) else {
            throw ConversationFailure("请选择一个已完成回复作为压缩终点。")
        }
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw ConversationFailure("压缩摘要不能为空。") }
        let compression = ConversationCompression(id: UUID().uuidString, date: date,
                                                  throughMessageID: throughMessageID, summary: summary)
        compressions.append(compression)
        activeCompressionID = compression.id
        updatedAt = date
        return compression
    }

    package mutating func activateCompression(id: String?, date: Date = Date()) throws {
        if let id, !compressions.contains(where: { $0.id == id }) {
            throw ConversationFailure("找不到这条压缩记录。")
        }
        activeCompressionID = id
        updatedAt = date
    }

    package func branch(throughMessageID: String? = nil, date: Date = Date()) throws -> ConversationSession {
        let boundary: Int
        if let throughMessageID {
            guard let index = messages.firstIndex(where: { $0.id == throughMessageID }) else {
                throw ConversationFailure("找不到所选的分支起点。")
            }
            boundary = index
        } else {
            boundary = messages.count - 1
        }
        var branch = self
        branch.id = UUID().uuidString
        branch.createdAt = date
        branch.updatedAt = date
        branch.parentSessionID = id
        branch.branchPointMessageID = boundary >= 0 ? messages[boundary].id : nil
        branch.messages = Array(messages.prefix(boundary + 1))
        let retainedIDs = Set(branch.messages.map(\.id))
        branch.compressions = compressions.filter { retainedIDs.contains($0.throughMessageID) }
        if !branch.compressions.contains(where: { $0.id == activeCompressionID }) {
            branch.activeCompressionID = nil
        }
        return branch
    }

    package var summary: ConversationSessionSummary {
        ConversationSessionSummary(id: id, createdAt: createdAt, updatedAt: updatedAt,
                                   actionName: action.name,
                                   preview: String(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
                                   messageCount: messages.filter { $0.role != .system }.count,
                                   hasImage: sourceImageData != nil || messages.contains { $0.imageData != nil },
                                   parentSessionID: parentSessionID,
                                   isCompressed: activeCompression != nil)
    }
}

package struct ConversationSessionSummary: Codable, Equatable, Identifiable {
    package var id: String
    package var createdAt: Date
    package var updatedAt: Date
    package var actionName: String
    package var preview: String
    package var messageCount: Int
    package var hasImage: Bool
    package var parentSessionID: String?
    package var isCompressed: Bool
}

package struct ConversationFailure: LocalizedError {
    package let message: String
    package init(_ message: String) { self.message = message }
    package var errorDescription: String? { message }
}
