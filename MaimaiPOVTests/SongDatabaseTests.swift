import XCTest
@testable import MaimaiPOV

final class SongDatabaseTests: XCTestCase {
    func testDifficultyValueRecognizesTrimmedUtageString() {
        XCTAssertTrue(DifficultyValue.stringValue(" UTAGE\n").isUtage)
    }

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

    func testPickByChartTypeNormalizesStandardPreference() {
        let database = SongDatabase()
        let dx = Self.song(id: 100, chartType: "dx")
        let standard = Self.song(id: 101, chartType: "standard")

        let picked = database.pickByChartType(
            candidates: [dx, standard],
            chartTypePreference: " STD\n",
            diffInput: nil
        )

        XCTAssertEqual(picked?.chartType, "standard")
    }

    func testFindCandidatesTrimsNewlinesAroundQuery() {
        let database = SongDatabase()
        let song = Self.song(id: 100, title: "Test Song")
        database.install(Self.snapshot(songs: [song]))

        let result = database.findCandidates(query: "\nTest Song\r\n")

        XCTAssertEqual(result.candidates.map(\.id), [100])
        XCTAssertEqual(result.matchKind, .title)
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

    private static func snapshot(songs: [Song]) -> SongDatabase.BundleLoadResult {
        var byId: [Int: Song] = [:]
        var byTitle: [String: [Song]] = [:]

        for song in songs {
            byId[song.id] = song
            byTitle[song.title.lowercased(), default: []].append(song)
        }

        return .success(SongDatabase.BundleSnapshot(
            songList: songs,
            aliasMap: [:],
            byId: byId,
            byTitle: byTitle,
            byAlias: [:],
            summary: SongDatabase.LoadSummary(
                loadedCount: songs.count,
                standardCount: songs.filter { $0.chartType == "standard" }.count,
                dxCount: songs.filter { $0.chartType == "dx" }.count,
                utageCount: songs.filter { $0.chartType == "utage" }.count,
                titleIndexCount: byTitle.count,
                aliasIndexCount: 0
            )
        ))
    }
}
