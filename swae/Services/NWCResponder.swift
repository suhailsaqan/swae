//
//  NWCResponder.swift
//  swae
//
//  On-device NWC wallet service that responds to pay_invoice requests
//  from the zap.stream server using the Spark wallet backend.
//  This allows auto-pay to work with self-custodial Spark wallets
//  by running the NWC responder on the phone while streaming.
//

import Combine
import Foundation
import NostrSDK

class NWCResponder {

    // MARK: - State

    enum State {
        case stopped
        case starting
        case running
        case error(String)
    }

    private(set) var state: State = .stopped

    /// The generated NWC URL to send to the zap.stream server
    private(set) var nwcURL: WalletConnectURL?

    // MARK: - Identity

    /// The wallet service keypair (we are the wallet service)
    private var walletKeypair: Keypair?

    /// The client's pubkey (derived from the secret we generate — this is the zap.stream server's identity)
    private var clientPubkey: PublicKey?

    /// The shared secret (also the client's private key)
    private var clientSecret: Data?

    // MARK: - Relay

    private var relay: Relay?
    private var relayHandler: NWCResponderRelayHandler?
    private var eventSubscription: AnyCancellable?
    private let relayURL: URL

    // MARK: - Spark

    private weak var sparkService: SparkWalletService?

    // MARK: - Reconnection

    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var reconnectWorkItem: DispatchWorkItem?

    // MARK: - Processing

    /// Serial queue to avoid concurrent pay_invoice calls (prevents double-spending)
    private let processingQueue = DispatchQueue(label: "nwc.responder.processing", qos: .userInitiated)
    private var isProcessingPayment = false

    // MARK: - NIP-04 Encryption

    @available(*, deprecated, message: "NIP-04 is deprecated but required for NWC")
    private class NIP04Helper: NIP04Encryption {}
    private let encryptionHelper = NIP04Helper()

    // MARK: - Init

    static let defaultRelayURL = URL(string: "wss://relay.damus.io")!

    init(relayURL: URL = NWCResponder.defaultRelayURL) {
        self.relayURL = relayURL
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    /// Starts the NWC responder. Returns the NWC URL to send to the zap.stream server.
    func start(sparkService: SparkWalletService) async throws -> WalletConnectURL {
        guard case .stopped = state else {
            if let url = nwcURL { return url }
            throw NWCResponderError.alreadyRunning
        }

        state = .starting
        self.sparkService = sparkService

        // 1. Generate wallet service keypair
        guard let keypair = Keypair() else {
            state = .error("Failed to generate keypair")
            throw NWCResponderError.keypairGenerationFailed
        }
        walletKeypair = keypair

        // 2. Generate random 32-byte secret (this is the client's private key)
        var secretBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &secretBytes)
        guard status == errSecSuccess else {
            state = .error("Failed to generate secret")
            throw NWCResponderError.secretGenerationFailed
        }
        clientSecret = Data(secretBytes)

        // 3. Derive client pubkey from secret
        guard let clientPrivKey = PrivateKey(dataRepresentation: Data(secretBytes)),
              let clientKP = Keypair(privateKey: clientPrivKey) else {
            state = .error("Failed to derive client keypair")
            throw NWCResponderError.keypairGenerationFailed
        }
        clientPubkey = clientKP.publicKey

        // 4. Connect to relay
        guard let newRelay = try? Relay(url: relayURL) else {
            state = .error("Invalid relay URL")
            throw NWCResponderError.relayConnectionFailed("Invalid relay URL")
        }
        relay = newRelay
        setupRelayHandler()
        relay?.connect()

        // Wait for connection
        try await waitForRelayConnection(timeout: 10)

        // 5. Publish kind 13194 info event (plaintext content per NIP-47 spec)
        try publishInfoEvent()

        // 6. Subscribe to incoming NWC requests (kind 23194) addressed to us
        try subscribeToRequests()

        // 7. Build the NWC URL
        let secretHex = secretBytes.map { String(format: "%02x", $0) }.joined()
        let nwcURLString = "nostr+walletconnect://\(keypair.publicKey.hex)?relay=\(relayURL.absoluteString)&secret=\(secretHex)"
        guard let url = WalletConnectURL(str: nwcURLString) else {
            state = .error("Failed to construct NWC URL")
            throw NWCResponderError.urlConstructionFailed
        }
        nwcURL = url
        state = .running
        reconnectAttempt = 0

        print("✅ NWCResponder: Started. Wallet pubkey: \(keypair.publicKey.hex.prefix(8))...")
        return url
    }

