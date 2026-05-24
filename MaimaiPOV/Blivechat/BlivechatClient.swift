import Foundation
import Combine

class BlivechatClient: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected

    var onDanmaku: ((DanmakuMessage) -> Void)?
    var onGift: ((GiftMessage) -> Void)?
    var onSuperChat: ((SuperChatMessage) -> Void)?
    var onMember: ((MemberMessage) -> Void)?
    var onError: ((BlivechatErrorMessage) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectDelay: Double = 5.0
    private let maxReconnectDelay: Double = 30.0

    private var server: BlivechatServer = .cn
    private var roomKeyType: RoomKeyType = .authCode
    private var roomKeyValue: String = ""
    private var isIntentionalDisconnect = false

    func connect(server: BlivechatServer, roomKeyType: RoomKeyType, roomKeyValue: String) {
        disconnect()

        self.server = server
        self.roomKeyType = roomKeyType
        self.roomKeyValue = roomKeyValue
        self.isIntentionalDisconnect = false
        self.reconnectDelay = 5.0

        performConnect()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        cleanup()
        connectionState = .disconnected
    }

    private func performConnect() {
        cleanup()
        connectionState = .connecting

        let url = server.websocketURL
        var request = URLRequest(url: url)
        request.setValue(server.originURL, forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sendJoinRoom()
            self?.startHeartbeat()
            self?.connectionState = .connected
            self?.reconnectDelay = 5.0
        }
    }

    private func sendJoinRoom() {
        let joinData: [String: Any] = [
            "cmd": BlivechatCommand.joinRoom.rawValue,
            "data": [
                "roomKey": [
                    "type": roomKeyType.rawValue,
                    "value": roomKeyValue
                ],
                "config": [
                    "autoTranslate": false
                ]
            ]
        ]

        sendJSON(joinData)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.sendJSON(["cmd": BlivechatCommand.heartbeat.rawValue])
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }

        let message = URLSessionWebSocketTask.Message.string(string)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.handleConnectionError(error)
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.handleConnectionError(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            processTextMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                processTextMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func processTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmdValue = json["cmd"] as? Int,
              let cmd = BlivechatCommand(rawValue: cmdValue) else {
            return
        }

        let payload = json["data"]

        switch cmd {
        case .heartbeat:
            break

        case .addText:
            if let array = payload as? [Any],
               let danmaku = DanmakuMessage(fromArray: array) {
                DispatchQueue.main.async {
                    self.onDanmaku?(danmaku)
                }
            }

        case .addGift:
            if let dict = payload as? [String: Any],
               let gift = GiftMessage(fromDict: dict) {
                DispatchQueue.main.async {
                    self.onGift?(gift)
                }
            }

        case .addMember:
            if let dict = payload as? [String: Any],
               let member = MemberMessage(fromDict: dict) {
                DispatchQueue.main.async {
                    self.onMember?(member)
                }
            }

        case .addSuperChat:
            if let dict = payload as? [String: Any],
               let sc = SuperChatMessage(fromDict: dict) {
                DispatchQueue.main.async {
                    self.onSuperChat?(sc)
                }
            }

        case .delSuperChat:
            break

        case .updateTranslation:
            break

        case .fatalError:
            if let dict = payload as? [String: Any],
               let error = BlivechatErrorMessage(fromDict: dict) {
                DispatchQueue.main.async {
                    self.connectionState = .error(error.message)
                    self.onError?(error)
                }
            }
            isIntentionalDisconnect = true

        case .joinRoom:
            break
        }
    }

    private func handleConnectionError(_ error: Error) {
        guard !isIntentionalDisconnect else { return }

        connectionState = .error(error.localizedDescription)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.performConnect()
        }

        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
    }

    private func cleanup() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    deinit {
        cleanup()
    }
}
