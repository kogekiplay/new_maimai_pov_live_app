import XCTest
@testable import MaimaiPOV

final class SongCardManagerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SongCardManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testForceSaveClearsPersistedSnapshotAfterLastSongIsRemoved() throws {
        let persistenceManager = QueuePersistenceManager(snapshotDirectory: temporaryDirectory)
        let manager = SongCardManager(persistenceManager: persistenceManager)
        manager.addSong(Self.song(named: "Only Song"))
        manager.forceSave()
        XCTAssertNotNil(persistenceManager.load())

        manager.removeSong(at: 0)
        manager.forceSave()

        XCTAssertNil(persistenceManager.load())
    }

    func testClearQueueUsesInjectedPersistenceManager() throws {
        let persistenceManager = QueuePersistenceManager(snapshotDirectory: temporaryDirectory)
        let manager = SongCardManager(persistenceManager: persistenceManager)
        manager.addSong(Self.song(named: "Queued Song"))
        manager.forceSave()
        XCTAssertNotNil(persistenceManager.load())

        manager.clearQueue()

        XCTAssertNil(persistenceManager.load())
    }

    func testRestoreFromSnapshotNormalizesCurrentIndexBelowQueueStart() {
        let manager = SongCardManager(persistenceManager: QueuePersistenceManager(snapshotDirectory: temporaryDirectory))
        let snapshot = QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 10),
            queue: [
                Self.song(named: "First Song", id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!),
                Self.song(named: "Second Song", id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!)
            ],
            currentIndex: -2,
            userGiftPool: [:]
        )

        manager.restoreFromSnapshot(snapshot)

        XCTAssertEqual(manager.currentIndex, 0)
        XCTAssertEqual(manager.currentSong?.songName, "First Song")
    }

    func testRestoreFromSnapshotNormalizesCurrentIndexPastQueueEnd() {
        let manager = SongCardManager(persistenceManager: QueuePersistenceManager(snapshotDirectory: temporaryDirectory))
        let snapshot = QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 10),
            queue: [
                Self.song(named: "First Song", id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!),
                Self.song(named: "Second Song", id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!)
            ],
            currentIndex: 10,
            userGiftPool: [:]
        )

        manager.restoreFromSnapshot(snapshot)

        XCTAssertEqual(manager.currentIndex, 1)
        XCTAssertEqual(manager.currentSong?.songName, "Second Song")
    }

    func testRestoreGiftValuesOnlyNormalizesCurrentIndexBeforeCarryingGifts() {
        let manager = SongCardManager(persistenceManager: QueuePersistenceManager(snapshotDirectory: temporaryDirectory))
        let snapshot = QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(timeIntervalSince1970: 10),
            queue: [
                Self.song(
                    named: "Current Song",
                    requesterName: "alice",
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
                    giftValue: 100
                ),
                Self.song(
                    named: "Waiting Song",
                    requesterName: "bob",
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
                    giftValue: 200
                )
            ],
            currentIndex: -2,
            userGiftPool: [:]
        )

        manager.restoreGiftValuesOnly(from: snapshot)

        XCTAssertNil(manager.userGiftPool["alice"])
        XCTAssertEqual(manager.userGiftPool["bob"], 200)
    }

    private static func song(
        named name: String,
        requesterName: String = "alice",
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        giftValue: Int = 0
    ) -> SongCardData {
        SongCardData(
            id: id,
            songName: name,
            artist: "Test Artist",
            requesterName: requesterName,
            giftValue: giftValue,
            addedAt: Date(timeIntervalSince1970: 1),
            lastOwnerActivityAt: Date(timeIntervalSince1970: 2)
        )
    }
}
