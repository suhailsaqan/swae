//
//  WalletModel.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//

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

    init(state: WalletConnectState, publicKey: PublicKey, appState: AppState) {
        self.connect_state = state
        self.previous_state = .none
        self.publicKey = publicKey
        self.appState = appState
    }

    init(publicKey: PublicKey, appState: AppState) {
        self.publicKey = publicKey
        self.appState = appState
        if let nwc = nostrWalletConnectSecureStorage.nostrWalletConnectURL(for: publicKey) {
            self.previous_state = .existing(nwc)
            self.connect_state = .existing(nwc)
            print("setting to existing, \(publicKey)")
            // Create NWC client for existing connection
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
        if case .existing(let nwc) = connect_state {
            lud16 = nwc.lud16
        } else {
            lud16 = nil
        }

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

    // MARK: - Wallet Data Management

    /// Loads wallet balance and transactions using the NWC client
    func loadWalletData() async {
        // Guard against concurrent loads — if already loading, skip
        guard !isLoading else {
            print("⚠️ Wallet: Already loading, skipping duplicate call")
            return
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            // Ensure we have an NWC client
            guard let client = nwcClient else {
                // Try to create one from existing connection
                guard case .existing(let nwc) = connect_state else {
                    print("❌ Wallet: No wallet connected - state: \(connect_state)")
                    throw WalletError.noWalletConnected
                }
                
                // Create client if missing
                let newClient = try NWCClient(walletConnectURL: nwc)
                await MainActor.run {
                    self.nwcClient = newClient
                }
                
                // Use the new client
                try await loadWithClient(newClient)
                return
            }
            
            try await loadWithClient(client)

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

    /// Refreshes wallet data
    func refreshWalletData() async {
        await loadWalletData()
    }

    /// Refreshes only transactions (useful for pagination or filtering)
    func refreshTransactions(limit: Int = 50) async {
        guard let client = nwcClient else {
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
    
    /// Pays a Lightning invoice using the NWC client
    func payInvoice(_ bolt11: String) async throws -> String? {
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
        guard let client = nwcClient else {
            throw WalletError.noWalletConnected
        }
        
        try await client.connect()
        // NWC uses millisats, so convert sats to millisats
        let amountMillisats = amountSats * 1000
        return try await client.makeInvoice(amount: amountMillisats, description: description)
    }
}
