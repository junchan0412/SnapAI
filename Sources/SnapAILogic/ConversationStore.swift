import Foundation
import SQLite3

package final class ConversationStore {
    package static let shared = ConversationStore()
    private let url: URL
    private let lock = NSLock()

    package init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    package func save(_ session: ConversationSession, historyLimit: Int,
                      contentStorage: HistoryContentStorage,
                      protectsContent: Bool = false) -> Result<Bool, Error> {
        access { db in
            try self.transaction(db) {
                guard historyLimit > 0, session.action.saveHistory,
                      contentStorage == .full, !protectsContent else {
                    try self.execute(db, "DELETE FROM conversation_sessions WHERE id = ?;", [session.id])
                    return false
                }
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let payload = try encoder.encode(session)
                let summary = try encoder.encode(session.summary)
                try self.execute(db, """
                INSERT INTO conversation_sessions(id, updatedAt, summary, payload) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET updatedAt = excluded.updatedAt,
                    summary = excluded.summary, payload = excluded.payload;
                """, [session.id, session.updatedAt.timeIntervalSince1970, summary, payload])
                try self.prune(db, limit: historyLimit)
                return true
            }
        }
    }

    package func load(id: String) -> Result<ConversationSession?, Error> {
        access { db in
            let statement = try self.prepare(db, "SELECT payload FROM conversation_sessions WHERE id = ?;", [id])
            defer { sqlite3_finalize(statement) }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW else { throw self.failure(db) }
            return try PropertyListDecoder().decode(ConversationSession.self, from: self.blob(statement, column: 0))
        }
    }

    package func list(limit: Int) -> Result<[ConversationSessionSummary], Error> {
        access { db in
            let statement = try self.prepare(db, """
            SELECT summary FROM conversation_sessions ORDER BY updatedAt DESC, id DESC LIMIT ?;
            """, [max(0, limit)])
            defer { sqlite3_finalize(statement) }
            var sessions: [ConversationSessionSummary] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                sessions.append(try PropertyListDecoder().decode(ConversationSessionSummary.self,
                                                                from: self.blob(statement, column: 0)))
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw self.failure(db) }
            return sessions
        }
    }

    package func delete(id: String) -> Result<Void, Error> {
        access { db in try self.execute(db, "DELETE FROM conversation_sessions WHERE id = ?;", [id]) }
    }

    package func deleteAll() -> Result<Void, Error> {
        access { db in try self.execute(db, "DELETE FROM conversation_sessions;") }
    }

    package func prune(limit: Int) -> Result<Void, Error> {
        access { db in try self.prune(db, limit: limit) }
    }

    private func access<Value>(_ operation: (OpaquePointer) throws -> Value) -> Result<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var connection: OpaquePointer?
            guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                  let connection else {
                let error = failure(connection)
                if let connection { sqlite3_close_v2(connection) }
                throw error
            }
            defer { sqlite3_close_v2(connection) }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            sqlite3_busy_timeout(connection, 1_000)
            try execute(connection, "PRAGMA secure_delete=ON;")
            try execute(connection, """
            CREATE TABLE IF NOT EXISTS conversation_sessions (
                id TEXT PRIMARY KEY NOT NULL, updatedAt REAL NOT NULL,
                summary BLOB NOT NULL, payload BLOB NOT NULL
            );
            """)
            try execute(connection, "CREATE INDEX IF NOT EXISTS conversation_sessions_updated ON conversation_sessions(updatedAt DESC, id DESC);")
            return .success(try operation(connection))
        } catch {
            return .failure(error)
        }
    }

    private func prune(_ db: OpaquePointer, limit: Int) throws {
        try execute(db, """
        DELETE FROM conversation_sessions WHERE id IN (
            SELECT id FROM conversation_sessions ORDER BY updatedAt DESC, id DESC LIMIT -1 OFFSET ?
        );
        """, [max(0, limit)])
    }

    private func transaction<Value>(_ db: OpaquePointer, _ operation: () throws -> Value) throws -> Value {
        try execute(db, "BEGIN IMMEDIATE;")
        do {
            let value = try operation()
            try execute(db, "COMMIT;")
            return value
        } catch {
            try? execute(db, "ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ db: OpaquePointer, _ sql: String, _ values: [Any] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure(db)
        }
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case let value as String:
                    status = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), conversationSQLTransient) }
                case let value as Double:
                    status = sqlite3_bind_double(statement, index, value)
                case let value as Int:
                    status = sqlite3_bind_int64(statement, index, Int64(value))
                case let value as Data:
                    status = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), conversationSQLTransient) }
                default:
                    throw ConversationFailure("会话存储参数无效。")
                }
                guard status == SQLITE_OK else { throw failure(db) }
            }
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func execute(_ db: OpaquePointer, _ sql: String, _ values: [Any] = []) throws {
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw failure(db) }
    }

    private func blob(_ statement: OpaquePointer, column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func failure(_ db: OpaquePointer?) -> ConversationFailure {
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
        return ConversationFailure("会话存储失败：\(detail)")
    }

    private static func defaultURL() -> URL {
        if ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] == "1" {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SnapAI-LogicTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
                .appendingPathComponent("conversations.sqlite")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("SnapAI", isDirectory: true).appendingPathComponent("conversations.sqlite")
    }
}

private let conversationSQLTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
