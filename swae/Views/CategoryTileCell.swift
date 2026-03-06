//
//  CategoryTileCell.swift
//  swae
//
//  Gradient tile cell for the "Popular Categories" section.
//  Shows category name, icon, viewer count, and stream count.
//

import Kingfisher
import UIKit

final class CategoryTileCell: UICollectionViewCell {
    static let reuseIdentifier = "CategoryTileCell"

    private let gradientLayer = CAGradientLayer()
    private let coverImageView = UIImageView()
    private let overlayGradient = CAGradientLayer()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let statsLabel = UILabel()
    private var coverTask: Task<Void, Never>?

    var onTap: (() -> Void)?

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

        // Gradient background
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        contentView.layer.insertSublayer(gradientLayer, at: 0)

        // Cover art image (hidden by default, shown when cover data loads)
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
        overlayGradient.startPoint = CGPoint(x: 0.5, y: 0.3)
        overlayGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        overlayGradient.isHidden = true
        contentView.layer.addSublayer(overlayGradient)

        // Large centered icon
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white.withAlphaComponent(0.3)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // Category name at bottom
        nameLabel.font = .systemFont(ofSize: 18, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        // Stats pill (viewers + streams)
        statsLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statsLabel.textColor = .white.withAlphaComponent(0.85)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -2),

            statsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            statsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        onTap?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
        overlayGradient.frame = contentView.bounds
    }

    func configure(with stat: CategoryStat) {
        gradientLayer.colors = stat.category.gradientColors.map { $0.cgColor }
        iconView.image = UIImage(
            systemName: stat.category.icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        )
        nameLabel.text = stat.category.name

        let streamText = stat.streamCount == 1 ? "1 stream" : "\(stat.streamCount) streams"
        if stat.viewerCount > 0 {
            let viewerText = stat.viewerCount == 1 ? "1 viewer" : "\(stat.viewerCount) viewers"
            statsLabel.text = "\(viewerText) · \(streamText)"
        } else {
            statsLabel.text = streamText
        }

        // Reset to default state
        coverImageView.alpha = 0
        iconView.alpha = 1
        overlayGradient.isHidden = true

        // Tier 1: IGDB cover art (async network fetch)
        if let gameId = stat.igdbGameId {
            coverTask = Task { [weak self] in
                guard let info = await GameDatabaseService.shared.getGame(id: gameId),
                      let coverURL = info.coverURL else { return }
                await MainActor.run {
                    guard let self = self else { return }
                    self.coverImageView.kf.setImage(
                        with: coverURL,
                        options: [.transition(.fade(0.2)), .cacheOriginalImage]
                    ) { result in
                        if case .success = result {
                            UIView.animate(withDuration: 0.2) {
                                self.coverImageView.alpha = 1
                                self.iconView.alpha = 0
                                self.overlayGradient.isHidden = false
                            }
                        }
                    }
                }
            }
        }
        // Tier 2: Bundled category image (synchronous, from asset catalog)
        else if let imageName = stat.category.coverImageName,
                let image = UIImage(named: imageName) {
            coverImageView.image = image
            coverImageView.alpha = 1
            iconView.alpha = 0
            overlayGradient.isHidden = false
        }
        // Tier 3: Gradient + SF Symbol icon (default state, no action needed)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
        coverTask?.cancel()
        coverTask = nil
        coverImageView.kf.cancelDownloadTask()
        coverImageView.image = nil
        coverImageView.alpha = 0
        iconView.alpha = 1
        overlayGradient.isHidden = true
    }
}

// MARK: - CategoryStat

/// Aggregated stats for a category, computed in rebuildSections.
struct CategoryStat {
    let category: StreamCategory
    var viewerCount: Int
    var streamCount: Int
    var liveCount: Int = 0
    var igdbGameId: String?
}
