//
//  ImageUploadManager.swift
//  swae
//
//  Prepares images (resize, compress) and coordinates upload to nostr.build.
//

import NostrSDK
import UIKit

final class ImageUploadManager {

    static let shared = ImageUploadManager()

    enum ImagePurpose {
        case profilePicture  // max 400×400
        case banner          // max 1500×500
        case streamCover     // max 1280×720 (16:9 landscape)

        var maxSize: CGSize {
            switch self {
            case .profilePicture: return CGSize(width: 400, height: 400)
            case .banner: return CGSize(width: 1500, height: 500)
            case .streamCover: return CGSize(width: 1280, height: 720)
            }
        }
    }

    private init() {}

    /// Resizes, compresses, and uploads an image.
    /// - Returns: The public URL of the uploaded image.
    func uploadImage(
        _ image: UIImage,
        purpose: ImagePurpose,
        keypair: Keypair?
    ) async throws -> URL {
        let resized = resize(image, to: purpose.maxSize)

        // Try 0.8 quality first, fall back to 0.6 if too large
        var jpegData = resized.jpegData(compressionQuality: 0.8)

        if let data = jpegData, data.count > 10_000_000 {
            jpegData = resized.jpegData(compressionQuality: 0.6)
        }

        guard let data = jpegData, data.count <= 10_000_000 else {
            throw NostrBuildUploadError.fileTooLarge
        }

        let filename: String
        switch purpose {
        case .profilePicture: filename = "profile.jpg"
        case .banner: filename = "banner.jpg"
        case .streamCover: filename = "stream_cover.jpg"
        }

        let result = try await NostrBuildUploadService.shared.upload(
            imageData: data,
            mimeType: "image/jpeg",
            filename: filename,
            keypair: keypair
        )

        return result.url
    }

    // MARK: - Private

    private func resize(_ image: UIImage, to maxSize: CGSize) -> UIImage {
        let size = image.size
        guard size.width > maxSize.width || size.height > maxSize.height else { return image }

        let widthRatio = maxSize.width / size.width
        let heightRatio = maxSize.height / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: floor(size.width * ratio),
            height: floor(size.height * ratio)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
