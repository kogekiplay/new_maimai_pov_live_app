import Foundation
import Combine
import UIKit

final class BlivechatClient: ObservableObject, @unchecked Sendable {
    @Published var connectionState: ConnectionState = .disconnected

    var onDanmaku: ((DanmakuMessage) -> Void)?
    var onGift: ((GiftMessage) -> Void)?
    var onSuperChat: ((SuperChatMessage) -> Void)?
    var onMember: ((MemberMessage) -> Void)?
    var onError: ((BlivechatErrorMessage) -> Void)?
    var onReconnectLog: ((String) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var joinRoomWorkItem: DispatchWorkItem?
    private var reconnectDelay: Double = 5.0
    private let maxReconnectDelay: Double = 30.0
    private var reconnectAttemptCount: Int = 0

    private var server: BlivechatServer = .cn
    private var roomKeyType: RoomKeyType = .authCode
    private var roomKeyValue: String = ""
    private var isIntentionalDisconnect = false
    private var hasReceivedMessage = false

    var isManuallyDisconnected: Bool { isIntentionalDisconnect }

    private var foregroundObserver: NSObjectProtocol?

    init() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppForeground()
        }
    }

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cleanup()
    }

    func connect(server: BlivechatServer, roomKeyType: RoomKeyType, roomKeyValue: String) {
        disconnect()

        self.server = server
        self.roomKeyType = roomKeyType
        self.roomKeyValue = roomKeyValue
        self.isIntentionalDisconnect = false
        self.reconnectDelay = 5.0
        self.reconnectAttemptCount = 0

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
        hasReceivedMessage = false

        let url = server.websocketURL
        var request = URLRequest(url: url)
        request.setValue(server.originURL, forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()

        joinRoomWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.isIntentionalDisconnect else { return }
            self.joinRoomWorkItem = nil
            self.sendJoinRoom()
            self.startHeartbeat()
        }
        joinRoomWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func confirmConnected() {
        guard !hasReceivedMessage else { return }
        hasReceivedMessage = true
        connectionState = .connected
        reconnectDelay = 5.0
        if reconnectAttemptCount > 0 {
            onReconnectLog?(L10n.string("blivechat.reconnect.success", reconnectAttemptCount))
        }
        reconnectAttemptCount = 0
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
                self?.handleConnectionErrorFromCallback(error)
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self?.confirmConnected()
                }
                self?.handleMessage(message)
                self?.receiveMessage()

            case .failure(let error):
                self?.handleConnectionErrorFromCallback(error)
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
                Task { @MainActor in
                    self.onDanmaku?(danmaku)
                }
            }

        case .addGift:
            if let dict = payload as? [String: Any],
               let gift = GiftMessage(fromDict: dict) {
                Task { @MainActor in
                    self.onGift?(gift)
                }
            }

        case .addMember:
            if let dict = payload as? [String: Any],
               let member = MemberMessage(fromDict: dict) {
                Task { @MainActor in
                    self.onMember?(member)
                }
            }

        case .addSuperChat:
            if let dict = payload as? [String: Any],
               let sc = SuperChatMessage(fromDict: dict) {
                Task { @MainActor in
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
                Task { @MainActor in
                    self.connectionState = .error(error.message)
                    self.onError?(error)
                    self.isIntentionalDisconnect = true
                }
            }

        case .joinRoom:
            break
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let code = nsError.code
        let domain = nsError.domain

        if domain == NSURLErrorDomain {
            switch code {
            case NSURLErrorTimedOut:
                return L10n.string("Connection timed out")
            case NSURLErrorCannotConnectToHost:
                return L10n.string("Cannot connect to server")
            case NSURLErrorNetworkConnectionLost:
                return L10n.string("Connection lost")
            case NSURLErrorNotConnectedToInternet:
                return L10n.string("Network unavailable")
            case NSURLErrorDNSLookupFailed:
                return L10n.string("DNS lookup failed")
            case NSURLErrorCannotFindHost:
                return L10n.string("Server not found")
            case NSURLErrorResourceUnavailable:
                return L10n.string("Resource unavailable")
            default:
                break
            }
        }

        let desc = error.localizedDescription
        if desc.count > 20 {
            let index = desc.index(desc.startIndex, offsetBy: 20)
            return String(desc[..<index]) + "..."
        }
        return desc
    }

    private func handleConnectionErrorFromCallback(_ error: Error) {
        let friendlyMessage = friendlyErrorMessage(error)
        Task { @MainActor in
            self.handleConnectionError(friendlyMessage: friendlyMessage)
        }
    }

    private func handleConnectionError(friendlyMessage: String) {
        guard !isIntentionalDisconnect else { return }

        connectionState = .reconnecting(friendlyMessage)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }

        reconnectTimer?.invalidate()
        reconnectAttemptCount += 1
        let delay = reconnectDelay

        onReconnectLog?(L10n.string("blivechat.reconnect.attempt", reconnectAttemptCount, Int(delay)))

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performConnect()
        }

        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
    }

    private func handleAppForeground() {
        guard !isIntentionalDisconnect else { return }

        switch connectionState {
        case .connected:
            if !hasReceivedMessage {
                reconnectDelay = 2.0
                connectionState = .reconnecting(L10n.string("Returning to foreground, reconnecting..."))
                scheduleReconnect()
            }
        case .reconnecting, .error, .connecting:
            reconnectTimer?.invalidate()
            reconnectDelay = 1.0
            performConnect()
        case .disconnected:
            break
        }
    }

    private func cleanup() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        joinRoomWorkItem?.cancel()
        joinRoomWorkItem = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        hasReceivedMessage = false
    }
}