    /// Stops the responder and cleans up all resources.
    func stop() {
        print("🔌 NWCResponder: Stopping")
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        eventSubscription?.cancel()
        eventSubscription = nil
        relay?.disconnect()
        relayHandler = nil
        relay = nil
        walletKeypair = nil
        clientPubkey = nil
        clientSecret = nil
        nwcURL = nil
        state = .stopped
    }

    // MARK: - Relay Management

    private func waitForRelayConnection(timeout: TimeInterval) async throws {
        let start = Date()
        while relay?.state != .connected {
            if Date().timeIntervalSince(start) > timeout {
                state = .error("Relay connection timeout")
                throw NWCResponderError.relayConnectionFailed("Timeout")
            }
            if case .error(let err) = relay?.state {
                state = .error("Relay error: \(err)")
                throw NWCResponderError.relayConnectionFailed(err.localizedDescription)
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    private func setupRelayHandler() {
        guard let relay else { return }

        let handler = NWCResponderRelayHandler(
            onEvent: { [weak self] event in self?.handleRelayEvent(event) },
            onStateChange: { [weak self] newState in self?.handleRelayStateChange(newState) }
        )
        relay.delegate = handler
        relayHandler = handler
    }

    private func handleRelayStateChange(_ relayState: Relay.State) {
        switch relayState {
        case .connected:
            print("✅ NWCResponder: Relay connected")
            reconnectAttempt = 0
            // Re-subscribe after reconnect
            if case .running = state {
                try? subscribeToRequests()
            }
        case .notConnected:
            if case .running = state, relay != nil {
                print("⚠️ NWCResponder: Relay disconnected, scheduling reconnect")
                scheduleReconnect()
            }
        case .error(let err):
            print("❌ NWCResponder: Relay error: \(err)")
            if case .running = state, relay != nil {
                scheduleReconnect()
            }
        case .connecting:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1
        print("🔄 NWCResponder: Reconnecting in \(delay)s (attempt \(reconnectAttempt))")

        let work = DispatchWorkItem { [weak self] in
            self?.relay?.connect()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Event Publishing

    private func publishInfoEvent() throws {
        guard let keypair = walletKeypair, let relay else {
            throw NWCResponderError.notStarted
        }

        // NIP-47 spec: kind 13194 content is plaintext space-separated methods
        let infoEvent = try NWCInfoEvent(
            name: "Swae Spark Wallet",
            description: "On-device NWC responder for Spark wallet auto-pay",
            version: "1.0",
            supportedMethods: ["pay_invoice", "get_info"],
            signedBy: keypair
        )
        try relay.publishEvent(infoEvent)
        print("📤 NWCResponder: Published info event (kind 13194)")
    }

    private func subscribeToRequests() throws {
        guard let keypair = walletKeypair, let relay else {
            throw NWCResponderError.notStarted
        }

        // Subscribe to kind 23194 (NWC request) events tagged with our wallet pubkey
        let filter = Filter(
            kinds: [23194],
            tags: ["p": [keypair.publicKey.hex]],
            since: Int(Date().timeIntervalSince1970) - 5
        )
        if let filter {
            _ = try relay.subscribe(with: filter)
            print("📡 NWCResponder: Subscribed to NWC requests")
        }
    }

    // MARK: - Request Handling

    private func handleRelayEvent(_ relayEvent: RelayEvent) {
        // Only process kind 23194 (NWC request)
        guard relayEvent.event.kind.rawValue == 23194 else { return }

        guard let clientPubkey, let walletKeypair else { return }

        let event = relayEvent.event

        // Verify the request is from the expected client (zap.stream server)
        guard event.pubkey == clientPubkey.hex else {
            print("⚠️ NWCResponder: Ignoring request from unknown pubkey: \(event.pubkey.prefix(8))...")
            return
        }

        // Verify it's addressed to us (p tag)
        guard event.firstValue(forTag: "p") == walletKeypair.publicKey.hex else {
            print("⚠️ NWCResponder: Ignoring request not addressed to us")
            return
        }

        let requestId = event.id
        print("📥 NWCResponder: Received NWC request \(requestId.prefix(8))...")

        // Process on serial queue to avoid concurrent payments
        processingQueue.async { [weak self] in
            guard let self else { return }
            Task {
                await self.processRequest(event: event, requestId: requestId)
            }
        }
    }

    private func processRequest(event: NostrEvent, requestId: String) async {
        guard let walletKeypair, let clientPubkey else { return }

        do {
            // Decrypt the request content
            let decrypted = try encryptionHelper.decryptNIP04(
                encryptedMessage: event.content,
                senderPublicKey: clientPubkey,
                recipientPrivateKey: walletKeypair.privateKey
            )

            guard let data = decrypted.data(using: String.Encoding.utf8) else {
                try? await sendErrorResponse(
                    requestId: requestId,
                    code: -32700,
                    message: "Parse error"
                )
                return
            }

            let request = try JSONDecoder().decode(NWCRequest.self, from: data)
            print("📥 NWCResponder: Method: \(request.method.rawValue)")

            switch request.method {
            case .payInvoice:
                await handlePayInvoice(request: request, requestId: requestId)
            case .getInfo:
                try await sendGetInfoResponse(requestId: requestId)
            default:
                try await sendErrorResponse(
                    requestId: requestId,
                    code: -32601,
                    message: "Method not supported: \(request.method.rawValue)"
                )
            }
        } catch {
            print("❌ NWCResponder: Failed to process request: \(error)")
            try? await sendErrorResponse(
                requestId: requestId,
                code: -32603,
                message: "Internal error: \(error.localizedDescription)"
            )
        }
    }

    private func handlePayInvoice(request: NWCRequest, requestId: String) async {
        guard let spark = sparkService else {
            try? await sendErrorResponse(
                requestId: requestId,
                code: -32603,
                message: "Wallet not available"
            )
            return
        }

        // Extract bolt11 invoice from params
        guard let invoiceValue = request.params["invoice"]?.value as? String else {
            try? await sendErrorResponse(
                requestId: requestId,
                code: -32602,
                message: "Missing invoice parameter"
            )
            return
        }

        print("⚡ NWCResponder: Paying invoice: \(invoiceValue.prefix(20))...")

        do {
            let preimage = try await spark.payInvoice(invoiceValue)
            print("✅ NWCResponder: Payment succeeded")

            // Build success response
            let result: [String: Any] = ["preimage": preimage ?? ""]
            let response = NWCResponse(result: AnyCodable(result))
            try await sendResponse(response, requestId: requestId)
        } catch {
            print("❌ NWCResponder: Payment failed: \(error)")
            try? await sendErrorResponse(
                requestId: requestId,
                code: -32010,
                message: "Payment failed: \(error.localizedDescription)"
            )
        }
    }

    private func sendGetInfoResponse(requestId: String) async throws {
        let result: [String: Any] = [
            "alias": "Swae Spark Wallet",
            "pubkey": walletKeypair?.publicKey.hex ?? "",
            "network": "mainnet",
            "methods": ["pay_invoice", "get_info"]
        ]
        let response = NWCResponse(result: AnyCodable(result))
        try await sendResponse(response, requestId: requestId)
    }

    // MARK: - Response Sending

    private func sendResponse(_ response: NWCResponse, requestId: String) async throws {
        guard let walletKeypair, let clientPubkey, let relay else {
            throw NWCResponderError.notStarted
        }

        let responseJSON = try JSONEncoder().encode(response)
        let responseString = String(data: responseJSON, encoding: String.Encoding.utf8) ?? "{}"

        // Encrypt with NIP-04
        let encrypted = try encryptionHelper.encryptNIP04(
            message: responseString,
            recipientPublicKey: clientPubkey,
            senderPrivateKey: walletKeypair.privateKey
        )

        // Create kind 23195 response event
        let responseEvent = try NWCResponseEvent(
            encryptedContent: encrypted,
            recipientPubkey: clientPubkey.hex,
            requestEventId: requestId,
            signedBy: walletKeypair
        )

        try relay.publishEvent(responseEvent)
        print("📤 NWCResponder: Sent response for request \(requestId.prefix(8))...")
    }

    private func sendErrorResponse(requestId: String, code: Int, message: String) async throws {
        let response = NWCResponse(error: NWCError(code: code, message: message))
        try await sendResponse(response, requestId: requestId)
    }

    // MARK: - Errors

    enum NWCResponderError: Error, LocalizedError {
        case alreadyRunning
        case notStarted
        case keypairGenerationFailed
        case secretGenerationFailed
        case relayConnectionFailed(String)
        case urlConstructionFailed
        case testFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "NWC responder is already running"
            case .notStarted: return "NWC responder is not started"
            case .keypairGenerationFailed: return "Failed to generate keypair"
            case .secretGenerationFailed: return "Failed to generate secret"
            case .relayConnectionFailed(let reason): return "Relay connection failed: \(reason)"
            case .urlConstructionFailed: return "Failed to construct NWC URL"
            case .testFailed(let reason): return "Self-test failed: \(reason)"
            }
        }
    }

    // MARK: - Debug Self-Test

    #if DEBUG
    /// Simulates the zap.stream server sending a pay_invoice request to this responder.
    /// Tests the full round-trip: connect as client → encrypt request → publish to relay →
    /// responder decrypts → calls Spark → encrypts response → publishes to relay → client decrypts.
    ///
    /// Call this after `start()` succeeds. Uses a small test invoice or get_info if no invoice provided.
    /// Returns the response method result as a string for logging.
    func selfTest(testInvoice: String? = nil) async throws -> String {
        guard case .running = state,
              let walletKeypair,
              let clientSecret,
              let clientPubkey else {
            throw NWCResponderError.notStarted
        }

        print("🧪 NWCResponder Self-Test: Starting...")

        // 1. Create a client keypair from the secret (same as what zap.stream server would do)
        guard let clientPrivKey = PrivateKey(dataRepresentation: clientSecret),
              let clientKP = Keypair(privateKey: clientPrivKey) else {
            throw NWCResponderError.testFailed("Failed to derive client keypair from secret")
        }

        // Verify the derived pubkey matches what we expect
        guard clientKP.publicKey.hex == clientPubkey.hex else {
            throw NWCResponderError.testFailed("Client pubkey mismatch")
        }

        // 2. Connect a separate relay as the "client" (simulating zap.stream server)
        guard let testRelay = try? Relay(url: relayURL) else {
            throw NWCResponderError.testFailed("Failed to create test relay")
        }

        testRelay.connect()

        // Wait for connection
        let start = Date()
        while testRelay.state != .connected {
            if Date().timeIntervalSince(start) > 10 {
                testRelay.disconnect()
                throw NWCResponderError.testFailed("Test relay connection timeout")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        print("🧪 NWCResponder Self-Test: Test relay connected")

        // 3. Build the NWC request (get_info is safe — doesn't spend money)
        let method: NWCRequestMethod = testInvoice != nil ? .payInvoice : .getInfo
        var params: [String: AnyCodable] = [:]
        if let invoice = testInvoice {
            params["invoice"] = AnyCodable(invoice)
        }
        let request = NWCRequest(method: method, params: params)
        let requestJSON = try JSONEncoder().encode(request)
        let requestString = String(data: requestJSON, encoding: String.Encoding.utf8) ?? "{}"

        // 4. Encrypt with NIP-04 (client encrypts to wallet service)
        @available(*, deprecated, message: "NIP-04 required for NWC")
        class TestNIP04Helper: NIP04Encryption {}
        let testEncHelper = TestNIP04Helper()

        let encrypted = try testEncHelper.encryptNIP04(
            message: requestString,
            recipientPublicKey: walletKeypair.publicKey,
            senderPrivateKey: clientKP.privateKey
        )

        // 5. Create kind 23194 request event
        let requestEvent = try NWCRequestEvent(
            encryptedContent: encrypted,
            recipientPubkey: walletKeypair.publicKey.hex,
            signedBy: clientKP
        )
        let requestId = requestEvent.id
        print("🧪 NWCResponder Self-Test: Sending \(method.rawValue) request (id: \(requestId.prefix(8))...)")

        // 6. Set up response listener FIRST, then subscribe and publish
        let responseResult: String = try await withCheckedThrowingContinuation { continuation in
            var completed = false
            var testSubscription: AnyCancellable?

            let timeout = DispatchWorkItem {
                guard !completed else { return }
                completed = true
                testSubscription?.cancel()
                testRelay.disconnect()
                continuation.resume(throwing: NWCResponderError.testFailed("Response timeout (15s)"))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)

            // Listen via Combine publisher (more reliable than delegate for this use case)
            testSubscription = testRelay.events
                .sink { event in
                    guard !completed,
                          event.event.kind.rawValue == 23195,
                          event.event.firstValue(forTag: "e") == requestId else { return }

                    completed = true
                    timeout.cancel()
                    testSubscription?.cancel()

                    do {
                        let senderPubkey = PublicKey(hex: event.event.pubkey)!
                        let decrypted = try testEncHelper.decryptNIP04(
                            encryptedMessage: event.event.content,
                            senderPublicKey: senderPubkey,
                            recipientPrivateKey: clientKP.privateKey
                        )
                        testRelay.disconnect()
                        continuation.resume(returning: decrypted)
                    } catch {
                        testRelay.disconnect()
                        continuation.resume(throwing: NWCResponderError.testFailed("Decrypt failed: \(error)"))
                    }
                }

            // Now subscribe to the filter and publish the request
            do {
                let responseFilter = Filter(
                    authors: [walletKeypair.publicKey.hex],
                    kinds: [23195],
                    tags: ["p": [clientKP.publicKey.hex]],
                    since: Int(Date().timeIntervalSince1970) - 5
                )
                if let filter = responseFilter {
                    _ = try testRelay.subscribe(with: filter)
                }
                try testRelay.publishEvent(requestEvent)
                print("🧪 NWCResponder Self-Test: Request published, waiting for response...")
            } catch {
                guard !completed else { return }
                completed = true
                timeout.cancel()
                testSubscription?.cancel()
                testRelay.disconnect()
                continuation.resume(throwing: NWCResponderError.testFailed("Publish failed: \(error)"))
            }
        }

        print("🧪 NWCResponder Self-Test: ✅ Got response: \(responseResult.prefix(200))")
        return responseResult
    }
    #endif
}

// MARK: - Relay Handler

private class NWCResponderRelayHandler: RelayDelegate {
    private let onEvent: (RelayEvent) -> Void
    private let onStateChange: (Relay.State) -> Void

    init(onEvent: @escaping (RelayEvent) -> Void, onStateChange: @escaping (Relay.State) -> Void) {
        self.onEvent = onEvent
        self.onStateChange = onStateChange
    }

    func relayStateDidChange(_ relay: Relay, state: Relay.State) {
        onStateChange(state)
    }

    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        onEvent(event)
    }

    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        // Not used
    }
}

// MARK: - Test Relay Delegate

#if DEBUG
private class NWCTestRelayDelegate: RelayDelegate {
    private let onEvent: (RelayEvent) -> Void

    init(onEvent: @escaping (RelayEvent) -> Void) {
        self.onEvent = onEvent
    }

    func relayStateDidChange(_ relay: Relay, state: Relay.State) {}

    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        onEvent(event)
    }

    func relay(_ relay: Relay, didReceive response: RelayResponse) {}
}
#endif
