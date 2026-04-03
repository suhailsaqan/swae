//
//  SparkWalletService.swift
//  swae
//
//  Wraps the Breez SDK for Spark, providing async/await wallet operations.
//  Replaces NWCClient for the Spark wallet backend.
//

import BreezSdkSpark
import CryptoKit
import Foundation

class SparkWalletService {
    private var sdk: BreezSdk?
    private var eventListenerId: String?
    weak var delegate: SparkWalletDelegate?

    /// Whether the SDK has been initialized
    var isInitialized: Bool { sdk != nil }

    /// The mnemonic for this wallet (available after initialization for backup purposes)
    private(set) var mnemonic: String?

    // MARK: - Initialization

    /// Initialize the Spark wallet from a Nostr private key.
    /// Derives a deterministic BIP39 mnemonic and passes it to the Breez SDK.
    func initialize(
        nostrPrivateKeyHex: String,
        publicKeyHex: String,
        apiKey: String,
        lnurlDomain: String? = nil
    ) async throws {
        let storageDir = Self.storageDirectory(for: publicKeyHex)

        // Derive deterministic mnemonic from Nostr private key
        let (seed, derivedMnemonic) = try Self.deriveSeed(from: nostrPrivateKeyHex)
        self.mnemonic = derivedMnemonic

        var config = defaultConfig(network: Network.mainnet)
        config.apiKey = apiKey
        if let domain = lnurlDomain {
            config.lnurlDomain = domain
        }
        // Disable private mode so the Breez LNURL server publishes zap receipts
        // immediately on behalf of the user (even when their phone is backgrounded).
        config.privateEnabledDefault = false

        let builder = SdkBuilder(config: config, seed: seed)
        await builder.withDefaultStorage(storageDir: storageDir)

        self.sdk = try await builder.build()

        // Register event listener
        let listener = SparkEventListener(service: self)
        self.eventListenerId = await sdk!.addEventListener(listener: listener)
    }

    // MARK: - Seed Derivation

