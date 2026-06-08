import XCTest
@testable import MaimaiPOV

final class SongDatabaseTests: XCTestCase {
    func testFindNoteUsesTrimmedDisplayDifficultyInput() {
        let database = SongDatabase()
        let song = Self.song(notes: [
            Self.note(.intValue(0), level: "1", levelValue: 1),
            Self.note(.intValue(1), level: "2", levelValue: 2),
            Self.note(.intValue(2), level: "3", levelValue: 3),
            Self.note(.intValue(3), level: "4", levelValue: 4)
        ])

        let result = database.findNote(
            song: song,
            targetDiffNum: database.resolveDiffInput(" ADVANCED\n")
        )

        XCTAssertEqual(result?.diffName, "advanced")
        XCTAssertEqual(result?.noteIndex, 1)
    }

    func testPickByChartTypeUsesTrimmedUtageDifficultyPreference() {
        let database = SongDatabase()
        let standard = Self.song(id: 1, chartType: "standard")
        let utage = Self.song(
            id: 100001,
            chartType: "utage",
            notes: [Self.note(.stringValue("utage"), level: "宴", levelValue: 13)]
        )

        let picked = database.pickByChartType(
            candidates: [standard, utage],
            chartTypePreference: nil,
            diffInput: " UTAGE "
        )

        XCTAssertEqual(picked?.chartType, "utage")
    }

    private static func song(
        id: Int = 100,
        title: String = "Test Song",
        chartType: String = "dx",
        notes: [SongNote] = [note(.intValue(3), level: "13", levelValue: 13)]
    ) -> Song {
        Song(
            id: id,
            title: title,
            titleSort: nil,
            artist: nil,
            genre: nil,
            genreId: nil,
            bpm: nil,
            chartType: chartType,
            addVersion: nil,
            addVersionId: nil,
            releaseTag: nil,
            versionCode: nil,
            longMusic: nil,
            utageKanji: nil,
            utagePlayStyle: nil,
            notes: notes
        )
    }

    private static func note(
        _ difficulty: DifficultyValue,
        level: String,
        levelValue: Double
    ) -> SongNote {
        SongNote(
            difficulty: difficulty,
            level: level,
            levelValue: levelValue,
            noteDesigner: nil,
            maxNotes: nil,
            isEnable: true
        )
    }
}
