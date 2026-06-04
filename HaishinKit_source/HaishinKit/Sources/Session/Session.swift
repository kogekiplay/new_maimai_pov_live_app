import Foundation

public enum SessionMethod {
    case ingest
    case playback
}

/// A type that represents a foundation of streaming session.
///
/// Streaming with RTMPConneciton is difficult to use because it requires many idioms.
public protocol Session: Actor {
    /// The instance connected to server(true) or not(false).
    var isConnected: Bool { get async }

    /// The stream instance.
    var stream: any HKStream { get }

    /// Creates a new session with uri.
    init(uri: URL)

    /// Creates a connection to the server.
    func connect(_ method: SessionMethod) async throws

    /// Closes the connection from the server.
    func close() async throws
}
