//
//  ReceiveView.swift
//  swae
//
//  View for creating Lightning invoices to receive payments
//  Cash App-style design with custom number pad
//

import SwiftUI
import SwiftData
import NostrSDK

struct ReceiveView: View {
    @ObservedObject var walletModel: WalletModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var amountString: String = ""
    @State private var description: String = ""
    @State private var generatedInvoice: String? = nil
    @State private var paymentHash: String? = nil
    @State private var isGenerating: Bool = false
    @State private var error: String? = nil
    @State private var copied: Bool = false
    @State private var showDescriptionInput: Bool = false
    
    // Animation state
    @State private var qrScale: CGFloat = 0.8
    @State private var qrOpacity: Double = 0
    
    private var displayAmount: String {
        if amountString.isEmpty {
            return "0"
        }
        if let number = Int(amountString) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: number)) ?? amountString
        }
        return amountString
    }
    
    private var amountValue: Int {
        return Int(amountString) ?? 0
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if generatedInvoice != nil {
                invoiceDisplayView
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
        .animation(.easeInOut(duration: 0.25), value: generatedInvoice != nil)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Amount Input View (Cash App Style)
    
    private var amountInputView: some View {
        VStack(spacing: 0) {
            // Top bar with close button
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
            
            // Description button
            Button(action: { showDescriptionInput = true }) {
                HStack(spacing: 6) {
                    Image(systemName: description.isEmpty ? "plus.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 16))
                    Text(description.isEmpty ? "Add note" : description)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.gray)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Error message
            if let error = error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Number pad
            numberPad
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            
            // Generate button
            Button(action: generateInvoice) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Text("Request")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(amountValue > 0 ? Color.green : Color.gray.opacity(0.3))
                )
            }
            .disabled(amountValue == 0 || isGenerating)
            .animation(.easeInOut(duration: 0.2), value: amountValue > 0)
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .alert("Add Note", isPresented: $showDescriptionInput) {
            TextField("What's this for?", text: $description)
            Button("Done", action: {})
            Button("Cancel", role: .cancel, action: {})
        }
        .animation(.easeInOut(duration: 0.2), value: error != nil)
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
            ["", "0", "⌫"]
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
            error = nil
        }
    }
    
    // MARK: - Invoice Display View
    
    private var invoiceDisplayView: some View {
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
                Button(action: { dismiss() }) {
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
            
            // QR Code
            if let invoice = generatedInvoice {
                VStack(spacing: 24) {
                    QRCodeView(string: invoice.uppercased(), size: 220)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: .green.opacity(0.3), radius: 20, x: 0, y: 10)
                        .scaleEffect(qrScale)
                        .opacity(qrOpacity)
                        .onAppear {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                qrScale = 1.0
                                qrOpacity = 1.0
                            }
                        }
                    
                    // Amount
                    VStack(spacing: 4) {
                        Text("\(displayAmount) sats")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if !description.isEmpty {
                            Text(description)
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                        }
                    }
                    .opacity(qrOpacity)
                }
            }
            
            Spacer()
            
            // Action buttons
            if let invoice = generatedInvoice {
                VStack(spacing: 12) {
                    // Copy button
                    Button(action: { copyInvoice(invoice) }) {
                        HStack(spacing: 8) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 16, weight: .medium))
                            Text(copied ? "Copied!" : "Copy Invoice")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(Color.green)
                        )
                        .contentTransition(.symbolEffect(.replace))
                    }
                    
                    // Share button
                    ShareLink(item: invoice) {
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
    }
    
    private func goBack() {
        withAnimation(.easeInOut(duration: 0.25)) {
            qrScale = 0.8
            qrOpacity = 0
            generatedInvoice = nil
            amountString = ""
            description = ""
            copied = false
        }
    }
    
    // MARK: - Actions
    
    private func generateInvoice() {
        guard amountValue > 0 else {
            withAnimation(.easeInOut(duration: 0.2)) {
                error = "Enter an amount"
            }
            return
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            error = nil
        }
        isGenerating = true
        
        Task {
            do {
                let result = try await walletModel.makeInvoice(
                    amountSats: amountValue,
                    description: description.isEmpty ? nil : description
                )
                
                await MainActor.run {
                    qrScale = 0.8
                    qrOpacity = 0
                    withAnimation(.easeInOut(duration: 0.25)) {
                        generatedInvoice = result.invoice
                        paymentHash = result.paymentHash
                    }
                    isGenerating = false
                }
                
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.error = error.localizedDescription
                    }
                    isGenerating = false
                }
            }
        }
    }
    
    private func copyInvoice(_ invoice: String) {
        UIPasteboard.general.string = invoice
        
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

#Preview {
    ReceiveView(walletModel: WalletModel(
        publicKey: PublicKey(hex: "test")!,
        appState: AppState(modelContext: try! ModelContext(ModelContainer(for: AppSettings.self)))
    ))
}
