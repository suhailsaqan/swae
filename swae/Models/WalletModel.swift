//
//  WalletModel.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//

import BreezSdkSpark
import Foundation
import NostrSDK
import SwiftUI

enum WalletError: Error, LocalizedError {
    case noWalletConnected
    case nwcRequestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noWalletConnected:
            return "No wallet connected"
        case .nwcRequestFailed(let message):
            return "NWC request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from wallet"
        }
    }
}

enum WalletConnectState {
    case new(WalletConnectURL)
    case existing(WalletConnectURL)
    case spark(lud16: String?)
    case none
}

class WalletModel: ObservableObject {
    var publicKey: PublicKey
    private(set) var previous_state: WalletConnectState
    let nostrWalletConnectSecureStorage = NostrWalletConnectKeyStorage()
    private let appState: AppState

    @Published private(set) var connect_state: WalletConnectState

    // MARK: - Wallet Data
    /// The wallet's balance in millisats. Starts with `nil` to signify it is not loaded yet
    @Published private(set) var balance: Int64? = nil

    /// The list of wallet transactions. Starts with `nil` to signify it is not loaded yet
    @Published private(set) var transactions: [WalletTransaction]? = nil

    /// Whether the wallet data is currently being loaded
    @Published private(set) var isLoading: Bool = false

    /// Any error that occurred while loading wallet data
    @Published private(set) var error: String? = nil
    
    // MARK: - NWC Client (Option C - persistent connection)
    /// The NWC client instance - created once and reused for all requests
    private var nwcClient: NWCClient?

    // MARK: - Spark Wallet Service
    /// Feature flag: set to true to use Spark backend instead of NWC/Coinos
    static let useSparkBackend = true

    /// The Spark wallet service instance
    private(set) var sparkService: SparkWalletService?

    /// The Lightning address from Spark (published to profile)
    @Published private(set) var sparkLightningAddress: String?

    init(state: WalletConnectState, publicKey: PublicKey, appState: AppState) {
        self.connect_state = state
        self.previous_state = .none
        self.publicKey = publicKey
        self.appState = appState
    }

