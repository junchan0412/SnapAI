import Foundation
import SQLite3
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

private func storageEntry(_ index: Int, bodyLength: Int = 100) -> HistoryEntry {
    HistoryEntry(id: "record-\(index)",
                 date: Date(timeIntervalSince1970: Double(index)),
                 actionName: "总结",
                 source: "synthetic source \(index) " + String(repeating: "s", count: bodyLength),
                 output: "synthetic output \(index) " + String(repeating: "o", count: bodyLength),
                 provider: "Test",
                 model: "synthetic-model",
                 tags: ["fixture"])
}

private func withStorageFixture(_ body: (HistoryStore, URL, UserDefaults) throws -> Void) {
    let identifier = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapAI-StorageTests-\(identifier)", isDirectory: true)
    let suiteName = "SnapAI.StorageTests.\(identifier)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        expect(false, "creates isolated storage test defaults")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        try body(HistoryStore(url: url), url, defaults)
    } catch {
        expect(false, "storage fixture operation succeeds: \(error.localizedDescription)")
    }
}

private func withStorageDatabase<Value>(_ url: URL, _ operation: (OpaquePointer) throws -> Value) throws -> Value {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
        if let db { sqlite3_close(db) }
        throw NSError(domain: "StorageTests", code: 1)
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 1_000)
    return try operation(db)
}

private func storageSQL(_ url: URL, _ sql: String) throws {
    try withStorageDatabase(url) { db in
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "StorageTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }
}

private func storageScalar(_ url: URL, _ sql: String) throws -> String {
    try withStorageDatabase(url) { db in
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StorageTests", code: 3)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            throw NSError(domain: "StorageTests", code: 4)
        }
        return String(cString: value)
    }
}

func testHistoryStoreMigrationAndIndexTransactions() {
    withStorageFixture { store, url, _ in
        try storageSQL(url, """
        CREATE TABLE history_entries (
            id TEXT PRIMARY KEY NOT NULL, date REAL NOT NULL, actionName TEXT NOT NULL,
            source TEXT NOT NULL, output TEXT NOT NULL, provider TEXT NOT NULL,
            model TEXT NOT NULL, isFavorite INTEGER NOT NULL, tagsJSON TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE history_fts USING fts5(id UNINDEXED, actionName, source, output, provider, model, tags);
        INSERT INTO history_entries VALUES ('legacy', 1, '总结', 'legacy source', 'old result', 'Test', 'model', 1, '["originaltag"]');
        """)
        let migrated = store.load(limit: 50)
        expect(migrated.count == 1 && migrated.first?.id == "legacy", "schema migration preserves legacy history")
        expect(migrated.first?.isFavorite == true && migrated.first?.tags == ["originaltag"],
               "schema migration preserves favorite and tag metadata")
        expect(store.search("legacy", limit: 50).map(\.id) == ["legacy"], "migration repairs a missing legacy FTS entry")
        let schemaVersion = try storageScalar(url, "PRAGMA user_version;")
        expect(schemaVersion == "1", "history schema migration records its version")
        let queryPlan = try storageScalar(url, "SELECT name FROM sqlite_master WHERE type='index' AND name='history_entries_date';")
        expect(queryPlan == "history_entries_date", "history timeline has a persistent ordering index")

        try storageSQL(url, """
        CREATE TRIGGER fail_fixture_insert BEFORE INSERT ON history_entries
        WHEN new.id = 'record-999' BEGIN SELECT RAISE(ABORT, 'fixture stop'); END;
        """)
        expect(!store.replaceAll([storageEntry(2), storageEntry(999)], limit: 50), "batch replacement reports transaction failure")
        expect(store.load(limit: 50) == migrated, "failed batch replacement restores the original rows")
        expect(store.search("legacy", limit: 50).map(\.id) == ["legacy"], "failed batch replacement restores the original FTS index")
        try storageSQL(url, "DROP TRIGGER fail_fixture_insert;")

        guard var changed = migrated.first else { return }
        changed.source = "replacement body"
        changed.output = "changed output"
        changed.tags = ["revisedtag"]
        expect(store.upsert(changed, limit: 50), "updates an existing history row")
        expect(store.search("legacy", limit: 50).isEmpty, "upsert removes old tokens from the search index")
        expect(store.search("replacement revisedtag", limit: 50).map(\.id) == ["legacy"], "upsert indexes new text and tags")
        let searchIndex = try storageScalar(url, "SELECT group_concat(hex(block), ',') FROM history_fts_data;")
        changed.isFavorite.toggle()
        expect(store.upsert(changed, limit: 50), "favorite update persists")
        let updatedIndex = try storageScalar(url, "SELECT group_concat(hex(block), ',') FROM history_fts_data;")
        expect(updatedIndex == searchIndex,
               "favorite-only updates leave the full-text index untouched")
        try storageSQL(url, "INSERT INTO history_fts(history_fts, rank) VALUES ('integrity-check', 1);")

        var nul = storageEntry(3)
        nul.source = "before\u{0}after 中文 👩🏽‍💻"
        nul.output = "result\u{0}tail"
        expect(store.upsert(nul, limit: Int.max), "large limits do not overflow SQLite bindings")
        expect(store.load(limit: Int.max).first?.source == nul.source, "history text preserves embedded nulls and Unicode")
        expect(store.load(limit: 50).first?.output == nul.output, "history outputs preserve embedded nulls")
        expect(store.prune(limit: 1), "history retention pruning succeeds")
        expect(store.load(limit: 50).map(\.id) == [nul.id], "retention pruning keeps the newest row")
        expect(store.search("replacement", limit: 50).isEmpty, "retention pruning removes matching FTS rows")
        try storageSQL(url, "PRAGMA user_version=99;")
        expect(!HistoryStore(url: url).deleteAll(), "older app versions cannot modify a newer history schema")
        let retainedCount = try storageScalar(url, "SELECT count(*) FROM history_entries;")
        expect(retainedCount == "1", "unsupported schemas retain their original history rows")
    }
}

