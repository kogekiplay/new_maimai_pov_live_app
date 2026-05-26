import Foundation

protocol SongCardDataProvider: AnyObject {
    func onCurrentSongChanged(_ song: SongCardData)
    func onQueueUpdated(_ songs: [SongCardData])
}

class SongCardManager: ObservableObject {
    @Published var queue: [SongCardData] = []
    @Published var currentIndex: Int = -1

    weak var delegate: SongCardDataProvider?

    var userGiftPool: [String: Int] = [:]

    var lockedEndIndex: Int {
        guard currentIndex >= 0 else { return 0 }
        return min(currentIndex + 2, queue.count)
    }

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

    func addSongAtNext(_ song: SongCardData) {
        if currentIndex < 0 {
            queue.append(song)
            currentIndex = 0
            delegate?.onCurrentSongChanged(song)
        } else {
            var insertIndex = currentIndex + 1
            while insertIndex < queue.count && queue[insertIndex].isPriority {
                insertIndex += 1
            }
            queue.insert(song, at: insertIndex)
        }
        delegate?.onQueueUpdated(queue)
    }

    func switchToNext() {
        guard currentIndex >= 0, currentIndex + 1 < queue.count else { return }
        let skippedName = queue[currentIndex].requesterName
        currentIndex += 1
        if let name = skippedName {
            resetGiftPool(name: name)
        }
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
        let removedName = queue[index].requesterName
        queue.remove(at: index)
        if let name = removedName {
            resetGiftPool(name: name)
        }
        delegate?.onQueueUpdated(queue)

        if queue.isEmpty {
            currentIndex = -1
        } else if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
            delegate?.onCurrentSongChanged(currentSong!)
        } else if index == currentIndex {
            if currentIndex >= queue.count {
                queue.removeAll()
                currentIndex = -1
                delegate?.onQueueUpdated([])
            } else {
                delegate?.onCurrentSongChanged(currentSong!)
            }
        }
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = -1
        userGiftPool.removeAll()
        delegate?.onQueueUpdated([])
    }

    func findSongIndex(byName name: String) -> Int? {
        guard currentIndex >= 0 else { return nil }
        for i in currentIndex..<queue.count {
            if queue[i].requesterName == name {
                return i
            }
        }
        return nil
    }

    func hasSongInQueue(name: String) -> Bool {
        return findSongIndex(byName: name) != nil
    }

    func updateGiftValue(name: String, delta: Int) -> Bool {
        guard let index = findSongIndex(byName: name) else { return false }
        queue[index].giftValue = userGiftPool[name] ?? queue[index].giftValue + delta
        return true
    }

    func resetGiftPool(name: String) {
        userGiftPool.removeValue(forKey: name)
    }

    func reorderQueueByGiftValue() {
        let lockedEnd = lockedEndIndex
        guard currentIndex >= 0, lockedEnd < queue.count else { return }

        var sortable = Array(queue[lockedEnd...])
        sortable.sort { a, b in
            if a.giftValue != b.giftValue {
                return a.giftValue > b.giftValue
            }
            return a.addedAt < b.addedAt
        }

        queue.replaceSubrange(lockedEnd..., with: sortable)
        delegate?.onQueueUpdated(queue)
    }
}
