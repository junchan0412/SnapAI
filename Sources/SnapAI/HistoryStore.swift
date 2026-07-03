import Foundation
import SQLite3

final class HistoryStore {
    static let shared = HistoryStore()
    private static let statusLock = NSLock()
    private static var latestStatus = "ok"

    static var latestStatusLine: String {
        statusLock.lock()
        defer { statusLock.unlock() }
        return latestStatus
    }

    private let url: URL
    private let lock = NSLock()

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    func load(limit: Int) -> [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        var db: OpaquePointer?
        do {
            try open(&db)
            guard let db else { throw HistoryStoreFailure("failed to open history store: database unavailable") }
            defer { sqlite3_close(db) }
            try migrate(db)

            let sql = """
            SELECT id, date, actionName, source, output, provider, model, isFavorite, tagsJSON
            FROM history_entries
            ORDER BY date DESC
            LIMIT ?;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw error(db, prefix: "history SQL prepare failed")
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(max(0, limit)))

            var entries: [HistoryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let entry = entry(from: statement) {
                    entries.append(entry)
                }
            }
            Self.recordSuccess()
            return entries
        } catch {
            Self.recordFailure(error)
            return []
        }
    }

    func search(_ query: String, limit: Int) -> [HistoryEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return load(limit: limit) }
        lock.lock()
        defer { lock.unlock() }
        var db: OpaquePointer?
        do {
            try open(&db)
            guard let db else { throw HistoryStoreFailure("failed to open history store: database unavailable") }
            defer { sqlite3_close(db) }
            try migrate(db)

            let sql = """
            SELECT h.id, h.date, h.actionName, h.source, h.output, h.provider, h.model, h.isFavorite, h.tagsJSON
            FROM history_fts f
            JOIN history_entries h ON h.id = f.id
            WHERE history_fts MATCH ?
            ORDER BY bm25(history_fts), h.date DESC
            LIMIT ?;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw error(db, prefix: "history SQL prepare failed")
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, ftsQuery(normalized), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(max(0, limit)))

            var entries: [HistoryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let entry = entry(from: statement) {
                    entries.append(entry)
                }
            }
            Self.recordSuccess()
            return entries
        } catch {
            Self.recordFailure(error)
            return []
        }
    }

    @discardableResult
    func replaceAll(_ entries: [HistoryEntry], limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var db: OpaquePointer?
        do {
            try open(&db)
            guard let db else { throw HistoryStoreFailure("failed to open history store: database unavailable") }
            defer { sqlite3_close(db) }
            try migrate(db)
            try transaction(db) {
                try execute(db, "DELETE FROM history_fts;")
                try execute(db, "DELETE FROM history_entries;")
                for entry in entries.prefix(max(0, limit)) {
                    try upsert(entry, db: db)
                }
            }
            Self.recordSuccess()
            return true
        } catch {
            Self.recordFailure(error)
            return false
        }
    }

    @discardableResult
    func upsert(_ entry: HistoryEntry, limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var db: OpaquePointer?
        do {
            try open(&db)
            guard let db else { throw HistoryStoreFailure("failed to open history store: database unavailable") }
            defer { sqlite3_close(db) }
            try migrate(db)
            try transaction(db) {
                try upsert(entry, db: db)
                try prune(db, limit: limit)
            }
            Self.recordSuccess()
            return true
        } catch {
            Self.recordFailure(error)
            return false
        }
    }

    @discardableResult
    func delete(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var db: OpaquePointer?
        do {
            try open(&db)
            guard let db else { throw HistoryStoreFailure("failed to open history store: database unavailable") }
            defer { sqlite3_close(db) }
            try migrate(db)
            try transaction(db) {
                try execute(db, "DELETE FROM history_fts WHERE id = ?;", [id])
                try execute(db, "DELETE FROM history_entries WHERE id = ?;", [id])
            }
            Self.recordSuccess()
            return true
        } catch {
            Self.recordFailure(error)
            return false
        }
    }

    @discardableResult
    func deleteAll() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var db: OpaquePointer?
        do {
            try open(&db)
            guard let db else { throw HistoryStoreFailure("failed to open history store: database unavailable") }
            defer { sqlite3_close(db) }
            try migrate(db)
            try transaction(db) {
                try execute(db, "DELETE FROM history_fts;")
                try execute(db, "DELETE FROM history_entries;")
            }
            Self.recordSuccess()
            return true
        } catch {
            Self.recordFailure(error)
            return false
        }
    }

    private func open(_ db: inout OpaquePointer?) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            throw HistoryStoreFailure("failed to create history store directory: \(error.localizedDescription)")
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let failure = error(db, prefix: "failed to open history store")
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
            throw failure
        }
        do {
            try execute(db, "PRAGMA journal_mode=WAL;")
            try execute(db, "PRAGMA foreign_keys=ON;")
        } catch {
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
            throw error
        }
    }

    private func migrate(_ db: OpaquePointer?) throws {
        try execute(db, """
        CREATE TABLE IF NOT EXISTS history_entries (
            id TEXT PRIMARY KEY NOT NULL,
            date REAL NOT NULL,
            actionName TEXT NOT NULL,
            source TEXT NOT NULL,
            output TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            isFavorite INTEGER NOT NULL,
            tagsJSON TEXT NOT NULL
        );
        """)
        try execute(db, """
        CREATE VIRTUAL TABLE IF NOT EXISTS history_fts USING fts5(
            id UNINDEXED,
            actionName,
            source,
            output,
            provider,
            model,
            tags
        );
        """)
    }

    private func upsert(_ entry: HistoryEntry, db: OpaquePointer?) throws {
        let tagsJSON = (try? String(data: JSONEncoder().encode(entry.displayTags), encoding: .utf8)) ?? "[]"
        try execute(db, """
        INSERT OR REPLACE INTO history_entries
        (id, date, actionName, source, output, provider, model, isFavorite, tagsJSON)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            entry.id,
            entry.date.timeIntervalSince1970,
            entry.actionName,
            entry.source,
            entry.output,
            entry.provider,
            entry.model,
            entry.isFavorite ? 1 : 0,
            tagsJSON
        ])
        try execute(db, "DELETE FROM history_fts WHERE id = ?;", [entry.id])
        try execute(db, """
        INSERT INTO history_fts (id, actionName, source, output, provider, model, tags)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, [
            entry.id,
            entry.actionName,
            entry.source,
            entry.output,
            entry.provider,
            entry.model,
            entry.displayTags.joined(separator: " ")
        ])
    }

    private func prune(_ db: OpaquePointer?, limit: Int) throws {
        guard limit >= 0 else { return }
        try execute(db, """
        DELETE FROM history_fts
        WHERE id IN (
            SELECT id FROM history_entries
            ORDER BY date DESC
            LIMIT -1 OFFSET ?
        );
        """, [limit])
        try execute(db, """
        DELETE FROM history_entries
        WHERE id IN (
            SELECT id FROM history_entries
            ORDER BY date DESC
            LIMIT -1 OFFSET ?
        );
        """, [limit])
    }

    private func execute(_ db: OpaquePointer?,
                         _ sql: String,
                         _ values: [Any] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(db, prefix: "history SQL prepare failed")
        }
        defer { sqlite3_finalize(statement) }
        bind(values, to: statement)
        let status = sqlite3_step(statement)
        if status != SQLITE_DONE && status != SQLITE_ROW {
            throw error(db, prefix: "history SQL failed")
        }
    }

    private func transaction(_ db: OpaquePointer?, _ block: () throws -> Void) throws {
        do {
            try execute(db, "BEGIN IMMEDIATE;")
            try block()
            try execute(db, "COMMIT;")
        } catch {
            try? execute(db, "ROLLBACK;")
            throw error
        }
    }

    private func error(_ db: OpaquePointer?, prefix: String) -> HistoryStoreFailure {
        if let db {
            return HistoryStoreFailure("\(prefix): \(String(cString: sqlite3_errmsg(db)))")
        }
        return HistoryStoreFailure("\(prefix): database unavailable")
    }

    private static func recordSuccess() {
        statusLock.lock()
        latestStatus = "ok"
        statusLock.unlock()
    }

    private static func recordFailure(_ error: Error) {
        let message = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription, limit: 240)
        NSLog("SnapAI: history store failure: \(message)")
        statusLock.lock()
        latestStatus = "error: \(message)"
        statusLock.unlock()
    }

    private func bind(_ values: [Any], to statement: OpaquePointer?) {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let value as String:
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            case let value as Int:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as Bool:
                sqlite3_bind_int(statement, position, value ? 1 : 0)
            default:
                sqlite3_bind_null(statement, position)
            }
        }
    }

    private func entry(from statement: OpaquePointer?) -> HistoryEntry? {
        guard let id = text(statement, 0) else { return nil }
        return HistoryEntry(id: id,
                            date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                            actionName: text(statement, 2) ?? "",
                            source: text(statement, 3) ?? "",
                            output: text(statement, 4) ?? "",
                            provider: text(statement, 5) ?? "",
                            model: text(statement, 6) ?? "",
                            isFavorite: sqlite3_column_int(statement, 7) != 0,
                            tags: decodedTags(text(statement, 8)))
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func decodedTags(_ tagsJSON: String?) -> [String] {
        guard let data = tagsJSON?.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tags
    }

    private func ftsQuery(_ query: String) -> String {
        let terms = HistoryFilterCriteria.normalizedQueryTerms(query)
        guard !terms.isEmpty else { return "\"\"" }
        return terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " AND ")
    }

    private static func defaultURL() -> URL {
        if ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] == "1" {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("SnapAI-LogicTests", isDirectory: true)
                .appendingPathComponent("history.sqlite")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SnapAI", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }
}

private struct HistoryStoreFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
