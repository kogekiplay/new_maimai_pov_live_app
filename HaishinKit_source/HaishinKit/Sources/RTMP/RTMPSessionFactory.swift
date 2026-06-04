import Foundation

public struct RTMPSessionFactory: SessionFactory {
    public let supportedProtocols: Set<String> = ["rtmp", "rtmps"]

    public init() {
    }

    public func make(uri: URL) -> any Session {
        return RTMPSession(uri: uri)
    }
}