    /// Derives a Breez SDK Seed from a Nostr private key hex string.
    /// Generates a deterministic BIP39 mnemonic that the user can back up.
    /// Uses SHA256(privkey_bytes + "spark_mnemonic_seed") as entropy for BIP39.
    private static func deriveSeed(from privateKeyHex: String) throws -> (seed: Seed, mnemonic: String) {
        guard let privKeyData = privateKeyHex.hexDecodedData() else {
            throw SparkError.invalidInput("Invalid private key hex")
        }
        var hasher = SHA256()
        hasher.update(data: privKeyData)
        hasher.update(data: Data("spark_mnemonic_seed".utf8))
        let fullHash = Data(hasher.finalize()) // 32 bytes
        let entropy = fullHash.prefix(16) // 16 bytes = 128 bits = 12 words

        let mnemonic = try BIP39.mnemonicFromEntropy(Data(entropy))
        let seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: nil)
        return (seed, mnemonic)
    }

    // MARK: - Balance

    /// Wallet balance in millisats (to match current WalletModel convention where balance is in millisats)
    func getBalanceMillisats() async throws -> Int64 {
        guard let sdk else { throw SparkError.notInitialized }
        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: nil))
        return Int64(info.balanceSats) * 1000
    }

    /// The wallet's identity public key hex (unique per seed)
    func getIdentityPubkey() async throws -> String {
        guard let sdk else { throw SparkError.notInitialized }
        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: nil))
        return info.identityPubkey
    }

    // MARK: - Payments

    /// List payments, converted to WalletTransaction
    func listPayments(limit: UInt32 = 50) async throws -> [WalletTransaction] {
        guard let sdk else { throw SparkError.notInitialized }
        let response = try await sdk.listPayments(
            request: ListPaymentsRequest(
                limit: limit,
                sortAscending: false
            ))
        return response.payments.map { Self.convertToWalletTransaction($0) }
    }

    /// Prepare a bolt11 payment — returns fee estimate without sending.
    /// The caller should show the fee to the user, then call confirmPayment() to send.
    func preparePayment(_ bolt11: String) async throws -> PreparedPayment {
        guard let sdk else { throw SparkError.notInitialized }

        let prepareResponse = try await sdk.prepareSendPayment(
            request: PrepareSendPaymentRequest(
                paymentRequest: bolt11
            ))

        // Extract fee from the payment method
        let feeSats: UInt64
        switch prepareResponse.paymentMethod {
        case .bolt11Invoice(_, let sparkFee, let lightningFee):
            // Use Spark fee if available (lower), otherwise Lightning fee
            feeSats = sparkFee ?? lightningFee
        case .sparkAddress(_, let fee, _):
            feeSats = UInt64(fee)
        case .sparkInvoice(_, let fee, _):
            feeSats = UInt64(fee)
        case .bitcoinAddress(_, let feeQuote):
            feeSats = feeQuote.speedMedium.userFeeSat + feeQuote.speedMedium.l1BroadcastFeeSat
        }

        let amountSats = UInt64(prepareResponse.amount)

        return PreparedPayment(
            prepareResponse: prepareResponse,
            amountSats: amountSats,
            feeSats: feeSats
        )
    }

    /// Confirm and send a previously prepared payment. Returns preimage if available.
    func confirmPayment(_ prepared: PreparedPayment) async throws -> String? {
        guard let sdk else { throw SparkError.notInitialized }

        let options = SendPaymentOptions.bolt11Invoice(
            preferSpark: false,
            completionTimeoutSecs: 30
        )
        let sendResponse = try await sdk.sendPayment(
            request: SendPaymentRequest(
                prepareResponse: prepared.prepareResponse,
                options: options
            ))

        if let details = sendResponse.payment.details,
           case .lightning(let lightningDetails) = details {
            return lightningDetails.htlcDetails.preimage
        }
        return nil
    }

    /// Pay a bolt11 Lightning invoice in one step (prepare + send). Returns preimage if available.
    /// Use preparePayment() + confirmPayment() for the two-step flow with fee display.
    func payInvoice(_ bolt11: String) async throws -> String? {
        let prepared = try await preparePayment(bolt11)
        return try await confirmPayment(prepared)
    }

    /// Holds the result of a prepared payment for confirmation
    struct PreparedPayment {
        let prepareResponse: PrepareSendPaymentResponse
        let amountSats: UInt64
        let feeSats: UInt64
    }

    /// Create a bolt11 invoice for receiving payments
    func makeInvoice(amountSats: Int, description: String?) async throws -> (invoice: String, paymentHash: String) {
        guard let sdk else { throw SparkError.notInitialized }

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: ReceivePaymentMethod.bolt11Invoice(
                    description: description ?? "Swae payment",
                    amountSats: UInt64(amountSats),
                    expirySecs: 3600,
                    paymentHash: nil
                )))

        // The paymentRequest is the bolt11 invoice string
        return (response.paymentRequest, "")
    }

    // MARK: - Lightning Address

    /// Register a Lightning address for receiving payments
    func registerLightningAddress(username: String) async throws -> String {
        guard let sdk else { throw SparkError.notInitialized }
        let request = RegisterLightningAddressRequest(
            username: username,
            description: "Pay \(username) on Swae"
        )
        let info = try await sdk.registerLightningAddress(request: request)
        return info.lightningAddress
    }

    /// Get current Lightning address (nil if not registered)
    func getLightningAddress() async throws -> String? {
        guard let sdk else { throw SparkError.notInitialized }
        let info = try await sdk.getLightningAddress()
        return info?.lightningAddress
    }

    // MARK: - Lifecycle

    func disconnect() async {
        if let id = eventListenerId, let sdk {
            await sdk.removeEventListener(id: id)
        }
        eventListenerId = nil
        mnemonic = nil
        sdk = nil
    }

    // MARK: - Storage

    private static func storageDirectory(for keyHex: String) -> String {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first!
        // Use first 16 chars of the key hex as directory name.
        // IMPORTANT: This must match the check in WalletModel.init() which uses publicKey.hex.
        // We hash the private key to get a stable identifier that matches the public key prefix.
        // Actually, we just use the key as-is — the caller decides what to pass.
        let dirName = "spark_\(String(keyHex.prefix(16)))"
        let sparkDir = documentsDir.appendingPathComponent(dirName)
        try? FileManager.default.createDirectory(
            at: sparkDir, withIntermediateDirectories: true)
        return sparkDir.path
    }

    // MARK: - Transaction Conversion

    static func convertToWalletTransaction(_ payment: Payment) -> WalletTransaction {
        let txType: WalletTransaction.TransactionType =
            payment.paymentType == .send ? .outgoing : .incoming

        // Extract details from payment
        var paymentHash: String?
        var preimage: String?
        var bolt11Invoice: String?
        var description: String?

        // Zap enrichment data
        var senderPubkey: String?
        var recipientPubkey: String?
        var zapMessage: String?
        var zappedEventId: String?
        var zappedEventCoordinate: String?
        var isZap = false

        if let details = payment.details {
            switch details {
            case .lightning(let lightning):
                bolt11Invoice = lightning.invoice
                description = lightning.description
                paymentHash = lightning.htlcDetails.paymentHash
                preimage = lightning.htlcDetails.preimage

                // Strategy A: Check LnurlReceiveMetadata for incoming zaps
                // The Breez LNURL server populates this with the NIP-57 zap request
                if let metadata = lightning.lnurlReceiveMetadata {
                    if let zapRequestJSON = metadata.nostrZapRequest,
                       let zapData = parseZapRequestJSON(zapRequestJSON) {
                        senderPubkey = zapData.senderPubkey
                        recipientPubkey = zapData.recipientPubkey
                        zapMessage = zapData.message
                        zappedEventId = zapData.eventId
                        zappedEventCoordinate = zapData.eventCoordinate
                        isZap = true
                    }
                    // Use sender comment as fallback zap message
                    if zapMessage == nil, let comment = metadata.senderComment, !comment.isEmpty {
                        zapMessage = comment
                    }
                }

                // Strategy B: For sent payments, try parsing the invoice description
                // as a zap request JSON (same as NWC Strategy A).
                // LNURL services set the bolt11 description to the zap request JSON.
                if !isZap, let desc = lightning.description {
                    if let zapData = parseZapRequestJSON(desc) {
                        senderPubkey = zapData.senderPubkey
                        recipientPubkey = zapData.recipientPubkey
                        zapMessage = zapData.message
                        zappedEventId = zapData.eventId
                        zappedEventCoordinate = zapData.eventCoordinate
                        isZap = true
                        // Clean the description since it's raw JSON
                        description = nil
                    }
                }

            case .spark:
                break
            default:
                break
            }
        }

        let amountMillisats = Int64(payment.amount) * 1000
        let feesMillisats = Int64(payment.fees) * 1000

        return WalletTransaction(
            id: payment.id,
            type: txType,
            amount: amountMillisats,
            description: description,
            createdAt: Int64(payment.timestamp),
            paymentHash: paymentHash,
            preimage: preimage,
            feesPaid: feesMillisats,
            settledAt: payment.status == .completed ? Int64(payment.timestamp) : nil,
            expiresAt: nil,
            senderPubkey: senderPubkey,
            recipientPubkey: recipientPubkey,
            zapMessage: zapMessage,
            zappedEventId: zappedEventId,
            zappedEventCoordinate: zappedEventCoordinate,
            bolt11Invoice: bolt11Invoice,
            isZap: isZap
        )
    }

    /// Parses a JSON string as a NIP-57 zap request event (kind 9734).
    private static func parseZapRequestJSON(_ json: String) -> ZapEnrichmentData? {
        guard json.hasPrefix("{"),
              let data = json.data(using: .utf8) else {
            return nil
        }
        // Decode as a generic Nostr event first to check the kind
        struct NostrEventStub: Decodable {
            let kind: Int
            let pubkey: String
            let content: String
            let tags: [[String]]
        }
        guard let event = try? JSONDecoder().decode(NostrEventStub.self, from: data),
              event.kind == 9734 else {
            return nil
        }
        // Extract tagged values
        let recipientPubkey = event.tags.first(where: { $0.first == "p" })?[safe: 1]
        let eventId = event.tags.first(where: { $0.first == "e" })?[safe: 1]
        let eventCoordinate = event.tags.first(where: { $0.first == "a" })?[safe: 1]

        return ZapEnrichmentData(
            senderPubkey: event.pubkey,
            recipientPubkey: recipientPubkey,
            message: event.content.isEmpty ? nil : event.content,
            eventId: eventId,
            eventCoordinate: eventCoordinate
        )
    }

    struct ZapEnrichmentData {
        let senderPubkey: String
        let recipientPubkey: String?
        let message: String?
        let eventId: String?
        let eventCoordinate: String?
    }

    // MARK: - Errors

    enum SparkError: Error, LocalizedError {
        case notInitialized
        case invalidInput(String)

        var errorDescription: String? {
            switch self {
            case .notInitialized: return "Wallet not initialized"
            case .invalidInput(let msg): return msg
            }
        }
    }
}

// MARK: - Event Handling

protocol SparkWalletDelegate: AnyObject {
    func sparkWalletDidSync()
    func sparkWalletPaymentSucceeded(_ payment: Payment)
    func sparkWalletPaymentFailed(_ payment: Payment)
    func sparkWalletLightningAddressChanged(_ address: LightningAddressInfo?)
}

class SparkEventListener: EventListener {
    weak var service: SparkWalletService?

    init(service: SparkWalletService) {
        self.service = service
    }

    func onEvent(event: SdkEvent) async {
        switch event {
        case .synced:
            service?.delegate?.sparkWalletDidSync()
        case .paymentSucceeded(let payment):
            service?.delegate?.sparkWalletPaymentSucceeded(payment)
        case .paymentFailed(let payment):
            service?.delegate?.sparkWalletPaymentFailed(payment)
        case .lightningAddressChanged(let address):
            service?.delegate?.sparkWalletLightningAddressChanged(address)
        default:
            break
        }
    }
}

// MARK: - Hex Decoding Helper

private extension String {
    func hexDecodedData() -> Data? {
        guard count % 2 == 0 else { return nil }
        var data = Data(capacity: count / 2)
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
