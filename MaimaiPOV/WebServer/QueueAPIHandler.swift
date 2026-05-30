import Foundation
import Swifter

class QueueAPIHandler {
    weak var pipeline: LivePipelineManager?

    private func coverURL(from musicId: Int?) -> String? {
        guard let musicId = musicId else { return nil }
        return "/api/cover/\(musicId)"
    }

    private func buildQueueResponse() -> [String: Any] {
        guard let pipeline = pipeline else { return [:] }
        let manager = pipeline.songCardManager
        let ci = max(0, manager.currentIndex)
        var queueItems: [[String: Any]] = []

        for i in ci..<manager.queue.count {
            let song = manager.queue[i]
            var item: [String: Any] = [
                "index": i - ci,
                "songName": song.songName,
                "artist": song.artist,
                "isPriority": song.isPriority
            ]
            if let diff = song.difficulty { item["difficulty"] = diff }
            if let level = song.level { item["level"] = level }
            if let ct = song.chartType { item["chartType"] = ct }
            if let req = song.requester { item["requester"] = req }
            if let rn = song.requesterName { item["requesterName"] = rn }
            item["giftValue"] = song.giftValue
            if let mid = song.musicId {
                item["musicId"] = mid
                item["coverURL"] = coverURL(from: mid)
            }
            if let bpm = song.bpm { item["bpm"] = bpm }
            queueItems.append(item)
        }

        let remaining = max(0, manager.queue.count - ci - 1)

        return [
            "currentIndex": 0,
            "remaining": remaining,
            "queue": queueItems
        ]
    }

    private func realIndex(_ displayIndex: Int) -> Int {
        guard let pipeline = pipeline else { return displayIndex }
        let ci = max(0, pipeline.songCardManager.currentIndex)
        return ci + displayIndex
    }

    func getQueue() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)
        var response: [String: Any] = [:]

        DispatchQueue.main.async { [weak self] in
            response = self?.buildQueueResponse() ?? [:]
            sem.signal()
        }

        sem.wait()
        return .ok(.json(response))
    }

    func skip() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async { [weak self] in
            self?.pipeline?.triggerSongCardSwitch()
            sem.signal()
        }

        sem.wait()
        return getQueue()
    }

    func clear() -> HttpResponse {
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async { [weak self] in
            self?.pipeline?.clearSongQueue()
            sem.signal()
        }

        sem.wait()
        return getQueue()
    }

    func remove(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let displayIndex = body["index"] as? Int else {
            return .badRequest(.text("Missing or invalid 'index'"))
        }

        let preserveGift = body["preserveGift"] as? Bool ?? false

        let sem = DispatchSemaphore(value: 0)
        var success = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            let index = self.realIndex(displayIndex)
            let manager = pipeline.songCardManager
            guard index >= 0, index < manager.queue.count else {
                sem.signal()
                return
            }

            let ci = manager.currentIndex
            let wasInLockedArea = index <= ci + 1

            manager.removeSong(at: index, preserveGift: preserveGift)

            if manager.queue.isEmpty {
                pipeline.leftPanelCompositor?.clearAll()
                pipeline.rightPanelCompositor?.clearAll()
            } else if wasInLockedArea {
                pipeline.refreshRightPanel()
            }

            success = true
            sem.signal()
        }

        sem.wait()
        return success ? getQueue() : .badRequest(.text("Invalid index"))
    }

    func addForUser(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let musicId = body["musicId"] as? Int else {
            return .badRequest(.text("Missing or invalid 'musicId'"))
        }

        let difficulty = body["difficulty"] as? String
        let chartType = body["chartType"] as? String
        let username = body["username"] as? String ?? "LAN"

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
            if chartTypePreference == "std" { chartTypePreference = "standard" }

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

            let giftVal = pipeline.songCardManager.userGiftPool[username] ?? 0

            let cardData = SongCardData(
                songName: song.title,
                artist: song.artist ?? "",
                difficulty: diffName,
                level: levelStr,
                requester: username,
                requesterName: username,
                musicId: song.id,
                chartType: song.chartType,
                isPriority: false,
                bpm: song.bpm,
                giftValue: giftVal
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
            if chartTypePreference == "std" { chartTypePreference = "standard" }

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
                requesterName: "LAN",
                musicId: song.id,
                chartType: song.chartType,
                isPriority: false,
                bpm: song.bpm
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

    func cancelSongForUser(request: HttpRequest) -> HttpResponse {
        guard let body = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
              let username = body["username"] as? String else {
            return .badRequest(.text("Missing or invalid 'username'"))
        }

        let sem = DispatchSemaphore(value: 0)
        var success = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            let manager = pipeline.songCardManager

            if let index = manager.findSongIndex(byName: username) {
                let wasInLockedArea = index <= manager.currentIndex + 1
                manager.removeSong(at: index, preserveGift: true)

                if manager.queue.isEmpty {
                    pipeline.leftPanelCompositor?.clearAll()
                    pipeline.rightPanelCompositor?.clearAll()
                } else if wasInLockedArea {
                    pipeline.refreshRightPanel()
                }
                success = true
            }

            sem.signal()
        }

        sem.wait()
        return success ? getQueue() : .badRequest(.text("User has no song in queue"))
    }

    func getUserInfo(request: HttpRequest) -> HttpResponse {
        guard let username = request.queryParams.first(where: { $0.0 == "username" })?.1,
              !username.isEmpty else {
            return .badRequest(.text("Missing 'username' parameter"))
        }

        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = [:]

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }
            let manager = pipeline.songCardManager

            var info: [String: Any] = [
                "username": username,
                "giftValue": manager.userGiftPool[username] ?? 0
            ]

            if let index = manager.findSongIndex(byName: username) {
                let song = manager.queue[index]
                var songInfo: [String: Any] = [
                    "songName": song.songName,
                    "artist": song.artist,
                    "giftValue": song.giftValue
                ]
                if let diff = song.difficulty { songInfo["difficulty"] = diff }
                if let level = song.level { songInfo["level"] = level }
                if let ct = song.chartType { songInfo["chartType"] = ct }
                if let mid = song.musicId {
                    songInfo["musicId"] = mid
                    songInfo["coverURL"] = self.coverURL(from: mid)
                }
                info["currentSong"] = songInfo
            } else {
                info["currentSong"] = nil
            }

            let history = DanmakuBufferManager.shared.getHistoryForUser(username: username, limit: 20)
            var danmakuList: [[String: Any]] = []
            for entry in history {
                var item: [String: Any] = [
                    "content": entry.content,
                    "timestamp": entry.timestamp,
                    "type": entry.type.rawValue
                ]
                if entry.isSongRequest {
                    item["isSongRequest"] = true
                    if let status = entry.songRequestStatus {
                        item["songRequestStatus"] = status
                    }
                }
                danmakuList.append(item)
            }
            info["recentDanmaku"] = danmakuList

            result = info
            sem.signal()
        }

        sem.wait()
        return .ok(.json(result))
    }
}
