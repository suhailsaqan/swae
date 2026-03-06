//
//  ImageUploadProgressView.swift
//  swae
//
//  Upload status indicator that attaches around a target view.
//  For profile pics: animated spinning ring around the circle border.
//  For banners: small pill badge at bottom-right corner.
//

import UIKit

final class ImageUploadProgressView: UIView {

    enum State {
        case uploading
        case success
        case failed
    }

    enum Style {
        case ring    // Spinning ring around a circular profile pic
        case badge   // Small pill badge for banner
    }

    var onRetryTapped: (() -> Void)?
    private(set) var currentState: State = .uploading

    private let style: Style

    // Ring style
    private let ringLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let ringRetryButton = UIButton(type: .system)

    // Badge style
    private let pillBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let pillIcon = UIImageView()
    private let pillSpinner = UIActivityIndicatorView(style: .medium)

    // Shared
    private let checkmarkContainer = UIView()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        switch style {
        case .ring: setupRing()
        case .badge: setupBadge()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        self.style = .ring
        super.init(frame: frame)
        setupRing()
    }

    // MARK: - Ring Setup (Profile Pic)

    private func setupRing() {
        isUserInteractionEnabled = false

        trackLayer.fillColor = nil
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
        trackLayer.lineWidth = 3
        layer.addSublayer(trackLayer)

        ringLayer.fillColor = nil
        ringLayer.strokeColor = UIColor.accentPurple.cgColor
        ringLayer.lineWidth = 3
        ringLayer.lineCap = .round
        ringLayer.strokeStart = 0
        ringLayer.strokeEnd = 0.25
        layer.addSublayer(ringLayer)

        // Retry button — centered inside the ring, shown only on failure
        let retryImage = UIImage(systemName: "arrow.clockwise")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        ringRetryButton.setImage(retryImage, for: .normal)
        ringRetryButton.tintColor = .white
        ringRetryButton.backgroundColor = UIColor(red: 235/255, green: 55/255, blue: 55/255, alpha: 1)
        ringRetryButton.layer.cornerRadius = 20
        ringRetryButton.isHidden = true
        ringRetryButton.translatesAutoresizingMaskIntoConstraints = false
        ringRetryButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        addSubview(ringRetryButton)

        NSLayoutConstraint.activate([
            ringRetryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringRetryButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ringRetryButton.widthAnchor.constraint(equalToConstant: 40),
            ringRetryButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard style == .ring else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 1.5
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)
        trackLayer.path = path.cgPath
        trackLayer.frame = bounds
        ringLayer.path = path.cgPath
        ringLayer.frame = bounds
    }

    // MARK: - Badge Setup (Banner)

    private func setupBadge() {
        pillBackground.layer.cornerRadius = 14
        pillBackground.clipsToBounds = true
        pillBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillBackground)

        pillSpinner.color = UIColor.white
        pillSpinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        pillSpinner.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.contentView.addSubview(pillSpinner)

        pillIcon.contentMode = .scaleAspectFit
        pillIcon.translatesAutoresizingMaskIntoConstraints = false
        pillIcon.isHidden = true
        pillBackground.contentView.addSubview(pillIcon)

        NSLayoutConstraint.activate([
            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            pillBackground.heightAnchor.constraint(equalToConstant: 28),

            pillSpinner.centerXAnchor.constraint(equalTo: pillBackground.contentView.centerXAnchor),
            pillSpinner.centerYAnchor.constraint(equalTo: pillBackground.contentView.centerYAnchor),

            pillIcon.centerXAnchor.constraint(equalTo: pillBackground.contentView.centerXAnchor),
            pillIcon.centerYAnchor.constraint(equalTo: pillBackground.contentView.centerYAnchor),
            pillIcon.widthAnchor.constraint(equalToConstant: 16),
            pillIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        isAccessibilityElement = true
    }

    // MARK: - State

    func setState(_ state: State) {
        currentState = state

        switch style {
        case .ring: applyRingState(state)
        case .badge: applyBadgeState(state)
        }
    }

    // MARK: - Ring States

    private func applyRingState(_ state: State) {
        switch state {
        case .uploading:
            ringLayer.isHidden = false
            trackLayer.isHidden = false
            ringLayer.strokeColor = UIColor.accentPurple.cgColor
            ringRetryButton.isHidden = true
            isUserInteractionEnabled = false
            startSpinAnimation()

        case .success:
            stopSpinAnimation()
            ringLayer.isHidden = true
            trackLayer.isHidden = true
            ringRetryButton.isHidden = true
            // Brief green flash on the ring, then remove
            let flash = CAShapeLayer()
            flash.path = ringLayer.path
            flash.frame = bounds
            flash.fillColor = nil
            flash.strokeColor = UIColor.editProfileSuccess.cgColor
            flash.lineWidth = 3
            flash.strokeEnd = 1
            layer.addSublayer(flash)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.8
            fade.beginTime = CACurrentMediaTime() + 0.5
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            flash.add(fade, forKey: "fade")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
                flash.removeFromSuperlayer()
                self?.removeFromSuperview()
            }

        case .failed:
            stopSpinAnimation()
            ringLayer.strokeColor = UIColor(red: 235/255, green: 55/255, blue: 55/255, alpha: 1).cgColor
            ringLayer.strokeEnd = 1
            trackLayer.isHidden = true
            ringRetryButton.isHidden = false
            ringRetryButton.alpha = 0
            ringRetryButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            isUserInteractionEnabled = true

            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.ringRetryButton.alpha = 1
                self.ringRetryButton.transform = .identity
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func startSpinAnimation() {
        guard ringLayer.animation(forKey: "spin") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 0.8
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        ringLayer.add(rotation, forKey: "spin")
    }

    private func stopSpinAnimation() {
        ringLayer.removeAnimation(forKey: "spin")
    }

    // MARK: - Badge States

    private func applyBadgeState(_ state: State) {
        switch state {
        case .uploading:
            pillSpinner.startAnimating()
            pillSpinner.isHidden = false
            pillIcon.isHidden = true
            isUserInteractionEnabled = false
            accessibilityLabel = "Uploading image"

        case .success:
            pillSpinner.stopAnimating()
            pillSpinner.isHidden = true
            pillIcon.isHidden = false
            pillIcon.image = UIImage(systemName: "checkmark.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            pillIcon.tintColor = .editProfileSuccess
            accessibilityLabel = "Upload complete"

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            UIView.animate(withDuration: 0.3, delay: 1.0, options: []) {
                self.alpha = 0
            } completion: { _ in
                self.removeFromSuperview()
            }

        case .failed:
            pillSpinner.stopAnimating()
            pillSpinner.isHidden = true
            pillIcon.isHidden = false
            pillIcon.image = UIImage(systemName: "arrow.clockwise.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            pillIcon.tintColor = .editProfileError
            isUserInteractionEnabled = true
            accessibilityLabel = "Upload failed, tap to retry"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @objc private func handleTap() {
        guard currentState == .failed else { return }
        onRetryTapped?()
    }
}
