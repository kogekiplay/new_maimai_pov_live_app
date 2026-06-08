import XCTest
@testable import MaimaiPOV

final class QueuePersistenceManagerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueuePersistenceManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testLoadFallsBackToBackupWhenPrimarySnapshotIsCorrupt() throws {
        let manager = QueuePersistenceManager(snapshotDirectory: temporaryDirectory)
        let primaryURL = temporaryDirectory.appendingPathComponent("queue_snapshot.json")
        let backupURL = temporaryDirectory.appendingPathComponent("queue_snapshot.bak")
        try Data("not-json".utf8).write(to: primaryURL)

        let backupSnapshot = QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1_234),
            queue: [Self.song(named: "Backup Song")],
            currentIndex: 99,
            userGiftPool: ["alice": 1_000]
        )
        try JSONEncoder().encode(backupSnapshot).write(to: backupURL)

        let loaded = try XCTUnwrap(manager.load())

        XCTAssertEqual(loaded.queue.map(\.songName), ["Backup Song"])
        XCTAssertEqual(loaded.currentIndex, 0)
        XCTAssertEqual(loaded.userGiftPool, ["alice": 1_000])
    }

    func testSavingEmptySnapshotRemovesExistingPersistedFiles() throws {
        let manager = QueuePersistenceManager(snapshotDirectory: temporaryDirectory)
        manager.save(snapshot: QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1),
            queue: [Self.song(named: "Old Song")],
            currentIndex: 0,
            userGiftPool: [:]
        ))
        try Data("leftover".utf8).write(to: temporaryDirectory.appendingPathComponent("queue_snapshot.tmp"))

        manager.save(snapshot: QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 2),
            queue: [],
            currentIndex: -1,
            userGiftPool: [:]
        ))

        XCTAssertNil(manager.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("queue_snapshot.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("queue_snapshot.bak").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("queue_snapshot.tmp").path))
    }

    func testClearSnapshotRemovesSnapshotBackupAndTemporaryFiles() throws {
        let manager = QueuePersistenceManager(snapshotDirectory: temporaryDirectory)
        for fileName in ["queue_snapshot.json", "queue_snapshot.bak", "queue_snapshot.tmp"] {
            try Data(fileName.utf8).write(to: temporaryDirectory.appendingPathComponent(fileName))
        }

        manager.clearSnapshot()

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("queue_snapshot.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("queue_snapshot.bak").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("queue_snapshot.tmp").path))
    }

    func testLoadRejectsSnapshotFromFutureVersion() throws {
        let manager = QueuePersistenceManager(snapshotDirectory: temporaryDirectory)
        let futureSnapshot = QueueSnapshot(
            version: QueueSnapshot.currentVersion + 1,
            savedAt: Date(timeIntervalSince1970: 3),
            queue: [Self.song(named: "Future Song")],
            currentIndex: 0,
            userGiftPool: [:]
        )
        try JSONEncoder().encode(futureSnapshot).write(to: temporaryDirectory.appendingPathComponent("queue_snapshot.json"))

        XCTAssertNil(manager.load())
    }

    private static func song(named name: String) -> SongCardData {
        SongCardData(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            songName: name,
            artist: "Test Artist",
            addedAt: Date(timeIntervalSince1970: 1),
            lastOwnerActivityAt: Date(timeIntervalSince1970: 2)
        )
    }
}