    init(publicKey: PublicKey, appState: AppState) {
        self.publicKey = publicKey
        self.appState = appState
        print("🔧 WalletModel.init: useSparkBackend=\(Self.useSparkBackend), pubkey=\(publicKey.hex.prefix(8))...")
        if Self.useSparkBackend {
            self.previous_state = .none
            self.connect_state = .none

            // Check if this user previously connected a Spark wallet
            let udKey = "spark_wallet_\(publicKey.hex)"
            let hasSparkWallet = UserDefaults.standard.bool(forKey: udKey)
            #if DEBUG
            print("🔧 WalletModel.init: UserDefaults key='\(udKey)' hasSparkWallet=\(hasSparkWallet)")
            #endif

            // Also check if the storage directory exists (belt and suspenders)
            let dirName = "spark_\(String(publicKey.hex.prefix(16)))"
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let sparkDir = documentsDir.appendingPathComponent(dirName)
            let dirExists = FileManager.default.fileExists(atPath: sparkDir.path)
            #if DEBUG
            print("🔧 WalletModel.init: sparkDir exists=\(dirExists)")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: documentsDir.path) {
                let sparkDirs = contents.filter { $0.hasPrefix("spark_") }
                print("🔧 WalletModel.init: All spark dirs on disk: \(sparkDirs)")
            }
            let keypairAvailable = appState.privateKeySecureStorage.keypair(for: publicKey) != nil
            print("🔧 WalletModel.init: keypair available in Keychain=\(keypairAvailable)")
            #endif

            if hasSparkWallet || dirExists {
                #if DEBUG
                print("🔧 WalletModel.init: Attempting Spark reconnection...")
                #endif
                appState.isAutoConnectingWallet = true
                let pubKey = publicKey
                Task { [weak self] in
                    defer {
                        Task { @MainActor in
                            appState.isAutoConnectingWallet = false
                        }
                    }
                    guard let self else { return }
                    do {
                        guard let keypair = appState.privateKeySecureStorage.keypair(for: pubKey) else {
                            print("⚠️ Spark reconnect: No keypair in Keychain")
                            return
                        }
                        try await self.connectSpark(
                            privateKeyHex: keypair.privateKey.hex,
                            apiKey: breezSdkApiKey,
                            lnurlDomain: nil
                        )
                        print("✅ Spark wallet reconnected on launch")
                    } catch {
                        print("⚠️ Spark wallet reconnect failed: \(error)")
                    }
                }
            } else {
                print("🔧 WalletModel.init: No previous Spark wallet found, showing onboarding")
            }
        } else if let nwc = nostrWalletConnectSecureStorage.nostrWalletConnectURL(for: publicKey) {
            self.previous_state = .existing(nwc)
            self.connect_state = .existing(nwc)
            print("setting to existing, \(publicKey)")
            self.nwcClient = try? NWCClient(walletConnectURL: nwc)
        } else {
            print("setting to none, \(publicKey)")
            self.previous_state = .none
            self.connect_state = .none
        }
    }

    func cancel() {
        self.connect_state = previous_state
        self.objectWillChange.send()
    }

    func disconnect() {
        // Capture the lud16 before clearing state so we can notify listeners
        let lud16: String?
        switch connect_state {
        case .existing(let nwc):
            lud16 = nwc.lud16
        case .spark(let address):
            lud16 = address
        default:
            lud16 = nil
        }

        // Disconnect Spark service
        if let spark = sparkService {
            Task { await spark.disconnect() }
        }
        sparkService = nil
        sparkLightningAddress = nil
        UserDefaults.standard.removeObject(forKey: "spark_wallet_\(publicKey.hex)")

        // Disconnect NWC client
        if let client = nwcClient {
            Task {
                await client.disconnect()
            }
        }
        nwcClient = nil
        
        self.nostrWalletConnectSecureStorage.delete(for: publicKey)
        self.connect_state = .none
        self.previous_state = .none
        
        // Reset wallet data
        resetWalletData()

        // Notify listeners so the lightning address can be removed from the profile
        notify(.detached_wallet(lud16))
    }

    func new(_ nwc: WalletConnectURL) {
        self.connect_state = .new(nwc)
    }

    func connect(_ nwc: WalletConnectURL) {
        self.nostrWalletConnectSecureStorage.store(publicKey: publicKey, walletConnectURL: nwc)
        notify(.attached_wallet(nwc))
        self.connect_state = .existing(nwc)
        self.previous_state = .existing(nwc)
        
        // Create NWC client (Option C - created once, reused for all requests)
        do {
            self.nwcClient = try NWCClient(walletConnectURL: nwc)
            print("✅ WalletModel: NWC client created")
        } catch {
            print("❌ WalletModel: Failed to create NWC client: \(error)")
        }

        // Load wallet data after connecting
        Task {
            await loadWalletData()
        }
    }

    // MARK: - Spark Connection

    /// Initialize and connect the Spark wallet from a Nostr private key
    func connectSpark(privateKeyHex: String, apiKey: String, lnurlDomain: String? = nil) async throws {
        let service = SparkWalletService()
        try await service.initialize(
            nostrPrivateKeyHex: privateKeyHex,
            publicKeyHex: publicKey.hex,
            apiKey: apiKey,
            lnurlDomain: lnurlDomain
        )
        self.sparkService = service
        service.delegate = self

        // Register Lightning address
        // First check if this wallet already has one, then try to register if not
        var lud16: String?
        do {
            lud16 = try await service.getLightningAddress()
            if lud16 == nil {
                // No existing address — register one.
                // Use the wallet's own identity pubkey (from getInfo) to generate a unique username
                // that won't collide with other wallets derived from the same Nostr key.
                let identityPubkey = try await service.getIdentityPubkey()
                let username = String(identityPubkey.prefix(16))
                do {
                    lud16 = try await service.registerLightningAddress(username: username)
                    print("⚡ Spark: Registered Lightning address: \(lud16 ?? "nil")")
                } catch {
                    print("⚠️ Spark: Lightning address registration failed: \(error)")
                }
            } else {
                print("⚡ Spark: Existing Lightning address: \(lud16 ?? "nil")")
            }
        } catch {
            print("⚠️ Spark: Lightning address setup failed: \(error)")
        }

        await MainActor.run {
            self.sparkLightningAddress = lud16
            self.connect_state = .spark(lud16: lud16)
            self.previous_state = self.connect_state
            // Persist that this user has a Spark wallet so we reconnect on next launch
            UserDefaults.standard.set(true, forKey: "spark_wallet_\(self.publicKey.hex)")
        }

        // Notify so ContentView updates the profile lud16
        if let lud16 {
            notify(.spark_wallet_attached(lud16))
        }

        // Load wallet data
        await loadWalletData()
    }

    // MARK: - Wallet Data Management

    /// Loads wallet balance and transactions using the NWC client
    func loadWalletData() async {
        // Guard against concurrent loads — if already loading, skip
        guard !isLoading else {
            return
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            if Self.useSparkBackend, let spark = sparkService {
                try await loadWithSpark(spark)
            } else {
                // Ensure we have an NWC client
                guard let client = nwcClient ?? createClientIfNeeded() else {
                    print("❌ Wallet: No wallet connected - state: \(connect_state)")
                    throw WalletError.noWalletConnected
                }
                try await loadWithClient(client)
            }

        } catch is CancellationError {
            print("⚠️ Wallet: Task cancelled, not showing error to user")
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.balance = nil
                self.transactions = nil
                self.isLoading = false
                self.error = "Failed to load wallet data: \(error.localizedDescription)"
            }
        }
    }
    
    /// Internal method to load data using a specific client.
    /// Fetches balance and transactions in parallel, shows transactions
    /// immediately after conversion, then enriches in the background.
    private func loadWithClient(_ client: NWCClient) async throws {
        // Connect to relay (reuses existing connection if already connected)
        print("📊 Wallet: Connecting to relay...")
        try await client.connect()
        
        // Fetch balance and transactions in parallel — they're independent NWC requests
        print("📊 Wallet: Loading balance + transactions in parallel...")
        async let balanceTask = client.getBalance()
        async let transactionsTask = client.listTransactions(limit: 50)
        
        // Await balance — update UI as soon as it arrives
        do {
            let balance = try await balanceTask
            print("✅ Wallet: Balance loaded: \(balance)")
            await MainActor.run { self.balance = balance }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("⚠️ Wallet: Balance failed: \(error)")
            // Continue — transactions may still succeed
        }
        
        // Await transactions
        do {
            let nwcTransactions = try await transactionsTask
            let transactions = nwcTransactions.map { NWCClient.convertToWalletTransaction($0) }
            print("✅ Wallet: Transactions loaded: \(transactions.count)")
            
            // Show transactions immediately (before enrichment) so the list renders fast
            await MainActor.run {
                self.transactions = transactions
                self.isLoading = false
                // Kick off metadata fetch right away for any pubkeys already known from Strategy A
                self.fetchMissingProfileMetadata(for: transactions)
            }
            
            // Enrich in the background with zap receipt matching (Strategy B)
            let enrichedTransactions = await MainActor.run {
                enrichTransactionsWithZapReceipts(transactions)
            }
            
            // Only update if enrichment actually changed something
            let didEnrich = enrichedTransactions.contains(where: { enriched in
                transactions.first(where: { $0.id == enriched.id })?.isZap != enriched.isZap
            })
            
            if didEnrich {
                await MainActor.run {
                    self.transactions = enrichedTransactions
                    // Fetch metadata for any newly-discovered counterparty pubkeys
                    self.fetchMissingProfileMetadata(for: enrichedTransactions)
                }
            }
        } catch is CancellationError {
            print("⚠️ Wallet: Task cancelled during transaction load")
            await MainActor.run { self.isLoading = false }
            return
        } catch {
            // If transactions fail but balance succeeded, show balance with empty transactions
            print("⚠️ Wallet: Transactions failed but balance succeeded: \(error)")
            await MainActor.run {
                self.transactions = []
                self.isLoading = false
            }
        }
    }

    /// Loads wallet data using the Spark service
    private func loadWithSpark(_ spark: SparkWalletService) async throws {
        // Balance
        do {
            let balanceMillisats = try await spark.getBalanceMillisats()
            print("✅ Spark: Balance loaded: \(balanceMillisats)")
            await MainActor.run { self.balance = balanceMillisats }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("⚠️ Spark: Balance failed: \(error)")
        }

        // Transactions
        do {
            let transactions = try await spark.listPayments(limit: 50)
            print("✅ Spark: Transactions loaded: \(transactions.count)")

            await MainActor.run {
                self.transactions = transactions
                self.isLoading = false
                self.fetchMissingProfileMetadata(for: transactions)
            }

            // Enrich with zap receipts (same logic as NWC path)
            let enriched = await MainActor.run {
                enrichTransactionsWithZapReceipts(transactions)
            }
            let didEnrich = enriched.contains(where: { e in
                transactions.first(where: { $0.id == e.id })?.isZap != e.isZap
            })
            if didEnrich {
                await MainActor.run {
                    self.transactions = enriched
                    self.fetchMissingProfileMetadata(for: enriched)
                }
            }
        } catch is CancellationError {
            print("⚠️ Spark: Task cancelled during transaction load")
            await MainActor.run { self.isLoading = false }
        } catch {
            print("⚠️ Spark: Transactions failed: \(error)")
            await MainActor.run {
                self.transactions = []
                self.isLoading = false
            }
        }
    }

    /// Refreshes wallet data
    func refreshWalletData() async {
        await loadWalletData()
    }

    /// Refreshes only the wallet balance without fetching transactions.
    /// Use this from streaming/polling contexts that only need the balance number.
    func refreshBalanceOnly() async {
        if Self.useSparkBackend, let spark = sparkService {
            do {
                let newBalance = try await spark.getBalanceMillisats()
                await MainActor.run { self.balance = newBalance }
            } catch {
                print("⚠️ Spark: Balance-only refresh failed: \(error)")
            }
            return
        }

        // NWC fallback
        guard let client = nwcClient ?? createClientIfNeeded() else {
            print("❌ Wallet: No NWC client for balance refresh")
            return
        }

        do {
            try await client.connect()
            let newBalance = try await client.getBalance()
            await MainActor.run { self.balance = newBalance }
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch {
            print("⚠️ Wallet: Balance-only refresh failed: \(error)")
        }
    }

    /// Creates an NWC client from the existing connection if one isn't set yet.
    private func createClientIfNeeded() -> NWCClient? {
        guard case .existing(let nwc) = connect_state,
              let newClient = try? NWCClient(walletConnectURL: nwc) else {
            return nil
        }
        self.nwcClient = newClient
        return newClient
    }

    /// Refreshes only transactions (useful for pagination or filtering)
    func refreshTransactions(limit: Int = 50) async {
        guard let client = nwcClient ?? createClientIfNeeded() else {
            print("❌ Wallet: No NWC client for transaction refresh")
            return
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            try await client.connect()
            let nwcTransactions = try await client.listTransactions(limit: limit)
            let transactions = nwcTransactions.map { NWCClient.convertToWalletTransaction($0) }

            // Show immediately before enrichment
            await MainActor.run {
                self.transactions = transactions
                self.isLoading = false
                self.fetchMissingProfileMetadata(for: transactions)
            }

            // Enrich in background
            let enrichedTransactions = await MainActor.run {
                enrichTransactionsWithZapReceipts(transactions)
            }

            let didEnrich = enrichedTransactions.contains(where: { enriched in
                transactions.first(where: { $0.id == enriched.id })?.isZap != enriched.isZap
            })

            if didEnrich {
                await MainActor.run {
                    self.transactions = enrichedTransactions
                    self.fetchMissingProfileMetadata(for: enrichedTransactions)
                }
            }
        } catch is CancellationError {
            print("⚠️ Wallet: Transaction refresh cancelled")
            await MainActor.run { self.isLoading = false }
        } catch {
            await MainActor.run {
                self.error = "Failed to refresh transactions: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    /// Resets wallet data to loading state
    func resetWalletData() {
        balance = nil
        transactions = nil
        isLoading = false
        error = nil
    }
    
    // MARK: - Zap Enrichment
    
    /// Enriches transactions that weren't already enriched by description parsing (Strategy A).
    /// Falls back to matching against AppState zap receipts by bolt11 invoice (Strategy B).
    @MainActor
    private func enrichTransactionsWithZapReceipts(_ transactions: [WalletTransaction]) -> [WalletTransaction] {
        let unenriched = transactions.filter { !$0.isZap && $0.bolt11Invoice != nil }
        guard !unenriched.isEmpty else { return transactions }
        
        // Build bolt11 → receipt index from global zapReceipts + per-stream zapReceiptEvents
        var receiptsByBolt11: [String: LightningZapsReceiptEvent] = [:]
        for receipt in appState.zapReceipts {
            if let bolt11 = receipt.bolt11 {
                receiptsByBolt11[bolt11.lowercased()] = receipt
            }
        }
        for (_, receipts) in appState.zapReceiptEvents {
            for receipt in receipts {
                if let bolt11 = receipt.bolt11 {
                    receiptsByBolt11[bolt11.lowercased()] = receipt
                }
            }
        }
        
        return transactions.map { tx in
            guard !tx.isZap,
                  let bolt11 = tx.bolt11Invoice?.lowercased(),
                  let receipt = receiptsByBolt11[bolt11] else {
                return tx
            }
            
            let zapRequest = receipt.description
            return WalletTransaction(
                id: tx.id, type: tx.type, amount: tx.amount,
                description: tx.description, createdAt: tx.createdAt,
                paymentHash: tx.paymentHash, preimage: tx.preimage,
                feesPaid: tx.feesPaid, settledAt: tx.settledAt, expiresAt: tx.expiresAt,
                senderPubkey: receipt.zapSenderPubkey ?? zapRequest?.pubkey,
                recipientPubkey: receipt.recipientPubkey,
                zapMessage: zapRequest?.content,
                zappedEventId: receipt.eventId,
                zappedEventCoordinate: receipt.eventCoordinate,
                bolt11Invoice: tx.bolt11Invoice,
                isZap: true
            )
        }
    }
    
    /// Fetches profile metadata for counterparty pubkeys not yet in cache.
    @MainActor
    private func fetchMissingProfileMetadata(for transactions: [WalletTransaction]) {
        let pubkeys = Set(transactions.compactMap { $0.counterpartyPubkey })
        let missingPubkeys = pubkeys.filter { appState.metadataEvents[$0] == nil }
        if !missingPubkeys.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(Array(missingPubkeys))
        }
    }
    
    // MARK: - NWC Client Access
    
    /// Gets the NWC client for external use (e.g., LightningPaymentService)
    func getNWCClient() -> NWCClient? {
        return nwcClient
    }
    
    /// Pays a Lightning invoice using the Spark service or NWC client
    func payInvoice(_ bolt11: String) async throws -> String? {
        if Self.useSparkBackend {
            guard let spark = sparkService else {
                throw WalletError.noWalletConnected
            }
            return try await spark.payInvoice(bolt11)
        }

        guard let client = nwcClient else {
            throw WalletError.noWalletConnected
        }
        
        try await client.connect()
        return try await client.payInvoice(bolt11)
    }
    
    /// Creates a Lightning invoice for receiving payments
    /// - Parameters:
    ///   - amountSats: Amount in satoshis
    ///   - description: Optional description for the invoice
    /// - Returns: Tuple containing the bolt11 invoice string and payment hash
    func makeInvoice(amountSats: Int, description: String? = nil) async throws -> (invoice: String, paymentHash: String) {
        if Self.useSparkBackend {
            guard let spark = sparkService else {
                throw WalletError.noWalletConnected
            }
            return try await spark.makeInvoice(amountSats: amountSats, description: description)
        }

        guard let client = nwcClient else {
            throw WalletError.noWalletConnected
        }
        
        try await client.connect()
        // NWC uses millisats, so convert sats to millisats
        let amountMillisats = amountSats * 1000
        return try await client.makeInvoice(amount: amountMillisats, description: description)
    }
}

// MARK: - SparkWalletDelegate

extension WalletModel: SparkWalletDelegate {
    func sparkWalletDidSync() {
        Task {
            await loadWalletData()
        }
    }

    func sparkWalletPaymentSucceeded(_ payment: BreezSdkSpark.Payment) {
        Task {
            await loadWalletData()
        }
    }

    func sparkWalletPaymentFailed(_ payment: BreezSdkSpark.Payment) {
        Task {
            await loadWalletData()
        }
    }

    func sparkWalletLightningAddressChanged(_ address: BreezSdkSpark.LightningAddressInfo?) {
        Task { @MainActor in
            self.sparkLightningAddress = address?.lightningAddress
        }
    }
}
