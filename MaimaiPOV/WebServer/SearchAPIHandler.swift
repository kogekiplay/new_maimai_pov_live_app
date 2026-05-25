import Foundation
import Swifter

class SearchAPIHandler {
    weak var pipeline: LivePipelineManager?

    private func coverURL(from musicId: Int) -> String {
        return "/api/cover/\(musicId)"
    }

    func search(request: HttpRequest) -> HttpResponse {
        guard let queryParam = request.queryParams.first(where: { $0.0 == "q" })?.1,
              !queryParam.isEmpty else {
            return .badRequest(.text("Missing query parameter 'q'"))
        }

        let query = queryParam.removingPercentEncoding ?? queryParam

        let sem = DispatchSemaphore(value: 0)
        var response: [String: Any] = [:]

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let pipeline = self.pipeline else {
                sem.signal()
                return
            }

            let db = pipeline.songDatabase
            let candidates = db.findCandidates(query: query)

            var results: [[String: Any]] = []
            for song in candidates.candidates {
                var difficulties: [[String: Any]] = []
                for note in song.notes where note.isEnable {
                    let diffName: String
                    if note.difficulty.isUtage {
                        diffName = "UTAGE"
                    } else if let num = note.difficulty.intVal {
                        diffName = db.difficultyDisplayName(
                            [0: "easy", 1: "advanced", 2: "expert", 3: "master", 4: "remaster"][num] ?? "master"
                        )
                    } else {
                        diffName = "UNKNOWN"
                    }

                    difficulties.append([
                        "name": diffName,
                        "level": note.level,
                        "levelValue": note.levelValue
                    ])
                }

                var item: [String: Any] = [
                    "musicId": song.id,
                    "title": song.title,
                    "difficulties": difficulties,
                    "coverURL": self.coverURL(from: song.id)
                ]
                if let artist = song.artist { item["artist"] = artist }
                if let ct = song.chartType { item["chartType"] = ct }
                if let bpm = song.bpm { item["bpm"] = bpm }

                results.append(item)
            }

            response = [
                "query": query,
                "results": results
            ]
            sem.signal()
        }

        sem.wait()
        return .ok(.json(response))
    }
}
