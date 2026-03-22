//
//  SkeletonView.swift
//  swae
//
//  Created for skeleton loading states
//

import UIKit

/// A reusable skeleton loading view with shimmer animation
final class SkeletonView: UIView {

    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSkeleton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSkeleton()
    }

    private func setupSkeleton() {
        backgroundColor = .systemGray6
        layer.cornerRadius = 8
        clipsToBounds = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.5, 1]

        updateGradientColors()

        layer.addSublayer(gradientLayer)
    }

    private func updateGradientColors() {
        let lightColor = UIColor.systemGray5.cgColor
        let darkColor = UIColor.systemGray6.cgColor
        gradientLayer.colors = [darkColor, lightColor, darkColor]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateGradientColors()
        }
    }

    /// Starts shimmer animation with an optional delay for staggered wave effect.
    func startAnimating(delay: TimeInterval = 0) {
        guard gradientLayer.animation(forKey: "shimmer") == nil else { return }

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = 1.5
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if delay > 0 {
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        gradientLayer.add(animation, forKey: "shimmer")
    }

    func stopAnimating() {
        gradientLayer.removeAnimation(forKey: "shimmer")
    }

    /// Configures the skeleton for dark backgrounds (e.g., glass modal overlays).
    func useDarkStyle() {
        backgroundColor = UIColor(white: 1.0, alpha: 0.06)
        let lightColor = UIColor(white: 1.0, alpha: 0.12).cgColor
        let darkColor = UIColor(white: 1.0, alpha: 0.04).cgColor
        gradientLayer.colors = [darkColor, lightColor, darkColor]
    }
}

// MARK: - Carousel Skeleton (matches StreamCardCell: thumbnail + avatar + title + subtitle)

final class CarouselSkeletonCell: UICollectionViewCell {
    static let reuseIdentifier = "CarouselSkeletonCell"

    private let thumbnailSkeleton = SkeletonView()
    private let avatarSkeleton = SkeletonView()
    private let titleSkeleton = SkeletonView()
    private let subtitleSkeleton = SkeletonView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Thumbnail — 16:9, cornerRadius 12 (matches StreamCardCell.imageView)
        thumbnailSkeleton.layer.cornerRadius = 12
        thumbnailSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailSkeleton)

        // Avatar circle — 32×32 (matches StreamCardCell.hostImageView)
        avatarSkeleton.layer.cornerRadius = 16
        avatarSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarSkeleton)

        // Title bar (matches StreamCardCell.titleLabel)
        titleSkeleton.layer.cornerRadius = 4
        titleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleSkeleton)

        // Subtitle bar (matches StreamCardCell.hostLabel, shorter width)
        subtitleSkeleton.layer.cornerRadius = 4
        subtitleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleSkeleton)

        NSLayoutConstraint.activate([
            thumbnailSkeleton.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailSkeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailSkeleton.heightAnchor.constraint(equalTo: thumbnailSkeleton.widthAnchor, multiplier: 9.0 / 16.0),

            avatarSkeleton.topAnchor.constraint(equalTo: thumbnailSkeleton.bottomAnchor, constant: 8),
            avatarSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            avatarSkeleton.widthAnchor.constraint(equalToConstant: 32),
            avatarSkeleton.heightAnchor.constraint(equalToConstant: 32),

            titleSkeleton.topAnchor.constraint(equalTo: thumbnailSkeleton.bottomAnchor, constant: 10),
            titleSkeleton.leadingAnchor.constraint(equalTo: avatarSkeleton.trailingAnchor, constant: 8),
            titleSkeleton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.55),
            titleSkeleton.heightAnchor.constraint(equalToConstant: 14),

            subtitleSkeleton.topAnchor.constraint(equalTo: titleSkeleton.bottomAnchor, constant: 6),
            subtitleSkeleton.leadingAnchor.constraint(equalTo: titleSkeleton.leadingAnchor),
            subtitleSkeleton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.35),
            subtitleSkeleton.heightAnchor.constraint(equalToConstant: 12),
        ])

        startAnimating()
    }

    private func startAnimating() {
        thumbnailSkeleton.startAnimating(delay: 0)
        avatarSkeleton.startAnimating(delay: 0.1)
        titleSkeleton.startAnimating(delay: 0.15)
        subtitleSkeleton.startAnimating(delay: 0.2)
    }

    func restartAnimations() {
        [thumbnailSkeleton, avatarSkeleton, titleSkeleton, subtitleSkeleton].forEach {
            $0.stopAnimating()
        }
        startAnimating()
    }
}

// MARK: - Media Skeleton (matches MediaCardCell: thumbnail + title + subtitle)

final class MediaSkeletonCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaSkeletonCell"

    private let thumbnailSkeleton = SkeletonView()
    private let titleSkeleton = SkeletonView()
    private let subtitleSkeleton = SkeletonView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        // Thumbnail — 16:9 (matches MediaCardCell.thumbnailView)
        thumbnailSkeleton.layer.cornerRadius = 0
        thumbnailSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailSkeleton)

        titleSkeleton.layer.cornerRadius = 4
        titleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleSkeleton)

        subtitleSkeleton.layer.cornerRadius = 4
        subtitleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleSkeleton)

        NSLayoutConstraint.activate([
            thumbnailSkeleton.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailSkeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailSkeleton.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 9.0 / 16.0),

            titleSkeleton.topAnchor.constraint(equalTo: thumbnailSkeleton.bottomAnchor, constant: 8),
            titleSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleSkeleton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.7),
            titleSkeleton.heightAnchor.constraint(equalToConstant: 12),

            subtitleSkeleton.topAnchor.constraint(equalTo: titleSkeleton.bottomAnchor, constant: 5),
            subtitleSkeleton.leadingAnchor.constraint(equalTo: titleSkeleton.leadingAnchor),
            subtitleSkeleton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.4),
            subtitleSkeleton.heightAnchor.constraint(equalToConstant: 10),
        ])

        thumbnailSkeleton.startAnimating(delay: 0)
        titleSkeleton.startAnimating(delay: 0.1)
        subtitleSkeleton.startAnimating(delay: 0.15)
    }

    func restartAnimations() {
        [thumbnailSkeleton, titleSkeleton, subtitleSkeleton].forEach {
            $0.stopAnimating()
        }
        thumbnailSkeleton.startAnimating(delay: 0)
        titleSkeleton.startAnimating(delay: 0.1)
        subtitleSkeleton.startAnimating(delay: 0.15)
    }
}
