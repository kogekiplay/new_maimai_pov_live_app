import Foundation

enum QueueChange {
    case added(index: Int)
    case removed(index: Int)
    case reordered
    case fullRefresh
}

protocol SongCardDataProvider: AnyObject {
    func onCurrentSongChanged(_ song: SongCardData?)
    func onQueueUpdated(_ songs: [SongCardData], change: QueueChange)
    func onSongRemoved(queueIndex: Int)
    func onGiftValueChanged(_ song: SongCardData, queueIndex: Int)
    func onSongsExpired(_ songs: [SongCardData])
}

final class SongCardManager: ObservableObject, @unchecked Sendable {
    @Published var queue: [SongCardData] = []
    @Published var currentIndex: Int = -1

    weak var delegate: SongCardDataProvider?

    var userGiftPool: [String: Int] = [:]

    private var saveTimer: Timer?
    private let saveDebounceInterval: TimeInterval = 1.0

    private var expirationTimer: Timer?
    private let expirationCheckInterval: TimeInterval = 30
    var expirationTimeout: TimeInterval = 15 * 60
    private let persistenceManager: QueuePersistenceManager

    init(persistenceManager: QueuePersistenceManager = .shared) {
        self.persistenceManager = persistenceManager
    }

    deinit {
        stopExpirationTimer()
        cancelPendingSave()
    }

    var lockedEndIndex: Int {
        guard currentIndex >= 0 else { return 0 }
        return min(currentIndex + 1, queue.count)
    }

    var currentSong: SongCardData? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var nextSong: SongCardData? {
        let nextIndex = currentIndex + 1
        guard nextIndex >= 0, nextIndex < queue.count else { return nil }
        return queue[nextIndex]
    }

    var thirdSong: SongCardData? {
        let thirdIndex = currentIndex + 2
        guard thirdIndex >= 0, thirdIndex < queue.count else { return nil }
        return queue[thirdIndex]
    }

    func addSong(_ song: SongCardData) {
        queue.append(song)
        delegate?.onQueueUpdated(queue, change: .added(index: queue.count - 1))

        if currentIndex < 0 || currentIndex >= queue.count {
            currentIndex = min(max(currentIndex, 0), queue.count - 1)
            delegate?.onCurrentSongChanged(currentSong)
        }
        scheduleSave()
    }

    func addSongAtNext(_ song: SongCardData) {
        if currentIndex < 0 {
            queue.append(song)
            currentIndex = 0
            delegate?.onCurrentSongChanged(song)
            delegate?.onQueueUpdated(queue, change: .added(index: 0))
        } else {
            var insertIndex = min(currentIndex + 1, queue.count)
            while insertIndex < queue.count && queue[insertIndex].isPriority {
                insertIndex += 1
            }
            queue.insert(song, at: insertIndex)
            delegate?.onQueueUpdated(queue, change: .added(index: insertIndex))
        }
        scheduleSave()
    }

    func switchToNext() {
        guard currentIndex >= 0, currentIndex + 1 < queue.count else { return }
        let skippedName = queue[currentIndex].requesterName
        currentIndex += 1
        if let name = skippedName {
            resetGiftPool(name: name)
        }
        delegate?.onCurrentSongChanged(queue[currentIndex])
        scheduleSave()
    }

    func updateQueue(_ songs: [SongCardData]) {
        queue = songs
        currentIndex = songs.isEmpty ? -1 : 0
        delegate?.onQueueUpdated(queue, change: .fullRefresh)
        if let first = songs.first {
            delegate?.onCurrentSongChanged(first)
        }
        scheduleSave()
    }

    func removeSong(at index: Int, preserveGift: Bool = false) {
        guard index >= 0, index < queue.count else { return }
        let removedName = queue[index].requesterName
        let wasInRightPanel = index >= currentIndex + 1
        queue.remove(at: index)
        if let name = removedName, !preserveGift {
            resetGiftPool(name: name)
        }

        if queue.isEmpty {
            currentIndex = -1
        } else if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        } else if index == currentIndex {
            if currentIndex >= queue.count {
                currentIndex = queue.count - 1
            }
        }
        if !queue.isEmpty {
            currentIndex = min(max(currentIndex, 0), queue.count - 1)
        }

        if wasInRightPanel {
            delegate?.onSongRemoved(queueIndex: index)
        }
        delegate?.onQueueUpdated(queue, change: .removed(index: index))

