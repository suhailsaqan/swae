//
//  QRCodeView.swift
//  swae
//
//  QR Code generator component for displaying Lightning invoices
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let string: String
    var size: CGFloat = 200
    var backgroundColor: Color = .white
    var foregroundColor: Color = .black
    
    var body: some View {
        Image(uiImage: generateQRCode())
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(backgroundColor)
            .cornerRadius(12)
    }
    
    private func generateQRCode() -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        // Convert string to data
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel") // Medium error correction
        
        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        
        // Scale up the QR code for better quality
        let scale = size / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    VStack(spacing: 20) {
        QRCodeView(string: "lnbc1000n1ptest123...", size: 200)
        
        QRCodeView(string: "lightning:lnbc500n1p...", size: 150)
    }
    .padding()
    .background(Color.black)
}
