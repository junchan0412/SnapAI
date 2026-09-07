import Foundation
import SQLite3

package final class HistoryStore {
    package static let shared = HistoryStore()
    private static let statusLock = NSLock()
    private static let bootstrapLock = NSLock()
    private static var latestStatus = "ok"
    private static let schemaVersion = 1
    private static let entryColumns = "id, date, actionName, source, output, provider, model, isFavorite, tagsJSON"
    private static let upsertSQL = """
    INSERT INTO history_entries (id, date, actionName, source, output, provider, model, isFavorite, tagsJSON)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        date = excluded.date, actionName = excluded.actionName, source = excluded.source,
        output = excluded.output, provider = excluded.provider, model = excluded.model,
        isFavorite = excluded.isFavorite, tagsJSON = excluded.tagsJSON;
    """

    package static var latestStatusLine: String {
        statusLock.lock()
        defer { statusLock.unlock() }
        return latestStatus
    }

    private let url: URL
    private let lock = NSLock()
    private var connection: OpaquePointer?
    private var fileIdentity: FileIdentity?

    package init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    deinit {
        closeConnection()
    }

    package func load(limit: Int) -> [HistoryEntry] {
        (try? loadResult(limit: limit).get()) ?? []
    }

    package func loadResult(limit: Int) -> Result<[HistoryEntry], Error> {
        access { db in
            try query(db, """
            SELECT \(Self.entryColumns) FROM history_entries
            ORDER BY date DESC, id DESC LIMIT ?;
            """, [max(0, limit)])
        }
    }

    package func search(_ query: String, limit: Int) -> [HistoryEntry] {
        let terms = HistoryFilterCriteria.normalizedQueryTerms(query)
        guard !terms.isEmpty else { return load(limit: limit) }
        let match = terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " AND ")
        return (try? access { db in
            try self.query(db, """
            SELECT h.id, h.date, h.actionName, h.source, h.output, h.provider, h.model, h.isFavorite, h.tagsJSON
            FROM history_fts f JOIN history_entries h ON h.rowid = f.rowid
            WHERE history_fts MATCH ?
            ORDER BY bm25(history_fts), h.date DESC, h.id DESC LIMIT ?;
            """, [match, max(0, limit)])
        }.get()) ?? []
    }

    @discardableResult
    package func replaceAll(_ entries: [HistoryEntry], limit: Int) -> Bool {
        write { db in
            try execute(db, "DELETE FROM history_entries;")
            let statement = try prepare(db, Self.upsertSQL)
            defer { sqlite3_finalize(statement) }
            for entry in entries.prefix(max(0, limit)) {
                try upsert(entry, db: db, statement: statement)
            }
        }
    }

    @discardableResult
    package func upsert(_ entry: HistoryEntry, limit: Int) -> Bool {
        write { db in
            let statement = try prepare(db, Self.upsertSQL)
            defer { sqlite3_finalize(statement) }
            try upsert(entry, db: db, statement: statement)
            try prune(db, limit: limit)
        }
    }

    @discardableResult
    package func prune(limit: Int) -> Bool {
        write { db in try prune(db, limit: limit) }
    }

    @discardableResult
    package func delete(id: String) -> Bool {
        write { db in try execute(db, "DELETE FROM history_entries WHERE id = ?;", [id]) }
    }

    @discardableResult
    package func deleteAll() -> Bool {
        write { db in try execute(db, "DELETE FROM history_entries;") }
    }

    private func access<Value>(_ operation: (OpaquePointer) throws -> Value) -> Result<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        do {
            let value = try operation(database())
            Self.recordSuccess()
            return .success(value)
        } catch {
            closeConnection()
            Self.recordFailure(error)
            return .failure(error)
        }
    }

    private func write(_ operation: (OpaquePointer) throws -> Void) -> Bool {
        (try? access { db in
            try transaction(db) { try operation(db) }
            return true
        }.get()) ?? false
    }

    private func database() throws -> OpaquePointer {
        if let connection {
            if fileIdentity == FileIdentity(url: url) { return connection }
            closeConnection()
        }
        Self.bootstrapLock.lock()
        defer { Self.bootstrapLock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            let failure = error(db, prefix: "failed to open history store")
            if let db { sqlite3_close_v2(db) }
            throw failure
        }
        do {
            sqlite3_busy_timeout(db, 1_000)
            try execute(db, "PRAGMA journal_mode=WAL;")
            try execute(db, "PRAGMA foreign_keys=ON;")
            try migrate(db)
            guard let identity = FileIdentity(url: url) else {
                throw HistoryStoreFailure("failed to read history store file identity")
            }
            connection = db
            fileIdentity = identity
            return db
        } catch {
            sqlite3_close_v2(db)
            throw error
        }
    }

    private func closeConnection() {
        if let connection { sqlite3_close_v2(connection) }
        connection = nil
        fileIdentity = nil
    }

    private func migrate(_ db: OpaquePointer) throws {
        let version = try readSchemaVersion(db)
        guard version <= Self.schemaVersion else {
            throw HistoryStoreFailure("history store requires a newer app version")
        }
        guard version < Self.schemaVersion else { return }
        try transaction(db) {
            let lockedVersion = try readSchemaVersion(db)
            guard lockedVersion <= Self.schemaVersion else {
                throw HistoryStoreFailure("history store requires a newer app version")
            }
            guard lockedVersion < Self.schemaVersion else { return }
            try migrateLegacySchema(db)
        }
    }

    private func readSchemaVersion(_ db: OpaquePointer) throws -> Int32 {
        let statement = try prepare(db, "PRAGMA user_version;")
        let status = sqlite3_step(statement)
        let version = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        guard status == SQLITE_ROW else { throw error(db, prefix: "history schema read failed") }
        return version
    }

    private func migrateLegacySchema(_ db: OpaquePointer) throws {
        try execute(db, """
        CREATE TABLE IF NOT EXISTS history_entries (
            id TEXT PRIMARY KEY NOT NULL, date REAL NOT NULL, actionName TEXT NOT NULL,
            source TEXT NOT NULL, output TEXT NOT NULL, provider TEXT NOT NULL,
            model TEXT NOT NULL, isFavorite INTEGER NOT NULL, tagsJSON TEXT NOT NULL
        );
        """)
        try execute(db, "CREATE INDEX IF NOT EXISTS history_entries_date ON history_entries(date DESC, id DESC);")
        // Only the derived search index is rebuilt; the original history table stays intact.
        try execute(db, "DROP TABLE IF EXISTS history_fts;")
        try execute(db, """
        CREATE VIRTUAL TABLE history_fts USING fts5(
            actionName, source, output, provider, model, tagsJSON,
            content='history_entries', content_rowid='rowid'
        );
        """)
        try execute(db, """
        CREATE TRIGGER history_entries_ai AFTER INSERT ON history_entries BEGIN
            INSERT INTO history_fts(rowid, actionName, source, output, provider, model, tagsJSON)
            VALUES (new.rowid, new.actionName, new.source, new.output, new.provider, new.model, new.tagsJSON);
        END;
        """)
        try execute(db, """
        CREATE TRIGGER history_entries_ad AFTER DELETE ON history_entries BEGIN
            INSERT INTO history_fts(history_fts, rowid, actionName, source, output, provider, model, tagsJSON)
            VALUES ('delete', old.rowid, old.actionName, old.source, old.output, old.provider, old.model, old.tagsJSON);
        END;
        """)
        try execute(db, """
        CREATE TRIGGER history_entries_au AFTER UPDATE ON history_entries
        WHEN old.actionName IS NOT new.actionName OR old.source IS NOT new.source
          OR old.output IS NOT new.output OR old.provider IS NOT new.provider
          OR old.model IS NOT new.model OR old.tagsJSON IS NOT new.tagsJSON BEGIN
            INSERT INTO history_fts(history_fts, rowid, actionName, source, output, provider, model, tagsJSON)
            VALUES ('delete', old.rowid, old.actionName, old.source, old.output, old.provider, old.model, old.tagsJSON);
            INSERT INTO history_fts(rowid, actionName, source, output, provider, model, tagsJSON)
            VALUES (new.rowid, new.actionName, new.source, new.output, new.provider, new.model, new.tagsJSON);
        END;
        """)
        try execute(db, "INSERT INTO history_fts(history_fts) VALUES ('rebuild');")
        try execute(db, "PRAGMA user_version=\(Self.schemaVersion);")
    }

    private func upsert(_ entry: HistoryEntry, db: OpaquePointer, statement: OpaquePointer) throws {
        let tagsJSON = String(decoding: try JSONEncoder().encode(entry.displayTags), as: UTF8.self)
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind([entry.id, entry.date.timeIntervalSince1970, entry.actionName, entry.source,
                  entry.output, entry.provider, entry.model, entry.isFavorite ? 1 : 0, tagsJSON],
                 to: statement, db: db)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error(db, prefix: "history write failed") }
    }

    private func prune(_ db: OpaquePointer, limit: Int) throws {
        try execute(db, """
        DELETE FROM history_entries WHERE id IN (
            SELECT id FROM history_entries ORDER BY date DESC, id DESC LIMIT -1 OFFSET ?
        );
        """, [max(0, limit)])
    }

    private func query(_ db: OpaquePointer, _ sql: String, _ values: [Any]) throws -> [HistoryEntry] {
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, db: db)
        var entries: [HistoryEntry] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let entry = entry(from: statement) { entries.append(entry) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw error(db, prefix: "history read failed") }
        return entries
    }

    private func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw error(db, prefix: "history SQL prepare failed")
        }
        return statement
    }

    private func execute(_ db: OpaquePointer, _ sql: String, _ values: [Any] = []) throws {
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, db: db)
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw error(db, prefix: "history SQL failed") }
    }

    private func transaction(_ db: OpaquePointer, _ block: () throws -> Void) throws {
        try execute(db, "BEGIN IMMEDIATE;")
        do {
            try block()
            try execute(db, "COMMIT;")
        } catch {
            try? execute(db, "ROLLBACK;")
            throw error
        }
    }

    private func bind(_ values: [Any], to statement: OpaquePointer, db: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case let value as String:
                status = value.withCString { sqlite3_bind_text(statement, position, $0, Int32(value.utf8.count), SQLITE_TRANSIENT) }
            case let value as Int:
                status = sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Double:
                status = sqlite3_bind_double(statement, position, value)
            default:
                throw HistoryStoreFailure("unsupported history SQL value")
            }
            guard status == SQLITE_OK else { throw error(db, prefix: "history SQL bind failed") }
        }
    }

    private func entry(from statement: OpaquePointer) -> HistoryEntry? {
        guard let id = text(statement, 0) else { return nil }
        let tagsData = Data((text(statement, 8) ?? "[]").utf8)
        return HistoryEntry(id: id,
                            date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                            actionName: text(statement, 2) ?? "",
                            source: text(statement, 3) ?? "",
                            output: text(statement, 4) ?? "",
                            provider: text(statement, 5) ?? "",
                            model: text(statement, 6) ?? "",
                            isFavorite: sqlite3_column_int(statement, 7) != 0,
                            tags: (try? JSONDecoder().decode([String].self, from: tagsData)) ?? [])
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }

    private func error(_ db: OpaquePointer?, prefix: String) -> HistoryStoreFailure {
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
        return HistoryStoreFailure("\(prefix): \(detail)")
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

    private static func defaultURL() -> URL {
        if ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] == "1" {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SnapAI-LogicTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
                .appendingPathComponent("history.sqlite")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SnapAI", isDirectory: true).appendingPathComponent("history.sqlite")
    }

    private struct FileIdentity: Equatable {
        var device: UInt64
        var inode: UInt64

        init?(url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            self.device = device.uint64Value
            self.inode = inode.uint64Value
        }
    }
}

private struct HistoryStoreFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
