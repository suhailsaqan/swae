//
//  StreamCoverImagePicker.swift
//  swae
//
//  Coordinates the full image picker → crop → upload → URL flow for stream cover images.
//  Bridges UIKit view controllers into SwiftUI context.
//

import NostrSDK
import PhotosUI
import SwiftUI
import UIKit

class StreamCoverImageCoordinator: NSObject, ImageSourcePickerDelegate, ImageCropperDelegate {

    var onComplete: ((URL?) -> Void)?
    var onStateChanged: ((UploadState) -> Void)?

    enum UploadState {
        case idle
        case cropping
        case uploading
        case success(URL)
        case failed(String)
    }

    private weak var presentingViewController: UIViewController?
    private var keypair: Keypair?
    private var uploadTask: Task<Void, Never>?

    func present(from viewController: UIViewController, keypair: Keypair?, hasExistingImage: Bool) {
        self.presentingViewController = viewController
        self.keypair = keypair

        let picker = ImageSourcePickerViewController(
            imageType: .streamCover,
            hasExistingImage: hasExistingImage
        )
        picker.delegate = self
        viewController.present(picker, animated: true)
    }

    // MARK: - ImageSourcePickerDelegate

    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didSelectImage image: UIImage) {
        onStateChanged?(.cropping)

        let cropper = ImageCropperViewController(
            image: image,
            cropShape: .rect(aspectRatio: 16.0 / 9.0)
        )
        cropper.cropDelegate = self
        presentingViewController?.present(cropper, animated: true)
    }

    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didEnterURL url: URL) {
        onComplete?(url)
        onStateChanged?(.success(url))
    }

    func imageSourcePickerDidRemoveImage(_ picker: ImageSourcePickerViewController) {
        onComplete?(nil)
        onStateChanged?(.idle)
    }

    func imageSourcePickerDidCancel(_ picker: ImageSourcePickerViewController) {
        onStateChanged?(.idle)
    }

    // MARK: - ImageCropperDelegate

    func imageCropper(_ cropper: ImageCropperViewController, didCropImage image: UIImage) {
        onStateChanged?(.uploading)

        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await ImageUploadManager.shared.uploadImage(
                    image,
                    purpose: .streamCover,
                    keypair: self.keypair
                )
                await MainActor.run {
                    self.onComplete?(url)
                    self.onStateChanged?(.success(url))
                }
            } catch {
                await MainActor.run {
                    self.onStateChanged?(.failed(error.localizedDescription))
                }
            }
        }
    }

    func imageCropperDidCancel(_ cropper: ImageCropperViewController) {
        onStateChanged?(.idle)
    }
}
