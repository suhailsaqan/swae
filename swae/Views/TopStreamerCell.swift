//
//  TopStreamerCell.swift
//  swae
//
//  Horizontal avatar cell for top zap-ranked streamers.
//  Shows avatar, zap amount, and display name.
//

import Kingfisher
import UIKit

final class TopStreamerCell: UICollectionViewCell {
    static let reuseIdentifier = "TopStreamerCell"

    private let avatarImageView = UIImageView()
    private let zapLabel = UILabel()
    private let nameLabel = UILabel()
    private let stack = UIStackView()

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 28
        avatarImageView.backgroundColor = .tertiarySystemFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        zapLabel.font = .systemFont(ofSize: 13, weight: .bold)
        zapLabel.textColor = UIColor.systemYellow
        zapLabel.textAlignment = .center

        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .secondaryLabel
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(avatarImageView)
        stack.addArrangedSubview(zapLabel)
        stack.addArrangedSubview(nameLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: 56),
            avatarImageView.heightAnchor.constraint(equalToConstant: 56),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4),

            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        onTap?()
    }

    func configure(avatarURL: URL?, displayName: String, totalSats: Int64) {
        if let url = avatarURL {
            avatarImageView.kf.setImage(
                with: url,
                placeholder: UIImage(systemName: "person.circle.fill"),
                options: [.transition(.fade(0.2)), .cacheOriginalImage]
            )
        } else {
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .tertiaryLabel
        }

        zapLabel.text = "\(formatSats(totalSats)) ⚡"
        nameLabel.text = displayName
    }

    private func formatSats(_ sats: Int64) -> String {
        if sats >= 1_000_000 {
            return String(format: "%.1fM", Double(sats) / 1_000_000)
        } else if sats >= 1_000 {
            return String(format: "%.1fk", Double(sats) / 1_000)
        }
        return "\(sats)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.kf.cancelDownloadTask()
        avatarImageView.image = nil
        onTap = nil
    }
}
