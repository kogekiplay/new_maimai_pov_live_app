import Foundation
import Swifter

class QueueAPIHandler {
    weak var pipeline: LivePipelineManager?

    func getQueue() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        var resultJson: Data?

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            let manager = pipeline.songCardManager
            var queueItems: [[String: Any]] = []

            for (i, song) in manager.queue.enumerated() {
                var item: [String: Any] = [
                    "index": i,
                    "songName": song.songName,
                    "artist": song.artist,
                    "isPriority": song.isPriority
                ]
                if let diff = song.difficulty { item["difficulty"] = diff }
                if let level = song.level { item["level"] = level }
                if let ct = song.chartType { item["chartType"] = ct }
                if let req = song.requester { item["requester"] = req }
                if let mid = song.musicId { item["musicId"] = mid }
                queueItems.append(item)
            }

            let response: [String: Any] = [
                "currentIndex": manager.currentIndex,
                "queue": queueItems
            ]
            resultJson = try? JSONSerialization.data(withJSONObject: response)
            sem.signal()
        }

        sem.wait()
        guard let data = resultJson else {
            return .internalServerError
        }
        return .raw(200, "OK", [("Content-Type", "application/json; charset=utf-8")], data)
    }

    func skip() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        var success = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            pipeline.triggerSongCardSwitch()
            success = true
            sem.signal()
        }

        sem.wait()
        return success ? getQueue() : .internalServerError
    }

    func clear() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            pipeline.clearSongQueue()
            sem.signal()
        }

        sem.wait()
        return getQueue()
    }

    func remove(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let index = body["index"] as? Int else {
            return .badRequest(.text("Missing or invalid 'index'"))
        }

        let sem = DispatchSemaphore(value: 0)
        var success = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            let manager = pipeline.songCardManager
            guard index >= 0, index < manager.queue.count else {
                sem.signal()
                return
            }

            let ci = manager.currentIndex
            let needsRefresh = index <= ci + 2

            manager.removeSong(at: index)

            if needsRefresh {
                pipeline.refreshDisplayedCardsIfNeeded()
            }

            success = true
            sem.signal()
        }

        sem.wait()
        return success ? getQueue() : .badRequest(.text("Invalid index"))
    }

    func move(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let index = body["index"] as? Int,
              let direction = body["direction"] as? String else {
            return .badRequest(.text("Missing or invalid 'index' or 'direction'"))
        }

        guard direction == "up" || direction == "down" else {
            return .badRequest(.text("Direction must be 'up' or 'down'"))
        }

        let sem = DispatchSemaphore(value: 0)
        var success = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            let manager = pipeline.songCardManager
            let ci = manager.currentIndex

            let targetIndex = direction == "up" ? index - 1 : index + 1
            guard index >= 0, index < manager.queue.count,
                  targetIndex >= 0, targetIndex < manager.queue.count else {
                sem.signal()
                return
            }

            let needsRefresh = index <= ci + 2 || targetIndex <= ci + 2

            manager.moveSong(at: index, direction: direction)

            if needsRefresh {
                pipeline.refreshDisplayedCardsIfNeeded()
            }

            success = true
            sem.signal()
        }

        sem.wait()
        return success ? getQueue() : .badRequest(.text("Cannot move song"))
    }

    func add(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let musicId = body["musicId"] as? Int else {
            return .badRequest(.text("Missing or invalid 'musicId'"))
        }

        let difficulty = body["difficulty"] as? String
        let chartType = body["chartType"] as? String

        let sem = DispatchSemaphore(value: 0)
        var success = false
        var errorMsg: String?

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                errorMsg = "Pipeline not available"
                sem.signal()
                return
            }

            let db = pipeline.songDatabase
            let candidates = db.findCandidates(query: String(musicId))
            if candidates.candidates.isEmpty {
                errorMsg = "Song not found: \(musicId)"
                sem.signal()
                return
            }

            var chartTypePreference: String? = chartType
            if chartTypePreference == "dx" { chartTypePreference = "dx" }
            else if chartTypePreference == "standard" || chartTypePreference == "std" { chartTypePreference = "standard" }

            guard let song = db.pickByChartType(
                candidates: candidates.candidates,
                chartTypePreference: chartTypePreference,
                diffInput: difficulty
            ) else {
                errorMsg = "Cannot pick song from candidates"
                sem.signal()
                return
            }

            let targetDiffNum = db.resolveDiffInput(difficulty)
            guard let noteResult = db.findNote(song: song, targetDiffNum: targetDiffNum) else {
                errorMsg = "No available difficulty for \(song.title)"
                sem.signal()
                return
            }

            let diffName = db.difficultyDisplayName(noteResult.diffName)
            let levelStr = noteResult.levelValue.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(noteResult.levelValue))"
                : "\(noteResult.levelValue)"

            let cardData = SongCardData(
                songName: song.title,
                artist: song.artist ?? "",
                difficulty: diffName,
                level: levelStr,
                requester: "LAN",
                musicId: song.id,
                chartType: song.chartType,
                isPriority: false
            )

            pipeline.addSongToQueue(cardData)
            success = true
            sem.signal()
        }

        sem.wait()
        if success {
            return getQueue()
        } else {
            return .badRequest(.text(errorMsg ?? "Failed to add song"))
        }
    }
}
