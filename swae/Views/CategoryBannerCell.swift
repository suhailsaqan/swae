//
//  CategoryBannerCell.swift
//  swae
//
//  Gradient banner header for the category detail page.
//  Shows category icon, name, and live stats.
//

import UIKit

final class CategoryBannerCell: UICollectionViewCell {
    static let reuseIdentifier = "CategoryBannerCell"

    private let gradientLayer = CAGradientLayer()
    private let coverImageView = UIImageView()
    private let overlayGradient = CAGradientLayer()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let statsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        contentView.layer.insertSublayer(gradientLayer, at: 0)

        // Cover image (hidden by default, shown for categories with bundled images)
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.alpha = 0
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(coverImageView)

        // Dark gradient overlay for text readability over cover images
        overlayGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor
        ]
        overlayGradient.startPoint = CGPoint(x: 0.5, y: 0.2)
        overlayGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        overlayGradient.isHidden = true
        contentView.layer.addSublayer(overlayGradient)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white.withAlphaComponent(0.25)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        nameLabel.font = .systemFont(ofSize: 28, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        statsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statsLabel.textColor = .white.withAlphaComponent(0.8)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            // Cover image fills entire cell
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Large background icon (decorative)
            iconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            // Name at bottom-left
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -4),

            // Stats below name
            statsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
        overlayGradient.frame = contentView.bounds
    }

    func configure(with category: StreamCategory, liveCount: Int, viewerCount: Int) {
        gradientLayer.colors = category.gradientColors.map { $0.cgColor }
        iconView.image = UIImage(
            systemName: category.icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 60, weight: .ultraLight)
        )
        nameLabel.text = category.name

        let liveText = liveCount == 1 ? "1 live" : "\(liveCount) live"
        let viewerText = viewerCount == 1 ? "1 viewer" : "\(viewerCount) viewers"
        statsLabel.text = "\(liveText) · \(viewerText)"

        // Show bundled cover image if available
        if let imageName = category.coverImageName,
           let image = UIImage(named: imageName) {
            coverImageView.image = image
            coverImageView.alpha = 1
            overlayGradient.isHidden = false
            iconView.alpha = 0
        } else {
            coverImageView.alpha = 0
            overlayGradient.isHidden = true
            iconView.alpha = 1
        }
    }
}