func testHistoryStoreConnectionRecoveryAndConcurrency() {
    withStorageFixture { store, url, _ in
        let first = storageEntry(1)
        expect(store.upsert(first, limit: 100), "initial history write succeeds")
        try FileManager.default.removeItem(at: url)
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        expect(store.load(limit: 100).isEmpty, "a reused connection notices that the database was deleted")
        expect(store.upsert(storageEntry(2), limit: 100), "the same store recreates a deleted database")
        expect(store.load(limit: 100).map(\.id) == ["record-2"], "recreated databases do not serve detached old rows")

        let blockedParent = url.deletingLastPathComponent().appendingPathComponent("blocked")
        try Data("fixture".utf8).write(to: blockedParent)
        let recoverable = HistoryStore(url: blockedParent.appendingPathComponent("history.sqlite"))
        if case .success = recoverable.loadResult(limit: 50) {
            expect(false, "read failure is distinguishable from an empty history")
        }
        expect(!recoverable.upsert(first, limit: 50), "blocked parent directory rejects writes")
        try FileManager.default.removeItem(at: blockedParent)
        expect(recoverable.upsert(first, limit: 50), "a failed connection retries after the filesystem is repaired")

        let permissionStore = HistoryStore(url: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        if case .success = permissionStore.loadResult(limit: 50) {
            expect(false, "permission-denied reads report failure")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        expect(permissionStore.load(limit: 50).map(\.id) == ["record-2"], "read access recovers after permissions are restored")

        let parallelURL = url.deletingLastPathComponent().appendingPathComponent("parallel.sqlite")
        let stores = [HistoryStore(url: parallelURL), HistoryStore(url: parallelURL)]
        let resultsLock = NSLock()
        var allWritesSucceeded = true
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            let succeeded = stores[index % stores.count].upsert(storageEntry(index), limit: 100)
            resultsLock.lock()
            allWritesSucceeded = allWritesSucceeded && succeeded
            resultsLock.unlock()
        }
        expect(allWritesSucceeded, "concurrent connections migrate and write without losing operations")
        expect(stores[0].load(limit: 100).count == 30, "all concurrent history records remain readable")
        expect(stores[1].search("fixture", limit: 100).count == 30, "concurrent history writes keep the FTS index consistent")
    }
}

func testSettingsPersistenceRecoveryAndValidation() {
    withStorageFixture { store, _, defaults in
        let entries = (0..<60).map { storageEntry($0) }
        expect(store.replaceAll(entries, limit: 100), "corrupt-settings fixture persists its history")
        let corruptData = Data("{unfinished settings".utf8)
        defaults.set(corruptData, forKey: AppSettings.storeKey)
        let loaded = AppSettings.load(defaults: defaults, historyStore: store)
        expect(defaults.data(forKey: AppSettings.storeKey) == corruptData, "loading corrupt settings preserves the original archive")
        expect(loaded.history.count == 60, "corrupt settings recovery loads existing history without the default 50-row cap")
        loaded.temperature = 0.5
        expect(loaded.save(), "recovered settings can be saved explicitly")
        expect(store.load(limit: 100).count == 60, "saving recovered settings does not prune history with an unknown prior retention limit")
    }
    withStorageFixture { _, url, defaults in
        let original = storageEntry(1)
        let settings = AppSettings()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        object["history"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([original]))
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        defaults.set(legacyData, forKey: AppSettings.storeKey)

        let blockedParent = url.deletingLastPathComponent().appendingPathComponent("migration")
        try Data("fixture".utf8).write(to: blockedParent)
        let store = HistoryStore(url: blockedParent.appendingPathComponent("history.sqlite"))
        let loaded = AppSettings.load(defaults: defaults, historyStore: store)
        expect(loaded.history == [original], "failed migration keeps legacy history in memory")
        loaded.temperature = 0.6
        expect(!loaded.save(), "settings save reports an unfinished history migration")
        expect(defaults.data(forKey: AppSettings.storeKey) == legacyData, "failed migration preserves the original settings archive")

        try FileManager.default.removeItem(at: blockedParent)
        expect(loaded.save(), "settings save retries the migration after storage recovers")
        expect(store.load(limit: 50) == [original], "retry persists all legacy history")
        let savedData = defaults.data(forKey: AppSettings.storeKey)!
        let savedObject = try JSONSerialization.jsonObject(with: savedData) as! [String: Any]
        expect(savedObject["history"] == nil, "successful migration removes the legacy history copy from settings")
        expect(savedObject["temperature"] as? Double == 0.6, "migration retry also saves pending configuration changes")

        try FileManager.default.removeItem(at: blockedParent)
        try Data("fixture".utf8).write(to: blockedParent)
        loaded.temperature = 0.7
        expect(loaded.save(), "unrelated settings changes do not access the history database")
        loaded.historyLimit = 0
        expect(!loaded.save(), "retention changes report an unavailable database")
        expect(loaded.history == [original], "failed retention changes do not hide records that could not be deleted")
        let retainedObject = try JSONSerialization.jsonObject(with: defaults.data(forKey: AppSettings.storeKey)!) as! [String: Any]
        expect(retainedObject["historyLimit"] as? Int == 50, "failed retention changes preserve the saved retention setting")

        try FileManager.default.removeItem(at: blockedParent)
        expect(loaded.save(), "pending retention changes retry successfully")
        expect(loaded.history.isEmpty && store.load(limit: 50).isEmpty, "successful zero retention clears both representations")
    }
}

func testHistorySearchDeduplicatesAndRejectsDeletedRows() {
    let newest = storageEntry(2)
    var duplicate = newest
    duplicate.output = "stale result"
    let deleted = storageEntry(3)
    let result = HistorySearch.filteredEntries(criteria: HistoryFilterCriteria(query: "synthetic"),
                                               memoryEntries: [newest, duplicate],
                                               limit: 50,
                                               searchStore: { _, _ in [deleted, duplicate] })
    expect(result == [newest], "history search safely deduplicates IDs and excludes rows missing from the live snapshot")
}

private final class StorageCloudStore: NSUbiquitousKeyValueStore {
    var succeeds = false
    var submitted: [Data] = []

    override func set(_ aData: Data?, forKey aKey: String) {
        if let aData { submitted.append(aData) }
    }

    override func synchronize() -> Bool { succeeds }
}

private final class FailingSecretFileManager: FileManager, @unchecked Sendable {
    var failTemporaryWrite = false

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if failTemporaryWrite && path.hasSuffix(".tmp") {
            throw NSError(domain: "StorageTests", code: 5)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}

func testLocalSecretStoreConcurrentWritesAndRecovery() {
    withStorageFixture { _, url, _ in
        let directory = url.deletingLastPathComponent().appendingPathComponent("Secrets", isDirectory: true)
        let stores = [LocalSecretStore.Store(directoryURL: directory), LocalSecretStore.Store(directoryURL: directory)]
        let resultLock = NSLock()
        var allWritesSucceeded = true
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            let written = stores[index % stores.count].setAPIKey("synthetic-value-\(index)", for: "provider-\(index)")
            resultLock.lock()
            allWritesSucceeded = allWritesSucceeded && written
            resultLock.unlock()
        }
        expect(allWritesSucceeded, "concurrent secret writes create one usable master key")
        for index in 0..<30 {
            expect(stores[0].apiKey(for: "provider-\(index)") == "synthetic-value-\(index)",
                   "concurrent secret writes retain every encrypted record")
        }

        let keyURL = directory.appendingPathComponent("snapai-secrets.key")
        let secretsURL = directory.appendingPathComponent("provider-secrets.json")
        let originalKey = try Data(contentsOf: keyURL)
        let originalEnvelope = try Data(contentsOf: secretsURL)
        let failingManager = FailingSecretFileManager()
        failingManager.failTemporaryWrite = true
        let failingStore = LocalSecretStore.Store(directoryURL: directory, fileManager: failingManager)
        expect(!failingStore.setAPIKey("unsaved-value", for: "provider-0"), "failed secret replacement reports failure")
        let retainedEnvelope = try Data(contentsOf: secretsURL)
        expect(retainedEnvelope == originalEnvelope, "failed replacement leaves the original encrypted file intact")
        expect(stores[0].apiKey(for: "provider-0") == "synthetic-value-0", "failed replacement keeps the previous key readable")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        expect(!leftovers.contains(where: { $0.hasSuffix(".tmp") }), "failed secret replacement removes temporary files")

        try FileManager.default.removeItem(at: keyURL)
        expect(!stores[1].setAPIKey("replacement-value", for: "provider-new"), "missing master keys cannot silently rekey existing ciphertext")
        expect(!FileManager.default.fileExists(atPath: keyURL.path), "missing-key recovery preserves the missing master-key state")
        let missingKeyEnvelope = try Data(contentsOf: secretsURL)
        expect(missingKeyEnvelope == originalEnvelope, "missing master keys leave existing ciphertext unchanged")
        try originalKey.write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        expect(stores[0].apiKey(for: "provider-29") == "synthetic-value-29", "restoring the original master key recovers existing records")
        expect(stores[1].setAPIKey("updated-value", for: "provider-0"), "secret writes resume after master-key recovery")
        expect(stores[0].apiKey(for: "provider-0") == "updated-value", "atomic replacement publishes the updated key")
        let updatedKey = try Data(contentsOf: keyURL)
        expect(updatedKey == originalKey, "ordinary key updates keep the existing master key")
        expect(stores[0].delete(providerID: "provider-0"), "secret deletion succeeds after concurrent writes")
        expect(stores[1].apiKey(for: "provider-29") == "synthetic-value-29", "secret deletion preserves other providers")
    }
}

func testICloudUploadPreservesChangesOnFailure() {
    withStorageFixture { store, _, defaults in
        let settings = AppSettings()
        settings.persistenceDefaults = defaults
        settings.persistenceHistoryStore = store
        settings.iCloudSyncEnabled = true
        let cloud = StorageCloudStore()
        let sync = iCloudSync(store: cloud)

        sync.upload(settings)
        expect(settings.iCloudHasLocalChanges, "failed iCloud synchronization preserves local pending changes")
        expect(settings.iCloudLastSyncStatus.contains("暂不可用"), "failed iCloud synchronization reports an actionable status")
        let revision = settings.iCloudRevision
        cloud.succeeds = true
        sync.upload(settings)
        expect(!settings.iCloudHasLocalChanges && settings.iCloudRevision == revision + 1, "successful submission records the new revision")
        expect(settings.iCloudLastSyncStatus.contains("已提交同步"), "successful submission does not claim unconfirmed remote delivery")
        sync.startListening(into: settings, onApplied: {})
        NotificationCenter.default.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                        object: cloud,
                                        userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreQuotaViolationChange])
        expect(settings.iCloudHasLocalChanges && settings.iCloudLastSyncStatus.contains("容量"),
               "asynchronous iCloud quota errors restore the pending local-change state")

        let submissions = cloud.submitted.count
        settings.contextProfiles = (0..<24).map { index in
            ContextProfile(name: "fixture-\(index)", content: String(repeating: "字", count: 40_000))
        }
        sync.upload(settings)
        expect(cloud.submitted.count == submissions, "oversized iCloud payloads are rejected before submission")
        expect(settings.iCloudHasLocalChanges && settings.iCloudLastSyncStatus.contains("容量"), "oversized configuration remains local and pending")

        settings.iCloudRevision = Int.max
        sync.upload(settings)
        expect(cloud.submitted.count == submissions, "revision overflow cannot submit a corrupt payload")
        expect(settings.iCloudHasLocalChanges, "revision overflow preserves pending local changes")

        settings.iCloudRevision = 1
        settings.contextProfiles = ContextProfile.defaults()
        sync.startListening(into: settings, onApplied: {})
        let deadline = Date().addingTimeInterval(1.5)
        while cloud.submitted.count == submissions && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
        expect(cloud.submitted.count == submissions + 1 && !settings.iCloudHasLocalChanges,
               "starting synchronization resumes local changes left pending by a previous app run")
    }
}

func testStorageRuntimeSyntheticBenchmark() {
    guard ProcessInfo.processInfo.environment["SNAPAI_STORAGE_BENCHMARK"] == "1" else { return }
    withStorageFixture { store, _, _ in
        let source = String(String(repeating: "synthetic text benchmark storage. ", count: 80).prefix(2_000))
        let output = String(String(repeating: "stream output persistence schema. ", count: 80).prefix(2_000))
        let entries = (0..<500).map { index in
            var entry = storageEntry(index, bodyLength: 0)
            entry.source = source
            entry.output = output
            return entry
        }
        let clock = ContinuousClock()
        let populate = clock.measure { expect(store.replaceAll(entries, limit: 500), "benchmark population succeeds") }
        let reads = clock.measure {
            for _ in 0..<30 { expect(store.load(limit: 500).count == 500, "benchmark reads all rows") }
        }
        let favorites = clock.measure {
            for index in 0..<50 {
                var updated = entries[index]
                updated.isFavorite = true
                expect(store.upsert(updated, limit: 500), "benchmark favorite update succeeds")
            }
        }
        print("Synthetic history benchmark: 500 rows / 2 KB per body; populate=\(populate), 30 reads=\(reads), 50 favorites=\(favorites)")
    }
}
