//
//  CropOverlayView.swift
//  swae
//
//  Dimmed overlay with a transparent cutout for the image cropper.
//

import UIKit

final class CropOverlayView: UIView {

    enum CropShape {
        case circle
        case rect(aspectRatio: CGFloat) // width / height
    }

    let cropShape: CropShape
    private(set) var cropRect: CGRect = .zero

    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    init(cropShape: CropShape) {
        self.cropShape = cropShape
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
        layer.addSublayer(maskLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        borderLayer.lineWidth = 2
        layer.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMask()
    }

    private func updateMask() {
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        let padding: CGFloat = 40
        let rect: CGRect
        let cutoutPath: UIBezierPath

        switch cropShape {
        case .circle:
            let diameter = min(b.width, b.height) - padding * 2
            rect = CGRect(
                x: (b.width - diameter) / 2,
                y: (b.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            cutoutPath = UIBezierPath(ovalIn: rect)

        case .rect(let aspectRatio):
            let maxWidth = b.width - padding * 2
            let maxHeight = b.height - padding * 2
            var width = maxWidth
            var height = width / aspectRatio
            if height > maxHeight {
                height = maxHeight
                width = height * aspectRatio
            }
            rect = CGRect(
                x: (b.width - width) / 2,
                y: (b.height - height) / 2,
                width: width,
                height: height
            )
            cutoutPath = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        }

        cropRect = rect

        let fullPath = UIBezierPath(rect: b)
        fullPath.append(cutoutPath)
        maskLayer.path = fullPath.cgPath
        maskLayer.frame = b

        borderLayer.path = cutoutPath.cgPath
        borderLayer.frame = b
    }
}
