//
//  SearchResultCell.swift
//  swae
//
//  Cell for displaying a user in search results.
//  Follows the FollowingUserCell pattern (64pt row, 44pt circle pfp).
//

import Kingfisher
import UIKit

// MARK: - Search Skeleton Cell

final class SearchSkeletonCell: UITableViewCell {
    static let reuseIdentifier = "SearchSkeletonCell"

    private let profileSkeleton = SkeletonView()
    private let nameSkeleton = SkeletonView()
    private let usernameSkeleton = SkeletonView()
    private let countSkeleton = SkeletonView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        selectionStyle = .none
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        profileSkeleton.layer.cornerRadius = 22
        profileSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(profileSkeleton)

        nameSkeleton.layer.cornerRadius = 4
        nameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameSkeleton)

        usernameSkeleton.layer.cornerRadius = 4
        usernameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(usernameSkeleton)

        countSkeleton.layer.cornerRadius = 4
        countSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(countSkeleton)

        NSLayoutConstraint.activate([
            profileSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileSkeleton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            profileSkeleton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            profileSkeleton.widthAnchor.constraint(equalToConstant: 44),
            profileSkeleton.heightAnchor.constraint(equalToConstant: 44),

            nameSkeleton.leadingAnchor.constraint(equalTo: profileSkeleton.trailingAnchor, constant: 12),
            nameSkeleton.topAnchor.constraint(equalTo: profileSkeleton.topAnchor, constant: 6),
            nameSkeleton.widthAnchor.constraint(equalToConstant: 120),
            nameSkeleton.heightAnchor.constraint(equalToConstant: 14),

            usernameSkeleton.leadingAnchor.constraint(equalTo: nameSkeleton.leadingAnchor),
            usernameSkeleton.topAnchor.constraint(equalTo: nameSkeleton.bottomAnchor, constant: 6),
            usernameSkeleton.widthAnchor.constraint(equalToConstant: 80),
            usernameSkeleton.heightAnchor.constraint(equalToConstant: 12),

            countSkeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            countSkeleton.centerYAnchor.constraint(equalTo: profileSkeleton.centerYAnchor),
            countSkeleton.widthAnchor.constraint(equalToConstant: 50),
            countSkeleton.heightAnchor.constraint(equalToConstant: 14),
        ])

        [profileSkeleton, nameSkeleton, usernameSkeleton, countSkeleton].forEach { $0.startAnimating() }
    }
}

// MARK: - Search Result Cell

final class SearchResultCell: UITableViewCell {
    static let reuseIdentifier = "SearchResultCell"

    private let profileImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 22
        iv.backgroundColor = .systemGray5
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()

    private let nip05Label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .accentPurple
        return label
    }()

    private let followersLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(profileImageView)
        contentView.addSubview(textStack)
        contentView.addSubview(followersLabel)

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(usernameLabel)
        textStack.addArrangedSubview(nip05Label)

        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 44),
            profileImageView.heightAnchor.constraint(equalToConstant: 44),
            profileImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            profileImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            textStack.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: followersLabel.leadingAnchor, constant: -12),

            followersLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            followersLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            followersLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    func configure(with result: SearchViewModel.SearchResult) {
        // Name
        let displayName = result.displayName
        let trustDot = result.trustDot
        nameLabel.text = trustDot.isEmpty ? displayName : "\(trustDot) \(displayName)"

        // Username
        if let username = result.username, !username.isEmpty {
            usernameLabel.text = "@\(username)"
            usernameLabel.isHidden = false
        } else {
            usernameLabel.isHidden = true
        }

        // NIP-05
        if let domain = result.nip05Domain {
            nip05Label.text = "✓ \(domain)"
            nip05Label.isHidden = false
        } else {
            nip05Label.isHidden = true
        }

        // Followers count
        let count = result.followersCount
        if count > 0 {
            followersLabel.text = abbreviatedCount(count) + " followers"
        } else {
            followersLabel.text = nil
        }

        // Profile picture
        if let url = result.pictureURL {
            profileImageView.kf.setImage(
                with: url,
                options: [
                    .transition(.none),
                    .cacheOriginalImage,
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 88, height: 88))),
                    .scaleFactor(UIScreen.main.scale),
                    .backgroundDecode,
                ]
            )
        } else {
            profileImageView.image = nil
            profileImageView.backgroundColor = .systemGray5
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.kf.cancelDownloadTask()
        profileImageView.image = nil
        profileImageView.backgroundColor = .systemGray5
        nameLabel.text = nil
        usernameLabel.text = nil
        usernameLabel.isHidden = false
        nip05Label.text = nil
        nip05Label.isHidden = true
        followersLabel.text = nil
    }

    private func abbreviatedCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
