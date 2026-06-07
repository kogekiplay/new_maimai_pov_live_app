import Foundation

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.withLock {
            value = newValue
        }
    }

    func get() -> Value {
        lock.withLock {
            value
        }
    }
}
