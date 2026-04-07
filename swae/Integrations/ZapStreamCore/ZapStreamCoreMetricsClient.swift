import Foundation
import NostrSDK

// MARK: - Server Metrics Models

struct ZapStreamMetrics {
    let streamId: String
    let startedAt: String
    let lastSegmentTime: String
    let viewers: Int
    let averageFps: Double
    let targetFps: Double
    let frameCount: Int
    let inputResolution: String
    let ingressName: String
    let endpointStats: [String: ZapStreamEndpointStats]
}

struct ZapStreamEndpointStats {
    let name: String
    let bitrate: Int
}

// MARK: - Delegate

protocol ZapStreamCoreMetricsDelegate: AnyObject {
    func zapStreamMetricsUpdated(_ metrics: ZapStreamMetrics)
    func zapStreamMetricsError(_ message: String)
}

// MARK: - Metrics Client

/// Connects to the zap.stream WebSocket metrics endpoint, authenticates via NIP-98,
/// subscribes to the user's own stream, and forwards StreamMetrics to the delegate.
class ZapStreamCoreMetricsClient: NSObject {
    private var webSocket: WebSocketClient?
    private let baseUrl: String
    private let keypair: Keypair
    private var streamId: String?
    private var authenticated = false
    weak var delegate: ZapStreamCoreMetricsDelegate?

    init(baseUrl: String, keypair: Keypair) {
        self.baseUrl = baseUrl
        self.keypair = keypair
        super.init()
    }

    func connect(streamId: String) {
        self.streamId = streamId
        authenticated = false

        let wsUrl = makeWebSocketUrl()
        guard let url = URL(string: wsUrl) else {
            logger.warning("zap-stream-metrics: Invalid WebSocket URL: \(wsUrl)")
            return
        }

        logger.info("zap-stream-metrics: Connecting to \(wsUrl)")
        webSocket = WebSocketClient(url: url)
        webSocket?.delegate = self
        webSocket?.start()
    }

    func disconnect() {
        logger.info("zap-stream-metrics: Disconnecting")
        webSocket?.stop()
        webSocket = nil
        streamId = nil
        authenticated = false
    }

    // MARK: - Private

    private func makeWebSocketUrl() -> String {
        // Replace https:// with wss:// (or http:// with ws://)
        var url = baseUrl
        if url.hasPrefix("https://") {
            url = "wss://" + url.dropFirst("https://".count)
        } else if url.hasPrefix("http://") {
            url = "ws://" + url.dropFirst("http://".count)
        }
        return url + "/api/v1/ws"
    }

    private func sendAuth() {
        let wsUrl = makeWebSocketUrl()
        guard let url = URL(string: wsUrl) else { return }

        do {
            let authEvent = try HTTPAuthEvent.Builder()
                .url(url)
                .method("GET")
                .build(signedBy: keypair)

            let eventJson = try JSONEncoder().encode(authEvent)
            guard let eventString = String(data: eventJson, encoding: .utf8) else { return }
            let token = Data(eventString.utf8).base64EncodedString()

            let message = "{\"type\":\"Auth\",\"data\":{\"token\":\"\(token)\"}}"
            webSocket?.send(string: message)
            logger.info("zap-stream-metrics: Auth sent")
        } catch {
            logger.warning("zap-stream-metrics: Failed to create auth event: \(error)")
        }
    }

    private func sendSubscribe() {
        guard let streamId else { return }
        let message = "{\"type\":\"SubscribeStream\",\"data\":{\"stream_id\":\"\(streamId)\"}}"
        webSocket?.send(string: message)
        logger.info("zap-stream-metrics: Subscribed to stream \(streamId)")
    }

    private func handleMessage(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }

        // Parse the top-level { "type": "...", "data": { ... } } envelope
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "AuthResponse":
            handleAuthResponse(json)
        case "StreamMetrics":
            handleStreamMetrics(json)
        case "Error":
            handleError(json)
        default:
            break
        }
    }

    private func handleAuthResponse(_ json: [String: Any]) {
        guard let responseData = json["data"] as? [String: Any],
              let success = responseData["success"] as? Bool
        else { return }

        if success {
            logger.info("zap-stream-metrics: Authenticated")
            authenticated = true
            sendSubscribe()
        } else {
            logger.warning("zap-stream-metrics: Auth failed")
            delegate?.zapStreamMetricsError("Metrics authentication failed")
        }
    }

    private func handleStreamMetrics(_ json: [String: Any]) {
        guard let d = json["data"] as? [String: Any] else { return }

        // Parse endpoint_stats
        var endpointStats: [String: ZapStreamEndpointStats] = [:]
        if let statsDict = d["endpoint_stats"] as? [String: [String: Any]] {
            for (key, value) in statsDict {
                let name = value["name"] as? String ?? key
                let bitrate = value["bitrate"] as? Int ?? 0
                endpointStats[key] = ZapStreamEndpointStats(name: name, bitrate: bitrate)
            }
        }

        let metrics = ZapStreamMetrics(
            streamId: d["stream_id"] as? String ?? "",
            startedAt: d["started_at"] as? String ?? "",
            lastSegmentTime: d["last_segment_time"] as? String ?? "",
            viewers: d["viewers"] as? Int ?? 0,
            averageFps: d["average_fps"] as? Double ?? 0,
            targetFps: d["target_fps"] as? Double ?? 0,
            frameCount: d["frame_count"] as? Int ?? 0,
            inputResolution: d["input_resolution"] as? String ?? "",
            ingressName: d["ingress_name"] as? String ?? "",
            endpointStats: endpointStats
        )

        delegate?.zapStreamMetricsUpdated(metrics)
    }

    private func handleError(_ json: [String: Any]) {
        let message = (json["data"] as? [String: Any])?["message"] as? String ?? "Unknown error"
        logger.warning("zap-stream-metrics: Server error: \(message)")
        delegate?.zapStreamMetricsError(message)
    }
}

// MARK: - WebSocketClientDelegate

extension ZapStreamCoreMetricsClient: WebSocketClientDelegate {
    func webSocketClientConnected(_: WebSocketClient) {
        logger.info("zap-stream-metrics: Connected")
        sendAuth()
    }

    func webSocketClientDisconnected(_: WebSocketClient) {
        logger.info("zap-stream-metrics: Disconnected (will auto-reconnect)")
        authenticated = false
    }

    func webSocketClientReceiveMessage(_: WebSocketClient, string: String) {
        handleMessage(string)
    }
}
