//
//  NWCClient.swift
//  swae
//
//  Actor-based NWC client with connection pooling and proper async/await support.
//  This replaces the complex NostrWalletConnectService + NWCManager pattern.
//

import Combine
import Foundation
import NostrSDK

/// Actor-based NWC client that maintains a persistent relay connection
/// and provides clean async/await methods for wallet operations.
actor NWCClient {
    
    // MARK: - Types
    
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected), (.connecting, .connecting), (.connected, .connected):
                return true
            case (.error(let e1), .error(let e2)):
                return e1 == e2
            default:
                return false
            }
        }
    }
    
    enum NWCClientError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)
        case timeout
        case invalidResponse
        case walletError(String)
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to wallet relay"
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .timeout:
                return "Request timed out"
            case .invalidResponse:
                return "Invalid response from wallet"
            case .walletError(let message):
                return "Wallet error: \(message)"
            case .cancelled:
                return "Request was cancelled"
            }
        }
    }
    
    // MARK: - Properties
    
    /// The NWC connection details (created once from WalletConnectURL)
    private let connection: NWCManager.NWCConnection
    
    /// The relay instance (reused across requests)
    private var relay: Relay?
    
    /// Current connection state
    private(set) var state: ConnectionState = .disconnected
    
    /// Pending request continuations keyed by request ID
    private var pendingRequests: [String: CheckedContinuation<NWCResponseEvent, Error>] = [:]
    
    /// Combine subscription for relay events
    private var eventSubscription: AnyCancellable?
    
    /// Relay delegate handler
    private var relayHandler: RelayHandler?
    
    /// Request timeout in seconds
    private let requestTimeout: TimeInterval = 15
    
    /// Encryption helper (conforms to NIP04Encryption)
    private let encryptionHelper = NIP04EncryptionHelper()
    
    // MARK: - Initialization
    
    /// Creates a new NWCClient from a WalletConnectURL
    /// - Parameter walletConnectURL: The wallet connection URL from the app
    /// - Throws: If the connection details are invalid
    init(walletConnectURL: WalletConnectURL) throws {
        self.connection = try Self.createConnection(from: walletConnectURL)
        print("✅ NWCClient: Initialized with wallet pubkey: \(connection.walletPubkey.hex)")
    }

    
    // MARK: - Connection Management
    
    /// Connects to the wallet relay
    func connect() async throws {
        // If already connected, nothing to do
        if state == .connected {
            return
        }
        
        // If another call is already connecting, wait for it to finish
        if state == .connecting {
            print("🔗 NWCClient: Already connecting, waiting...")
            try await waitForConnection(timeout: 10)
            return
        }
        
        state = .connecting
        print("🔗 NWCClient: Connecting to relay: \(connection.relayURL)")
        
        // Create relay if needed
        if relay == nil {
            guard let newRelay = try? Relay(url: connection.relayURL) else {
                state = .error("Failed to create relay")
                throw NWCClientError.connectionFailed("Invalid relay URL")
            }
            relay = newRelay
            setupRelayHandler()
        }
        
        relay?.connect()
        
        // Wait for connection with timeout
        try await waitForConnection(timeout: 10)
    }
    
    /// Disconnects from the wallet relay
    func disconnect() {
        print("🔗 NWCClient: Disconnecting")
        
        // Cancel all pending requests
        for (requestId, continuation) in pendingRequests {
            print("⚠️ NWCClient: Cancelling pending request: \(requestId)")
            continuation.resume(throwing: NWCClientError.cancelled)
        }
        pendingRequests.removeAll()
        
        // Disconnect relay
        relay?.disconnect()
        eventSubscription?.cancel()
        eventSubscription = nil
        relayHandler = nil
        relay = nil
        state = .disconnected
    }
    
    /// Waits for the relay to connect
    private func waitForConnection(timeout: TimeInterval) async throws {
        let startTime = Date()
        
        while state == .connecting {
            // Check timeout
            if Date().timeIntervalSince(startTime) > timeout {
                state = .error("Connection timeout")
                throw NWCClientError.connectionFailed("Connection timeout")
            }
            
            // Check relay state
            if let relay = relay {
                switch relay.state {
                case .connected:
                    state = .connected
                    print("✅ NWCClient: Connected to relay")
                    return
                case .error(let error):
                    state = .error(error.localizedDescription)
                    throw NWCClientError.connectionFailed(error.localizedDescription)
                case .notConnected:
                    break
                case .connecting:
                    break
                }
            }
            
            // Small delay before checking again
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        if state != .connected {
            throw NWCClientError.connectionFailed("Connection failed")
        }
    }
    
    /// Sets up the relay event handler
    private func setupRelayHandler() {
        guard let relay = relay else { return }
        
        // Create handler that forwards events to us
        let handler = RelayHandler { [weak self] event in
            Task { [weak self] in
                await self?.handleRelayEvent(event)
            }
        } onStateChange: { [weak self] state in
            Task { [weak self] in
                await self?.handleRelayStateChange(state)
            }
        }
        
        relay.delegate = handler
        relayHandler = handler
        
        // Also subscribe to Combine events as backup
        eventSubscription = relay.events
            .sink { [weak self] relayEvent in
                Task { [weak self] in
                    await self?.handleRelayEvent(relayEvent)
                }
            }
    }
    
    /// Handles relay state changes
    private func handleRelayStateChange(_ relayState: Relay.State) {
        switch relayState {
        case .connected:
            state = .connected
        case .connecting:
            state = .connecting
        case .notConnected:
            state = .disconnected
        case .error(let error):
            state = .error(error.localizedDescription)
        }
    }
    
    /// Handles incoming relay events
    private func handleRelayEvent(_ relayEvent: RelayEvent) {
        // Only process NWC response events (kind 23195)
        guard relayEvent.event.kind.rawValue == 23195 else { return }
        
        print("🔍 NWCClient: Received NWC response event")
        
        // Get the referenced request ID from the 'e' tag
        guard let responseEvent = relayEvent.event as? NWCResponseEvent,
              let requestId = responseEvent.referencedEventId else {
            print("⚠️ NWCClient: Could not extract request ID from response")
            return
        }
        
        print("🔍 NWCClient: Response for request: \(requestId)")
        
        // Find and resume the pending continuation
        if let continuation = pendingRequests.removeValue(forKey: requestId) {
            print("✅ NWCClient: Resuming continuation for request: \(requestId)")
            continuation.resume(returning: responseEvent)
        } else {
            print("⚠️ NWCClient: No pending request found for ID: \(requestId)")
        }
    }

    
    // MARK: - Wallet Operations
    
    /// Gets the wallet balance in millisats
    func getBalance() async throws -> Int64 {
        let response = try await sendNWCRequest(method: NWCRequestMethod.getBalance)
        
        guard let result = response.result else {
            if let error = response.error {
                throw NWCClientError.walletError(error.message)
            }
            throw NWCClientError.invalidResponse
        }
        
        // Parse balance from result
        let resultData = try JSONEncoder().encode(result)
        let balanceResponse = try JSONDecoder().decode(NWCGetBalanceResponse.self, from: resultData)
        
        return Int64(balanceResponse.balance)
    }
    
    /// Lists wallet transactions
    func listTransactions(
        from: Int? = nil,
        until: Int? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        unpaid: Bool? = nil,
        type: String? = nil
    ) async throws -> [NWCTransaction] {
        var params: [String: AnyCodable] = [:]
        
        if let from = from { params["from"] = AnyCodable(from) }
        if let until = until { params["until"] = AnyCodable(until) }
        if let limit = limit { params["limit"] = AnyCodable(limit) }
        if let offset = offset { params["offset"] = AnyCodable(offset) }
        if let unpaid = unpaid { params["unpaid"] = AnyCodable(unpaid) }
        if let type = type { params["type"] = AnyCodable(type) }
        
        let response = try await sendNWCRequest(method: NWCRequestMethod.listTransactions, params: params)
        
        guard let result = response.result else {
            if let error = response.error {
                throw NWCClientError.walletError(error.message)
            }
            throw NWCClientError.invalidResponse
        }
        
        // Parse transactions from result
        let resultData = try JSONEncoder().encode(result)
        let transactionsResponse = try JSONDecoder().decode(NWCListTransactionsResponse.self, from: resultData)
        
        return transactionsResponse.transactions
    }
    
    /// Pays a Lightning invoice
    func payInvoice(_ invoice: String) async throws -> String? {
        let params: [String: AnyCodable] = ["invoice": AnyCodable(invoice)]
        let response = try await sendNWCRequest(method: NWCRequestMethod.payInvoice, params: params)
        
        guard let result = response.result else {
            if let error = response.error {
                throw NWCClientError.walletError(error.message)
            }
            throw NWCClientError.invalidResponse
        }
        
        // Parse payment response
        let resultData = try JSONEncoder().encode(result)
        let paymentResponse = try JSONDecoder().decode(NWCPayInvoiceResponse.self, from: resultData)
        
        return paymentResponse.preimage
    }
    
    /// Gets wallet info
    func getWalletInfo() async throws -> NWCWalletInfo {
        let response = try await sendNWCRequest(method: NWCRequestMethod.getInfo)
        
        guard let result = response.result else {
            if let error = response.error {
                throw NWCClientError.walletError(error.message)
            }
            throw NWCClientError.invalidResponse
        }
        
        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(NWCWalletInfo.self, from: resultData)
    }
    
    /// Creates a Lightning invoice
    func makeInvoice(amount: Int, description: String? = nil) async throws -> (invoice: String, paymentHash: String) {
        var params: [String: AnyCodable] = ["amount": AnyCodable(amount)]
        if let description = description {
            params["description"] = AnyCodable(description)
        }
        
        print("📤 NWCClient: makeInvoice - amount: \(amount), description: \(description ?? "nil")")
        
        let response = try await sendNWCRequest(method: NWCRequestMethod.makeInvoice, params: params)
        
        guard let result = response.result else {
            if let error = response.error {
                print("❌ NWCClient: makeInvoice error: \(error.message)")
                throw NWCClientError.walletError(error.message)
            }
            print("❌ NWCClient: makeInvoice - no result and no error")
            throw NWCClientError.invalidResponse
        }
        
        // Debug: print the raw result
        do {
            let resultData = try JSONEncoder().encode(result)
            if let resultString = String(data: resultData, encoding: .utf8) {
                print("🔍 NWCClient: makeInvoice raw result: \(resultString)")
            }
            let invoiceResponse = try JSONDecoder().decode(NWCMakeInvoiceResponse.self, from: resultData)
            print("✅ NWCClient: makeInvoice success - invoice: \(invoiceResponse.invoice.prefix(30))...")
            return (invoiceResponse.invoice, invoiceResponse.paymentHash)
        } catch {
            print("❌ NWCClient: makeInvoice decode error: \(error)")
            throw error
        }
    }

    
    // MARK: - Private Request Handling
    
    /// Sends an NWC request and waits for response
    private func sendNWCRequest(
        method: NWCRequestMethod,
        params: [String: AnyCodable] = [:]
    ) async throws -> NWCResponse {
        // Ensure connected (will wait for connection if needed)
        if state != .connected {
            try await connect()
        }
        
        guard let relay = relay else {
            throw NWCClientError.notConnected
        }
        
        // Create the request
        let request = NWCRequest(method: method, params: params)
        let requestJSON = try JSONEncoder().encode(request)
        let requestString = String(data: requestJSON, encoding: String.Encoding.utf8) ?? "{}"
        
        // Encrypt the request
        let encryptedContent = try encryptContent(requestString)
        
        // Create NWC request event
        let nwcRequest = try NWCRequestEvent(
            encryptedContent: encryptedContent,
            recipientPubkey: connection.walletPubkey.hex,
            signedBy: connection.clientKeypair
        )
        
        let requestId = nwcRequest.id
        print("📤 NWCClient: Sending request \(requestId) - method: \(method.rawValue)")
        
        // Set up response subscription filter
        let filter = Filter(
            authors: [connection.walletPubkey.hex],
            kinds: [23195],
            tags: ["p": [connection.clientKeypair.publicKey.hex]],
            since: Int(Date().timeIntervalSince1970) - 5
        )
        
        if let filter = filter {
            _ = try relay.subscribe(with: filter)
        }
        
        // Publish the request
        try relay.publishEvent(nwcRequest)
        
        // Wait for response with timeout
        let responseEvent = try await waitForResponse(requestId: requestId)
        
        // Decrypt and parse response
        guard let senderPubkey = PublicKey(hex: responseEvent.pubkey) else {
            throw NWCClientError.invalidResponse
        }
        
        let decryptedContent = try decryptContent(
            responseEvent.content,
            senderPubkey: senderPubkey
        )
        
        guard let responseData = decryptedContent.data(using: String.Encoding.utf8) else {
            throw NWCClientError.invalidResponse
        }
        
        let response = try JSONDecoder().decode(NWCResponse.self, from: responseData)
        
        return response
    }
    
    /// Waits for a response to a specific request
    private func waitForResponse(requestId: String) async throws -> NWCResponseEvent {
        return try await withCheckedThrowingContinuation { continuation in
            // Store the continuation
            pendingRequests[requestId] = continuation
            
            // Set up timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(requestTimeout * 1_000_000_000))
                
                // Check if still pending
                if let pendingContinuation = await self.removePendingRequest(requestId) {
                    print("⏰ NWCClient: Request \(requestId) timed out")
                    pendingContinuation.resume(throwing: NWCClientError.timeout)
                }
            }
        }
    }
    
    /// Removes and returns a pending request continuation
    private func removePendingRequest(_ requestId: String) -> CheckedContinuation<NWCResponseEvent, Error>? {
        return pendingRequests.removeValue(forKey: requestId)
    }
    
    // MARK: - Encryption/Decryption
    
    private func encryptContent(_ content: String) throws -> String {
        return try encryptionHelper.encryptNIP04(
            message: content,
            recipientPublicKey: connection.walletPubkey,
            senderPrivateKey: connection.clientKeypair.privateKey
        )
    }
    
    private func decryptContent(_ encryptedContent: String, senderPubkey: PublicKey) throws -> String {
        return try encryptionHelper.decryptNIP04(
            encryptedMessage: encryptedContent,
            senderPublicKey: senderPubkey,
            recipientPrivateKey: connection.clientKeypair.privateKey
        )
    }
    
    // MARK: - Connection Creation
    
    /// Creates an NWCConnection from a WalletConnectURL (done once at init)
    private static func createConnection(from nwc: WalletConnectURL) throws -> NWCManager.NWCConnection {
        guard nwc.secret.count == 32 else {
            throw NWCClientError.connectionFailed("Invalid secret length: \(nwc.secret.count) bytes")
        }
        
        // Convert secret to hex
        let secretHex = nwc.secret.map { String(format: "%02x", $0) }.joined()
        let walletPubkeyHex = nwc.pubkey.hex
        
        // Get relay URL from the original URI
        let originalURI = nwc.to_url().absoluteString
        
        guard let components = URLComponents(string: originalURI),
              let relayItem = components.queryItems?.first(where: { $0.name == "relay" }),
              let relayURL = relayItem.value else {
            throw NWCClientError.connectionFailed("Failed to parse relay URL")
        }
        
        // Reconstruct URI with hex secret
        let reconstructedURI = "nostr+walletconnect://\(walletPubkeyHex)?relay=\(relayURL)&secret=\(secretHex)"
        
        // Create keypair from secret for validation
        let secretData = Data(nwc.secret)
        guard let privateKey = PrivateKey(dataRepresentation: secretData),
              let keypair = Keypair(privateKey: privateKey) else {
            throw NWCClientError.connectionFailed("Failed to create keypair from secret")
        }
        
        print("🔑 NWCClient: Client pubkey: \(keypair.publicKey.hex)")
        
        return try NWCManager.createConnection(from: reconstructedURI, clientKeypair: keypair)
    }
}


