import Foundation

protocol SongCardDataProvider: AnyObject {
    func onCurrentSongChanged(_ song: SongCardData)
    func onQueueUpdated(_ songs: [SongCardData])
}

class SongCardManager: ObservableObject {
    @Published var queue: [SongCardData] = []
    @Published var currentIndex: Int = -1

    weak var delegate: SongCardDataProvider?

    var currentSong: SongCardData? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var nextSong: SongCardData? {
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count else { return nil }
        return queue[nextIndex]
    }

    var thirdSong: SongCardData? {
        let thirdIndex = currentIndex + 2
        guard thirdIndex < queue.count else { return nil }
        return queue[thirdIndex]
    }

    func addSong(_ song: SongCardData) {
        queue.append(song)
        delegate?.onQueueUpdated(queue)

        if currentIndex < 0 {
            currentIndex = 0
            delegate?.onCurrentSongChanged(song)
        }
    }

    func switchToNext() {
        guard currentIndex + 1 < queue.count else { return }
        currentIndex += 1
        delegate?.onCurrentSongChanged(queue[currentIndex])
    }

    func updateQueue(_ songs: [SongCardData]) {
        queue = songs
        currentIndex = songs.isEmpty ? -1 : 0
        delegate?.onQueueUpdated(queue)
        if let first = songs.first {
            delegate?.onCurrentSongChanged(first)
        }
    }

    func removeSong(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        queue.remove(at: index)
        delegate?.onQueueUpdated(queue)

        if queue.isEmpty {
            currentIndex = -1
        } else if index <= currentIndex {
            currentIndex = max(0, currentIndex - 1)
            delegate?.onCurrentSongChanged(currentSong!)
        }
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = -1
        delegate?.onQueueUpdated([])
    }
}
