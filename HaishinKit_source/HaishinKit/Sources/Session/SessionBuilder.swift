import Foundation

public struct SessionBuilder: Sendable {
    let manager: SessionBuilderFactory
    let uri: URL

    public func build() async throws -> (any Session)? {
        return try await manager.build(uri)
    }
}
