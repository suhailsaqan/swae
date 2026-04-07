import Combine
import SwiftUI

// MARK: - Zap Stream Core Payment ViewModel

@MainActor
class ZapStreamCorePaymentViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isLoadingHistory = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var accountBalance: Double?
    @Published var currentInvoice: ZapStreamCoreInvoice?
    @Published var paymentHistory: [ZapStreamCorePaymentHistoryItem] = []
    @Published var paymentSuccessful = false

    // MARK: - NWC Auto-Pay State
    @Published var isAutoPayingWithWallet = false
    @Published var autoPayError: String? = nil
    @Published var walletConnected: Bool = false

    private var apiClient: ZapStreamCoreApiClient?
    private var cancellables = Set<AnyCancellable>()
    private var statusCheckTimer: Timer?
    private var currentAppState: AppState?
    private var monitoringInvoiceId: String?
    private var autoPayTask: Task<Void, Never>?

    func loadAccountInfo(appState: AppState) {
        if apiClient == nil {
            setupApiClient()
        }
        guard let apiClient = apiClient else { return }

        isLoading = true

        apiClient.getAccountInfo(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] accountInfo in
                    self?.accountBalance = Double(accountInfo.balance)
                }
            )
            .store(in: &cancellables)
    }

    func createInvoice(amount: Double, appState: AppState) {
        if apiClient == nil {
            setupApiClient()
        }
        guard let apiClient = apiClient else { return }

        isLoading = true
        paymentSuccessful = false  // Reset payment success flag
        monitoringInvoiceId = nil  // Reset monitoring invoice ID

        apiClient.createInvoice(
            appState: appState,
            amount: amount,
            currency: "sats",
            description: "Account top-up"
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.handleError(error)
                }
            },
            receiveValue: { [weak self] invoice in
                self?.currentInvoice = invoice
                self?.monitoringInvoiceId = invoice.id
                self?.startAutomaticStatusCheck(appState: appState)
            }
        )
        .store(in: &cancellables)
    }

    func checkInvoiceStatus(invoiceId: String, appState: AppState, completion: @escaping () -> Void)
    {
        guard let apiClient = apiClient else {
            completion()
            return
        }

        // Check recent account history to see if the payment was processed
        apiClient.getAccountHistory(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("Error checking invoice status: \(error)")
                    }
                    completion()
                },
                receiveValue: { [weak self] historyItems in
                    guard let self = self, let currentInvoice = self.currentInvoice else {
                        completion()
                        return
                    }

                    // Look for credit transactions that match this specific invoice
                    let matchingPayments = historyItems.filter { item in
                        let isCredit = item.type == 0
                        let amountMatches = item.amount == currentInvoice.amount
                        // Add 5 second tolerance to account for timing differences between invoice creation and payment processing
                        let invoiceCreationTime = currentInvoice.createdAt.timeIntervalSince1970
                        let paymentTime = Double(item.created)
                        let createdAfterInvoice = paymentTime > (invoiceCreationTime - 5.0)  // Allow 5 seconds before invoice creation

                        return isCredit && amountMatches && createdAfterInvoice
                    }

                    // If we find a matching payment, the invoice has been paid
                    if !matchingPayments.isEmpty {
                        // Use the timestamp from the most recent matching payment
                        let mostRecentPayment = matchingPayments.max { $0.created < $1.created }!
                        let paidAt = Date(timeIntervalSince1970: Double(mostRecentPayment.created))

                        // Create an updated invoice with paid status
                        let updatedInvoice = ZapStreamCoreInvoice(
                            id: currentInvoice.id,
                            amount: currentInvoice.amount,
                            currency: currentInvoice.currency,
                            status: "paid",
                            paymentRequest: currentInvoice.paymentRequest,
                            paymentHash: currentInvoice.paymentHash,
                            createdAt: currentInvoice.createdAt,
                            expiresAt: currentInvoice.expiresAt,
                            paidAt: paidAt
                        )
                        self.currentInvoice = updatedInvoice

                        // Set payment successful flag
                        self.paymentSuccessful = true

                        // Stop automatic status checking since invoice is now paid
                        self.stopAutomaticStatusCheck()

                        // Also refresh account info to update balance
                        self.loadAccountInfo(appState: appState)
                    } else {
                        print("❌ No matching payments found for invoice \(currentInvoice.id)")
                    }

                    completion()
                }
            )
            .store(in: &cancellables)
    }

    func loadPaymentHistory(appState: AppState) {
        if apiClient == nil {
            setupApiClient()
        }
        guard let apiClient = apiClient else { return }

        isLoadingHistory = true

        apiClient.getAccountHistory(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingHistory = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] historyItems in
                    // Convert history items to payment history items
                    let paymentHistoryItems = historyItems.map { item in
                        ZapStreamCorePaymentHistoryItem(
                            id: "\(item.created)_\(item.type)_\(Int(item.amount))",
                            amount: item.amount,
                            currency: "sats",
                            status: item.type == 0 ? "credit" : "debit",
                            paymentRequest: "",
                            paymentHash: "",
                            createdAt: Date(timeIntervalSince1970: Double(item.created)),
                            paidAt: Date(timeIntervalSince1970: Double(item.created)),
                            description: item.desc
                        )
                    }
                    self?.paymentHistory = paymentHistoryItems
                }
            )
            .store(in: &cancellables)
    }

    private func setupApiClient() {
        let config = ZapStreamCoreConfig()
        apiClient = ZapStreamCoreApiClient(config: config)
    }

    // MARK: - NWC Auto-Pay

    /// Check wallet connection status on appear
    func checkWalletStatus(appState: AppState) {
        if let wallet = appState.wallet {
            switch wallet.connect_state {
            case .existing, .spark:
                walletConnected = true
            default:
                walletConnected = false
            }
        } else {
            walletConnected = false
        }
    }

    /// Attempt to pay the invoice automatically using the user's NWC wallet
    func attemptAutoPayWithWallet(invoice: ZapStreamCoreInvoice, appState: AppState) {
        guard let walletModel = appState.wallet else { return }
        switch walletModel.connect_state {
        case .existing, .spark:
            break
        default:
            return
        }

        // Cancel any previous auto-pay task
        autoPayTask?.cancel()

        isAutoPayingWithWallet = true
        autoPayError = nil

        autoPayTask = Task { [weak self] in
            do {
                let _ = try await walletModel.payInvoice(invoice.paymentRequest)
                guard !Task.isCancelled else { return }
                self?.isAutoPayingWithWallet = false
                self?.paymentSuccessful = true
                self?.stopAutomaticStatusCheck()
                self?.loadAccountInfo(appState: appState)
            } catch {
                guard !Task.isCancelled else { return }
                self?.isAutoPayingWithWallet = false
                self?.autoPayError = error.localizedDescription
            }
        }
    }

    /// Cancel any in-progress auto-pay task
    func cancelAutoPay() {
        autoPayTask?.cancel()
        autoPayTask = nil
        isAutoPayingWithWallet = false
    }

    // MARK: - Automatic Status Checking

    func startAutomaticStatusCheck(appState: AppState) {
        currentAppState = appState
        stopAutomaticStatusCheck()  // Stop any existing timer

        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) {
            [weak self] _ in
            guard let self = self, let appState = self.currentAppState else {
                return
            }

            // Only check status if we have an active invoice and are monitoring it
            if let invoice = self.currentInvoice,
                let monitoringId = self.monitoringInvoiceId,
                invoice.id == monitoringId,
                invoice.status == "pending"
            {
                self.checkInvoiceStatus(invoiceId: invoice.id, appState: appState) {
                }
            } else {
            }
        }

        // Ensure timer runs on main run loop
        RunLoop.main.add(statusCheckTimer!, forMode: .common)
    }

    func stopAutomaticStatusCheck() {
        if statusCheckTimer != nil {
            statusCheckTimer?.invalidate()
            statusCheckTimer = nil
            currentAppState = nil
            monitoringInvoiceId = nil
        }
    }

    private func startStatusPolling(invoiceId: String, appState: AppState) {
        // Stop any existing timer
        statusCheckTimer?.invalidate()

        // Start polling for invoice status
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            self?.checkInvoiceStatusPolling(invoiceId: invoiceId, appState: appState)
        }
    }

    private func checkInvoiceStatusPolling(invoiceId: String, appState: AppState) {
        guard let apiClient = apiClient else { return }

        apiClient.getInvoiceStatus(appState: appState, invoiceId: invoiceId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in
                    // Ignore errors during polling
                },
                receiveValue: { [weak self] status in
                    if status.paid {
                        // Invoice is paid, stop polling and refresh account info
                        self?.statusCheckTimer?.invalidate()
                        self?.statusCheckTimer = nil
                        self?.loadAccountInfo(appState: appState)

                        // Update the current invoice status
                        if var invoice = self?.currentInvoice {
                            // Create a new invoice with updated status
                            let updatedInvoice = ZapStreamCoreInvoice(
                                id: invoice.id,
                                amount: invoice.amount,
                                currency: invoice.currency,
                                status: "paid",
                                paymentRequest: invoice.paymentRequest,
                                paymentHash: invoice.paymentHash,
                                createdAt: invoice.createdAt,
                                expiresAt: invoice.expiresAt,
                                paidAt: status.paidAt
                            )
                            self?.currentInvoice = updatedInvoice
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    deinit {
        statusCheckTimer?.invalidate()
        autoPayTask?.cancel()
    }
}

// MARK: - Enhanced Payment ViewModel with AppState

@MainActor
class ZapStreamCorePaymentViewModelWithAppState: ObservableObject {
    @Published var isLoading = false
    @Published var isLoadingHistory = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var accountBalance: Double?
    @Published var currentInvoice: ZapStreamCoreInvoice?
    @Published var paymentHistory: [ZapStreamCorePaymentHistoryItem] = []

    private var apiClient: ZapStreamCoreApiClient?
    private var cancellables = Set<AnyCancellable>()
    private var statusCheckTimer: Timer?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        setupApiClient()
    }

    func loadAccountInfo() {
        guard let apiClient = apiClient else { return }

        isLoading = true

        apiClient.getAccountInfo(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] accountInfo in
                    self?.accountBalance = Double(accountInfo.balance)
                }
            )
            .store(in: &cancellables)
    }

    func createInvoice(amount: Double) {
        guard let apiClient = apiClient else { return }

        isLoading = true

        apiClient.createInvoice(
            appState: appState,
            amount: amount,
            currency: "sats",
            description: "Account top-up"
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.handleError(error)
                }
            },
            receiveValue: { [weak self] invoice in
                self?.currentInvoice = invoice
                // Note: Using startAutomaticStatusCheck instead of startStatusPolling
            }
        )
        .store(in: &cancellables)
    }

    func checkInvoiceStatus(invoiceId: String, completion: @escaping () -> Void) {
        guard let apiClient = apiClient else {
            completion()
            return
        }

        apiClient.getInvoiceStatus(appState: appState, invoiceId: invoiceId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in
                    completion()
                },
                receiveValue: { [weak self] status in
                    if status.paid {
                        // Invoice is paid, refresh account info
                        self?.loadAccountInfo()

                        // Update the current invoice status
                        if var invoice = self?.currentInvoice {
                            let updatedInvoice = ZapStreamCoreInvoice(
                                id: invoice.id,
                                amount: invoice.amount,
                                currency: invoice.currency,
                                status: "paid",
                                paymentRequest: invoice.paymentRequest,
                                paymentHash: invoice.paymentHash,
                                createdAt: invoice.createdAt,
                                expiresAt: invoice.expiresAt,
                                paidAt: status.paidAt
                            )
                            self?.currentInvoice = updatedInvoice
                        }
                    }
                    completion()
                }
            )
            .store(in: &cancellables)
    }

    func loadPaymentHistory() {
        guard let apiClient = apiClient else { return }

        isLoadingHistory = true

        apiClient.getPaymentHistory(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingHistory = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] payments in
                    self?.paymentHistory = payments
                }
            )
            .store(in: &cancellables)
    }

    private func setupApiClient() {
        let config = ZapStreamCoreConfig()
        apiClient = ZapStreamCoreApiClient(config: config)
    }

    private func startStatusPolling(invoiceId: String) {
        // Stop any existing timer
        statusCheckTimer?.invalidate()

        // Start polling for invoice status
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            self?.checkInvoiceStatusPolling(invoiceId: invoiceId)
        }
    }

    private func checkInvoiceStatusPolling(invoiceId: String) {
        guard let apiClient = apiClient else { return }

        apiClient.getInvoiceStatus(appState: appState, invoiceId: invoiceId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in
                    // Ignore errors during polling
                },
                receiveValue: { [weak self] status in
                    if status.paid {
                        // Invoice is paid, stop polling and refresh account info
                        self?.statusCheckTimer?.invalidate()
                        self?.statusCheckTimer = nil
                        self?.loadAccountInfo()

                        // Update the current invoice status
                        if var invoice = self?.currentInvoice {
                            let updatedInvoice = ZapStreamCoreInvoice(
                                id: invoice.id,
                                amount: invoice.amount,
                                currency: invoice.currency,
                                status: "paid",
                                paymentRequest: invoice.paymentRequest,
                                paymentHash: invoice.paymentHash,
                                createdAt: invoice.createdAt,
                                expiresAt: invoice.expiresAt,
                                paidAt: status.paidAt
                            )
                            self?.currentInvoice = updatedInvoice
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    deinit {
        statusCheckTimer?.invalidate()
    }
}