// MARK: - Relay Handler

/// Helper class to handle relay delegate callbacks and forward to actor
private class RelayHandler: RelayDelegate {
    private let onEvent: (RelayEvent) -> Void
    private let onStateChange: (Relay.State) -> Void
    
    init(onEvent: @escaping (RelayEvent) -> Void, onStateChange: @escaping (Relay.State) -> Void) {
        self.onEvent = onEvent
        self.onStateChange = onStateChange
    }
    
    func relayStateDidChange(_ relay: Relay, state: Relay.State) {
        print("🔗 RelayHandler: State changed to \(state)")
        onStateChange(state)
    }
    
    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        onEvent(event)
    }
    
    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        // Not used for NWC
    }
}

// MARK: - NIP04 Encryption Helper

/// Helper class that conforms to NIP04Encryption protocol
@available(*, deprecated, message: "NIP-04 is deprecated but required for NWC")
private class NIP04EncryptionHelper: NIP04Encryption {
    // Uses default implementation from protocol extension
}

// MARK: - WalletTransaction Conversion Extension

extension NWCClient {
    /// Converts NWCTransaction to WalletTransaction for the app
    static func convertToWalletTransaction(_ nwcTransaction: NWCTransaction) -> WalletTransaction {
        let transactionType: WalletTransaction.TransactionType =
            nwcTransaction.type == "incoming" ? .incoming : .outgoing
        
        // Handle the double optional preimage (String??)
        let preimageValue: String?
        if let outerOptional = nwcTransaction.preimage {
            preimageValue = outerOptional
        } else {
            preimageValue = nil
        }
        
        return WalletTransaction(
            id: nwcTransaction.paymentHash ?? UUID().uuidString,
            type: transactionType,
            amount: Int64(nwcTransaction.amount ?? 0),
            description: cleanTransactionDescription(nwcTransaction.description),
            createdAt: Int64(nwcTransaction.createdAt),
            paymentHash: nwcTransaction.paymentHash,
            preimage: preimageValue,
            feesPaid: nwcTransaction.feesPaid.map { Int64($0) },
            settledAt: nwcTransaction.paid ? Int64(nwcTransaction.createdAt) : nil,
            expiresAt: nwcTransaction.expiresAt.map { Int64($0) }
        )
    }
    
    /// Cleans transaction description by parsing JSON and extracting meaningful text
    private static func cleanTransactionDescription(_ description: String?) -> String? {
        guard let description = description, !description.isEmpty else {
            return nil
        }
        
        // If it looks like JSON, try to parse it
        if description.hasPrefix("[") || description.hasPrefix("{") {
            return parseTransactionDescription(description)
        }
        
        return description
    }
    
    /// Parses JSON description and extracts meaningful text
    private static func parseTransactionDescription(_ jsonString: String) -> String? {
        // Try to parse as JSON array first
        if jsonString.hasPrefix("[") {
            if let data = jsonString.data(using: String.Encoding.utf8),
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
               let firstElement = jsonArray.first,
               firstElement.count >= 2,
               let textContent = firstElement[1] as? String {
                return textContent
            }
        }
        
        // Try to parse as JSON object
        if jsonString.hasPrefix("{") {
            if let data = jsonString.data(using: String.Encoding.utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let description = jsonObject["description"] as? String { return description }
                if let memo = jsonObject["memo"] as? String { return memo }
                if let message = jsonObject["message"] as? String { return message }
                if jsonObject["id"] != nil { return "Lightning payment" }
            }
        }
        
        return "Lightning payment"
    }
}
