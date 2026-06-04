import Foundation

actor RTMPSession: Session {
    var isConnected: Bool {
        get async {
            await connection.connected
        }
    }

    var stream: any HKStream {
        _stream
    }

    private let uri: RTMPURL
    private lazy var connection = RTMPConnection()
    private lazy var _stream: RTMPStream = {
        RTMPStream(connection: connection)
    }()

    init(uri: URL) {
        self.uri = RTMPURL(url: uri)
    }

    func connect(_ method: SessionMethod) async throws {
        let response = try await connection.connect(uri.command)
        switch method {
        case .ingest:
            _ = try await _stream.publish(uri.streamName)
        case .playback:
            _ = try await _stream.play(uri.streamName)
        }
    }

    func close() async throws {
        try await connection.close()
    }
}