        if !queue.isEmpty {
            if index < currentIndex + 1 || index == currentIndex {
                if let song = currentSong {
                    delegate?.onCurrentSongChanged(song)
                }
            }
        }
        scheduleSave()
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = -1
        userGiftPool.removeAll()
        delegate?.onCurrentSongChanged(nil)
        delegate?.onQueueUpdated([], change: .fullRefresh)
        cancelPendingSave()
        persistenceManager.clearSnapshot()
    }

    func findSongIndex(byName name: String) -> Int? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
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
        delegate?.onGiftValueChanged(queue[index], queueIndex: index)
        scheduleSave()
        return true
    }

    func resetGiftPool(name: String) {
        userGiftPool.removeValue(forKey: name)
    }

    func updateOwnerActivity(forName name: String) {
        for i in 0..<queue.count {
            if queue[i].requesterName == name {
                queue[i].lastOwnerActivityAt = Date()
            }
        }
    }

    func checkAndRemoveExpiredSongs() -> [SongCardData] {
        let now = Date()
        var expired: [SongCardData] = []

        for i in stride(from: queue.count - 1, through: max(currentIndex + 1, 0), by: -1) {
            let song = queue[i]
            guard song.giftValue == 0 else { continue }
            if now.timeIntervalSince(song.lastOwnerActivityAt) > expirationTimeout {
                expired.append(song)
            }
        }

        for song in expired {
            if let index = queue.firstIndex(where: { $0.id == song.id }) {
                removeSong(at: index)
            }
        }

        return expired
    }

    func startExpirationTimer() {
        guard expirationTimer == nil else { return }
        expirationTimer = Timer.scheduledTimer(
            withTimeInterval: expirationCheckInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            let expired = self.checkAndRemoveExpiredSongs()
            if !expired.isEmpty {
                self.delegate?.onSongsExpired(expired)
            }
        }
    }

    func stopExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil
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
        delegate?.onQueueUpdated(queue, change: .reordered)
        scheduleSave()
    }

    func restoreFromSnapshot(_ snapshot: QueueSnapshot) {
        let snapshot = snapshot.normalized()
        queue = snapshot.queue
        currentIndex = snapshot.currentIndex
        userGiftPool = snapshot.userGiftPool
        delegate?.onQueueUpdated(queue, change: .fullRefresh)
        if let song = currentSong {
            delegate?.onCurrentSongChanged(song)
        }
    }

    func restoreGiftValuesOnly(from snapshot: QueueSnapshot) {
        let snapshot = snapshot.normalized()
        var carriedGifts: [String: Int] = [:]
        let startIndex = snapshot.currentIndex + 1
        guard startIndex < snapshot.queue.count else { return }
        for i in startIndex..<snapshot.queue.count {
            let song = snapshot.queue[i]
            guard let name = song.requesterName, song.giftValue > 0 else { continue }
            carriedGifts[name, default: 0] += song.giftValue
        }
        guard !carriedGifts.isEmpty else { return }
        userGiftPool.merge(carriedGifts) { $0 + $1 }
        delegate?.onQueueUpdated([], change: .fullRefresh)
        delegate?.onCurrentSongChanged(nil)
    }

    func restoreAllGiftValues(from snapshot: QueueSnapshot) {
        let snapshot = snapshot.normalized()
        var playedNames = Set<String>()
        if snapshot.currentIndex >= 0 {
            for i in 0...snapshot.currentIndex where i < snapshot.queue.count {
                if let name = snapshot.queue[i].requesterName {
                    playedNames.insert(name)
                }
            }
        }
        var carriedGifts: [String: Int] = [:]
        for (name, value) in snapshot.userGiftPool where value > 0 && !playedNames.contains(name) {
            carriedGifts[name] = value
        }
        guard !carriedGifts.isEmpty else { return }
        userGiftPool.merge(carriedGifts) { $0 + $1 }
        delegate?.onQueueUpdated([], change: .fullRefresh)
        delegate?.onCurrentSongChanged(nil)
    }

    func forceSave() {
        cancelPendingSave()
        performSave()
    }

    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] timer in
            guard let self,
                  let saveTimer = self.saveTimer,
                  saveTimer === timer else { return }
            self.saveTimer = nil
            self.performSave()
        }
    }

    private func cancelPendingSave() {
        saveTimer?.invalidate()
        saveTimer = nil
    }

    private func performSave() {
        let snapshot = QueueSnapshot(
            version: QueueSnapshot.currentVersion,
            savedAt: Date(),
            queue: queue,
            currentIndex: currentIndex,
            userGiftPool: userGiftPool
        )
        persistenceManager.save(snapshot: snapshot)
    }
}
