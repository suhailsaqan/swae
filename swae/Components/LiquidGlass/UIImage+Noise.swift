import UIKit

// MARK: - UIImage noise generator
extension UIImage {
    static func noiseImage(alpha: CGFloat = 0.012, size: CGSize = CGSize(width: 256, height: 256)) -> UIImage? {
        let scale = UIScreen.main.scale
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let pixelCount = w * h
        var bytes = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount { bytes[i] = UInt8.random(in: 0...255) }
        let data = CFDataCreate(nil, bytes, pixelCount)!
        guard let provider = CGDataProvider(data: data) else { return nil }
        guard let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        ctx.setAlpha(alpha)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img
    }
}
