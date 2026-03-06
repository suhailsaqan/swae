import Combine
import SwiftUI

// MARK: - Zap Stream Core Payment View

struct ZapStreamCorePaymentView: View {
    @StateObject private var viewModel = ZapStreamCorePaymentViewModel()
    @EnvironmentObject private var model: Model
    @Environment(\.dismiss) private var dismiss

    @State private var amountString: String = ""
    @State private var isShowingPaymentHistory = false

    // Animation state
    @State private var qrScale: CGFloat = 0.8
    @State private var qrOpacity: Double = 0
    @State private var successScale: CGFloat = 0.5
    @State private var successOpacity: Double = 0

    private var displayAmount: String {
        if amountString.isEmpty { return "0" }
        if let number = Int(amountString) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: number)) ?? amountString
        }
        return amountString
    }

    private var amountValue: Int {
        Int(amountString) ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.paymentSuccessful {
                successView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let invoice = viewModel.currentInvoice {
                invoiceDisplayView(invoice: invoice)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                amountInputView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentInvoice != nil)
        .animation(.easeInOut(duration: 0.25), value: viewModel.paymentSuccessful)
        .preferredColorScheme(.dark)
        .onAppear {
            if let appState = model.appState {
                viewModel.loadAccountInfo(appState: appState)
                viewModel.checkWalletStatus(appState: appState)
            }
        }
        .onChange(of: viewModel.paymentSuccessful) { success in
            if success {
                model.refreshZapStreamCoreBalance()
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $isShowingPaymentHistory) {
            ZapStreamCorePaymentHistoryView(viewModel: viewModel, model: model)
        }
    }

    // MARK: - Amount Input View

    private var amountInputView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()

                // Payment history
                Button(action: { isShowingPaymentHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Amount display
            VStack(spacing: 8) {
                Text(displayAmount)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.1), value: displayAmount)

                Text("sats")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 40)

            // Balance pill
            if let balance = viewModel.accountBalance {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Balance: \(formatSatsLocal(Int64(balance))) sats")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .padding(.top, 16)
            }

            Spacer()

            // Quick amounts
            quickAmountsRow
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Number pad
            numberPad
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Top Up button
            Button(action: createInvoice) {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Top Up")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(amountValue > 0 ? Color.accentPurple : Color.gray.opacity(0.3))
                )
            }
            .disabled(amountValue == 0 || viewModel.isLoading)
            .animation(.easeInOut(duration: 0.2), value: amountValue > 0)
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
    }

    // MARK: - Quick Amounts

    private let presetAmounts: [Int] = [500, 1000, 5000, 10000]

    private var quickAmountsRow: some View {
        HStack(spacing: 8) {
            ForEach(presetAmounts, id: \.self) { amount in
                Button(action: {
                    amountString = "\(amount)"
                }) {
                    Text(formatSatsLocal(Int64(amount)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(
                            amountValue == amount ? .black : .white
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    amountValue == amount
                                        ? Color.accentPurple
                                        : Color.white.opacity(0.08)
                                )
                        )
                }
            }
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: 12) {
            ForEach(numberPadRows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        numberPadButton(key)
                    }
                }
            }
        }
    }

    private var numberPadRows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"],
        ]
    }

    private func numberPadButton(_ key: String) -> some View {
        Button(action: { handleKeyPress(key) }) {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24, weight: .medium))
                } else {
                    Text(key)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                key.isEmpty ? Color.clear : Color.white.opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(key.isEmpty)
    }

    private func handleKeyPress(_ key: String) {
        withAnimation(.easeInOut(duration: 0.1)) {
            switch key {
            case "⌫":
                if !amountString.isEmpty {
                    amountString.removeLast()
                }
            case "":
                break
            default:
                if amountString.count < 10 {
                    if amountString == "0" {
                        amountString = key
                    } else {
                        amountString += key
                    }
                }
            }
        }
    }

    // MARK: - Invoice Display View

    private func invoiceDisplayView(invoice: ZapStreamCoreInvoice) -> some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()
                Button(action: {
                    viewModel.cancelAutoPay()
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            if viewModel.isAutoPayingWithWallet {
                // Auto-pay in progress
                autoPayInProgressView(invoice: invoice)
            } else if let autoPayError = viewModel.autoPayError {
                // Auto-pay failed — show error with fallback options
                autoPayFailedView(invoice: invoice, error: autoPayError)
            } else {
                // Manual QR flow
                manualInvoiceView(invoice: invoice)
            }

            Spacer()

            // Action buttons
            if viewModel.isAutoPayingWithWallet {
                // Cancel button during auto-pay
                Button(action: {
                    viewModel.cancelAutoPay()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            } else if viewModel.autoPayError != nil {
                // Retry + fallback buttons after auto-pay failure
                VStack(spacing: 12) {
                    if viewModel.walletConnected {
                        Button(action: {
                            if let appState = model.appState {
                                viewModel.attemptAutoPayWithWallet(invoice: invoice, appState: appState)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Try Again with Wallet")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26)
                                    .fill(Color.accentPurple)
                            )
                        }
                    }

                    Button(action: {
                        // Clear error to show QR code
                        viewModel.autoPayError = nil
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 16, weight: .medium))
                            Text("Show Invoice QR")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            } else {
                // Standard manual flow buttons
                VStack(spacing: 12) {
                    // Pay with Wallet button (if wallet connected but showing QR)
                    if viewModel.walletConnected {
                        Button(action: {
                            if let appState = model.appState {
                                viewModel.attemptAutoPayWithWallet(invoice: invoice, appState: appState)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Pay with Wallet")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26)
                                    .fill(Color.accentPurple)
                            )
                        }
                    }

                    Button(action: { copyInvoice(invoice.paymentRequest) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16, weight: .medium))
                            Text("Copy Invoice")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(viewModel.walletConnected ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(viewModel.walletConnected ? Color.clear : Color.accentPurple)
                        )
                        .overlay(
                            viewModel.walletConnected ?
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1) : nil
                        )
                    }

                    ShareLink(item: invoice.paymentRequest) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                            Text("Share")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .onAppear {
            if let appState = model.appState {
                viewModel.startAutomaticStatusCheck(appState: appState)
            }
        }
        .onDisappear {
            viewModel.stopAutomaticStatusCheck()
            viewModel.cancelAutoPay()
        }
    }

    // MARK: - Auto-Pay In Progress View

    private func autoPayInProgressView(invoice: ZapStreamCoreInvoice) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentPurple.opacity(0.15))
                    .frame(width: 100, height: 100)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentPurple))
                    .scaleEffect(1.5)
            }

            VStack(spacing: 8) {
                Text("Paying from your wallet...")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Text("\(formatSatsLocal(Int64(invoice.amount))) sats")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Auto-Pay Failed View

    private func autoPayFailedView(invoice: ZapStreamCoreInvoice, error: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text("Wallet payment failed")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Text("\(formatSatsLocal(Int64(invoice.amount))) sats")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: - Manual Invoice QR View

    private func manualInvoiceView(invoice: ZapStreamCoreInvoice) -> some View {
        VStack(spacing: 24) {
            QRCodeView(string: invoice.paymentRequest.uppercased(), size: 220)
                .padding(16)
                .background(Color.white)
                .cornerRadius(20)
                .shadow(color: Color.accentPurple.opacity(0.3), radius: 20, x: 0, y: 10)
                .scaleEffect(qrScale)
                .opacity(qrOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        qrScale = 1.0
                        qrOpacity = 1.0
                    }
                }

            VStack(spacing: 4) {
                Text("\(formatSatsLocal(Int64(invoice.amount))) sats")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Scan to pay this invoice")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }
            .opacity(qrOpacity)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .scaleEffect(successScale)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.green)
                    .scaleEffect(successScale)
            }
            .opacity(successOpacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    successScale = 1.0
                    successOpacity = 1.0
                }
            }

            Text("Top Up Successful!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .opacity(successOpacity)

            if let invoice = viewModel.currentInvoice {
                Text("\(formatSatsLocal(Int64(invoice.amount))) sats added")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .opacity(successOpacity)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 28).fill(Color.green))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
    }

    // MARK: - Actions

    private func createInvoice() {
        guard amountValue > 0 else { return }
        if let appState = model.appState {
            viewModel.paymentSuccessful = false
            viewModel.createInvoice(amount: Double(amountValue), appState: appState)
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.25)) {
            qrScale = 0.8
            qrOpacity = 0
            viewModel.currentInvoice = nil
            viewModel.stopAutomaticStatusCheck()
        }
    }

    @State private var copied: Bool = false

    private func copyInvoice(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }

    // MARK: - Formatting

    private func formatSatsLocal(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }
}

