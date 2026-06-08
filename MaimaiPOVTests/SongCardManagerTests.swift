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

    private static func song(named name: String) -> SongCardData {
        SongCardData(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            songName: name,
            artist: "Test Artist",
            requesterName: "alice",
            addedAt: Date(timeIntervalSince1970: 1),
            lastOwnerActivityAt: Date(timeIntervalSince1970: 2)
        )
    }
}
