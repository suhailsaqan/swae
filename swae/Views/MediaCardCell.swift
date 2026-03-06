//
//  MediaCardCell.swift
//  swae
//
//  Shared card cell for clips (kind 1313) and videos (kind 21).
//  Shows thumbnail with play icon overlay, optional duration badge, and title.
//

import Kingfisher
import UIKit

final class MediaCardCell: UICollectionViewCell {
    static let reuseIdentifier = "MediaCardCell"

    private let thumbnailView = UIImageView()
    private let playIcon = UIImageView()
    private let durationBadge = PaddedLabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground

        // Thumbnail
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = .tertiarySystemFill
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailView)

        // Play icon overlay
        let playConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        playIcon.image = UIImage(systemName: "play.circle.fill", withConfiguration: playConfig)
        playIcon.tintColor = UIColor.white.withAlphaComponent(0.9)
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.layer.shadowColor = UIColor.black.cgColor
        playIcon.layer.shadowOffset = CGSize(width: 0, height: 2)
        playIcon.layer.shadowRadius = 4
        playIcon.layer.shadowOpacity = 0.5
        contentView.addSubview(playIcon)

        // Duration badge
        durationBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        durationBadge.textColor = .white
        durationBadge.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        durationBadge.layer.cornerRadius = 4
        durationBadge.clipsToBounds = true
        durationBadge.textAlignment = .center
        durationBadge.translatesAutoresizingMaskIntoConstraints = false
        durationBadge.isHidden = true
        contentView.addSubview(durationBadge)

        // Title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Subtitle (source stream or creator)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 9.0/16.0),

            playIcon.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),

            durationBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -6),
            durationBadge.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -6),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        onTap?()
    }

    func configureAsClip(thumbnailURL: URL?, title: String?, subtitle: String?) {
        loadThumbnail(thumbnailURL)
        titleLabel.text = title ?? "Untitled Clip"
        subtitleLabel.text = subtitle
        durationBadge.isHidden = true  // Clips don't have duration in the event
    }

    func configureAsShort(thumbnailURL: URL?, title: String?, subtitle: String?) {
        loadThumbnail(thumbnailURL)
        titleLabel.text = title ?? "Untitled Short"
        subtitleLabel.text = subtitle
        durationBadge.isHidden = true
    }

    private func loadThumbnail(_ url: URL?) {
        if let url = url {
            thumbnailView.kf.setImage(
                with: url,
                placeholder: nil,
                options: [.transition(.fade(0.2)), .cacheOriginalImage]
            )
        } else {
            thumbnailView.image = nil
            thumbnailView.backgroundColor = .tertiarySystemFill
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.kf.cancelDownloadTask()
        thumbnailView.image = nil
        durationBadge.isHidden = true
        onTap = nil
    }
}