// MARK: - Invoice View (kept for backward compatibility)

struct ZapStreamCoreInvoiceView: View {
    let invoice: ZapStreamCoreInvoice
    @ObservedObject var viewModel: ZapStreamCorePaymentViewModel
    let model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var isCheckingStatus = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    if viewModel.paymentSuccessful {
                        // Success state
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)

                            Text("Payment Successful!")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            Text("\(Int(invoice.amount)) sats added")
                                .font(.system(size: 17))
                                .foregroundColor(.gray)
                        }
                    } else {
                        // QR Code
                        QRCodeView(string: invoice.paymentRequest.uppercased(), size: 220)
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(20)
                            .shadow(color: Color.accentPurple.opacity(0.3), radius: 20, x: 0, y: 10)

                        VStack(spacing: 4) {
                            Text("\(Int(invoice.amount)) sats")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Scan to pay")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                        }
                    }

                    Spacer()

                    if !viewModel.paymentSuccessful {
                        VStack(spacing: 12) {
                            Button(action: {
                                UIPasteboard.general.string = invoice.paymentRequest
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy Invoice")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 26)
                                        .fill(Color.accentPurple)
                                )
                            }

                            Button(action: { checkInvoiceStatus() }) {
                                HStack(spacing: 8) {
                                    if isCheckingStatus {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Check Status")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 26)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .disabled(isCheckingStatus)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                    } else {
                        Button(action: { dismiss() }) {
                            Text("Done")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(RoundedRectangle(cornerRadius: 28).fill(Color.green))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                    }
                }
            }
            .navigationTitle("Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func checkInvoiceStatus() {
        isCheckingStatus = true
        if let appState = model.appState {
            viewModel.checkInvoiceStatus(invoiceId: invoice.id, appState: appState) {
                isCheckingStatus = false
            }
        }
    }
}

// MARK: - Invoice Detail Row

struct InvoiceDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Payment History View

struct ZapStreamCorePaymentHistoryView: View {
    @ObservedObject var viewModel: ZapStreamCorePaymentViewModel
    let model: Model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoadingHistory {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.paymentHistory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.6))

                        Text("No history yet")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Your top-up history will appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.paymentHistory) { payment in
                                PaymentHistoryRow(payment: payment)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
            .onAppear {
                if let appState = model.appState {
                    viewModel.loadPaymentHistory(appState: appState)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

// MARK: - Payment History Row

struct PaymentHistoryRow: View {
    let payment: ZapStreamCorePaymentHistoryItem

    private var isCredit: Bool {
        payment.status == "credit"
    }

    private var rowColor: Color {
        isCredit ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rowColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: isCredit ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(rowColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(payment.description ?? "Payment")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(DateFormatter.shortDateTime.string(from: payment.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(isCredit ? "+" : "-")\(Int(payment.amount))")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(rowColor)

                Text("sats")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .foregroundColor(.white)
            .cornerRadius(8)
    }

    private var statusColor: Color {
        switch status.lowercased() {
        case "paid", "completed": return .green
        case "pending": return .orange
        case "failed", "expired": return .red
        default: return .gray
        }
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Amount Button (kept for backward compatibility)

struct AmountButton: View {
    let amount: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(Int(amount))")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("sats")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentPurple : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
    }
}

#Preview {
    ZapStreamCorePaymentView()
        .environmentObject(Model())
}
