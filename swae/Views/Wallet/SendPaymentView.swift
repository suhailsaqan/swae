//
//  SendPaymentView.swift
//  swae
//
//  View for sending Lightning payments with confirmation
//

import SwiftUI
import SwiftData
import NostrSDK
import CodeScanner

struct SendPaymentView: View {
    @ObservedObject var walletModel: WalletModel
    @Environment(\.dismiss) private var dismiss
    
    // Input state
    @State private var invoiceText: String = ""
    @State private var showScanner: Bool = false
    
    // Confirmation state
    @State private var showConfirmation: Bool = false
    @State private var parsedInvoice: ParsedInvoice? = nil
    @State private var preparedPayment: SparkWalletService.PreparedPayment? = nil
    @State private var feeSats: UInt64 = 0
    @State private var isPreparing: Bool = false
    
    // Payment state
    @State private var isProcessing: Bool = false
    @State private var error: String? = nil
    @State private var paymentSuccess: Bool = false
    @State private var preimage: String? = nil
    
    // Animation state
    @State private var successScale: CGFloat = 0.5
    @State private var successOpacity: Double = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if paymentSuccess {
                    successView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if showConfirmation, let invoice = parsedInvoice {
                    confirmationView(invoice: invoice)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    inputView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showConfirmation)
            .animation(.easeInOut(duration: 0.25), value: paymentSuccess)
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: handleBack) {
                        if paymentSuccess || showConfirmation {
                            Image(systemName: "chevron.left")
                        } else {
                            Text("Cancel")
                        }
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                invoiceScannerView
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func handleBack() {
        if paymentSuccess {
            dismiss()
        } else if showConfirmation {
            withAnimation(.easeInOut(duration: 0.25)) {
                showConfirmation = false
                parsedInvoice = nil
                preparedPayment = nil
                feeSats = 0
                error = nil
            }
        } else {
            dismiss()
        }
    }
    
    // MARK: - Input View
    
    private var inputView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Send Payment")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.top, 20)
                
                // Balance display
                if let balance = walletModel.balance {
                    HStack {
                        Text("Available:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(formatBalance(balance)) sats")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
                }
                
                // Input methods
                VStack(spacing: 16) {
                    // Scan QR button
                    Button(action: { showScanner = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan QR Code")
                                    .font(.headline)
                                Text("Use camera to scan invoice")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentPurple.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.accentPurple.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Paste button
                    Button(action: pasteFromClipboard) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paste Invoice")
                                    .font(.headline)
                                Text("Paste from clipboard")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                
                // Divider
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                    Text("or enter manually").font(.caption).foregroundColor(.secondary)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                }
                
                // Manual invoice input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lightning Invoice")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $invoiceText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 80)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
                
                // Error message
                if let error = error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                // Review button
                Button(action: reviewInvoice) {
                    HStack {
                        if isPreparing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Preparing...")
                        } else {
                            Image(systemName: "eye.fill")
                            Text("Review Invoice")
                        }
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(canReview && !isPreparing ? Color.accentPurple : Color.gray))
                }
                .disabled(!canReview || isPreparing)
                .animation(.easeInOut(duration: 0.2), value: canReview)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    private var canReview: Bool {
        let trimmed = invoiceText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("lnbc") || trimmed.hasPrefix("lightning:")
    }
    
    // MARK: - Confirmation View
    
    private func confirmationView(invoice: ParsedInvoice) -> some View {
        let balanceSats = (walletModel.balance ?? 0) / 1000
        let totalCost = Int64(invoice.amountSats) + Int64(feeSats)
        let insufficientFunds = totalCost > balanceSats

        return VStack(spacing: 0) {
            Spacer()
            
            // Amount display
            VStack(spacing: 12) {
                Text(formatSats(invoice.amountSats))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                
                Text("sats")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.gray)
                
                if let description = invoice.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                }
            }
            
            Spacer()
            
            // Details card with fee
            VStack(spacing: 12) {
                HStack {
                    Text("Amount")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(formatSats(invoice.amountSats)) sats")
                        .foregroundColor(.white)
                }

                if feeSats > 0 {
                    HStack {
                        Text("Network fee")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(feeSats) sats")
                            .foregroundColor(.orange)
                    }

                    Divider().background(Color.gray.opacity(0.3))

                    HStack {
                        Text("Total")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(formatSats(totalCost)) sats")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                    }
                }

                Divider().background(Color.gray.opacity(0.3))

                HStack {
                    Text("Your balance")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(formatSats(balanceSats)) sats")
                        .foregroundColor(insufficientFunds ? .red : .green)
                }
            }
            .font(.system(size: 14))
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            .padding(.horizontal, 20)

            // Insufficient funds warning
            if insufficientFunds {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("Not enough funds (need \(formatSats(totalCost)) sats)")
                        .font(.caption)
                }
                .foregroundColor(.red)
                .padding(.top, 12)
                .padding(.horizontal, 20)
            }
            
            // Error message
            if let error = error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
            
            Spacer().frame(height: 32)
            
            // Confirm button
            Button(action: confirmPayment) {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Confirm & Pay")
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(insufficientFunds ? .gray : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 28).fill(insufficientFunds ? Color.gray.opacity(0.3) : Color.accentPurple))
            }
            .disabled(isProcessing || insufficientFunds)
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .animation(.easeInOut(duration: 0.2), value: error != nil)
    }
    
    // MARK: - Success View
    
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Success animation
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
            
            Text("Payment Sent!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .opacity(successOpacity)
            
            if let invoice = parsedInvoice {
                Text("\(formatSats(invoice.amountSats)) sats")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .opacity(successOpacity)
            }
            
            Spacer()
            
            // Done button
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
    
    // MARK: - Scanner View
    
    private var invoiceScannerView: some View {
        NavigationView {
            CodeScannerView(codeTypes: [.qr]) { result in
                showScanner = false
                switch result {
                case .success(let scanResult):
                    handleScannedCode(scanResult.string)
                case .failure(let scanError):
                    withAnimation(.easeInOut(duration: 0.2)) {
                        error = "Scan failed: \(scanError.localizedDescription)"
                    }
                }
            }
            .navigationTitle("Scan Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showScanner = false }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleScannedCode(_ code: String) {
        var invoice = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if invoice.lowercased().hasPrefix("lightning:") {
            invoice = String(invoice.dropFirst("lightning:".count))
        }
        invoiceText = invoice
        reviewInvoice()
    }
    
    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string else {
            withAnimation(.easeInOut(duration: 0.2)) {
                error = "Nothing to paste from clipboard"
            }
            return
        }
        var invoice = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        if invoice.lowercased().hasPrefix("lightning:") {
            invoice = String(invoice.dropFirst("lightning:".count))
        }
        invoiceText = invoice
    }
    
    private func reviewInvoice() {
        var invoice = invoiceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if invoice.lowercased().hasPrefix("lightning:") {
            invoice = String(invoice.dropFirst("lightning:".count))
        }
        
        guard invoice.lowercased().hasPrefix("lnbc") else {
            withAnimation(.easeInOut(duration: 0.2)) {
                error = "Invalid invoice format"
            }
            return
        }
        
        let parsed = parseInvoice(invoice)
        parsedInvoice = parsed
        isPreparing = true
        error = nil

        // Prepare the payment to get the fee estimate
        Task {
            if WalletModel.useSparkBackend, let spark = walletModel.sparkService {
                do {
                    let prepared = try await spark.preparePayment(invoice)
                    await MainActor.run {
                        self.preparedPayment = prepared
                        self.feeSats = prepared.feeSats
                        self.isPreparing = false
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showConfirmation = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.isPreparing = false
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.error = "Failed to prepare payment: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                // NWC fallback — no fee estimation available
                await MainActor.run {
                    self.isPreparing = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showConfirmation = true
                    }
                }
            }
        }
    }
    
    private func confirmPayment() {
        guard let invoice = parsedInvoice else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            error = nil
        }
        isProcessing = true
        
        Task {
            do {
                let result: String?
                if WalletModel.useSparkBackend, let spark = walletModel.sparkService, let prepared = preparedPayment {
                    // Use the prepared payment (fee already confirmed by user)
                    result = try await spark.confirmPayment(prepared)
                } else {
                    // NWC fallback
                    result = try await walletModel.payInvoice(invoice.bolt11)
                }
                
                await MainActor.run {
                    preimage = result
                    successScale = 0.5
                    successOpacity = 0
                    withAnimation(.easeInOut(duration: 0.25)) {
                        paymentSuccess = true
                    }
                    isProcessing = false
                }
                
                await walletModel.refreshWalletData()
                
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.error = "Payment failed: \(error.localizedDescription)"
                    }
                    isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Invoice Parsing
    
    private func parseInvoice(_ bolt11: String) -> ParsedInvoice {
        let invoice = bolt11.lowercased()
        var amountSats: Int64 = 0
        
        if invoice.hasPrefix("lnbc") {
            let afterPrefix = String(invoice.dropFirst(4))
            let amountPart = extractAmountPart(afterPrefix)
            if !amountPart.isEmpty {
                amountSats = parseBolt11Amount(amountPart)
            }
        }
        
        return ParsedInvoice(bolt11: bolt11, amountSats: amountSats, description: nil)
    }
    
    private func extractAmountPart(_ str: String) -> String {
        var result = ""
        var foundDigits = false
        
        for char in str {
            if char.isNumber {
                result.append(char)
                foundDigits = true
            } else if foundDigits && "munp".contains(char) {
                result.append(char)
                break
            } else if char == "1" {
                break
            } else {
                break
            }
        }
        
        return result
    }
    
    private func parseBolt11Amount(_ amountStr: String) -> Int64 {
        guard !amountStr.isEmpty else { return 0 }
        
        let lastChar = amountStr.last!
        let multipliers: Set<Character> = ["m", "u", "n", "p"]
        
        if multipliers.contains(lastChar) {
            let numberPart = String(amountStr.dropLast())
            guard let number = Double(numberPart) else { return 0 }
            
            switch lastChar {
            case "m": return Int64(number * 100_000)
            case "u": return Int64(number * 100)
            case "n": return Int64(number / 10)
            case "p": return Int64(number / 10_000)
            default: return 0
            }
        } else {
            guard let number = Double(amountStr) else { return 0 }
            return Int64(number * 100_000_000)
        }
    }
    
    // MARK: - Formatting
    
    private func formatBalance(_ millisats: Int64) -> String {
        let sats = millisats / 1000
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }
}

// MARK: - Parsed Invoice Model

struct ParsedInvoice {
    let bolt11: String
    let amountSats: Int64
    let description: String?
}

#Preview {
    SendPaymentView(walletModel: WalletModel(
        publicKey: PublicKey(hex: "test")!,
        appState: AppState(modelContext: try! ModelContext(ModelContainer(for: AppSettings.self)))
    ))
}
