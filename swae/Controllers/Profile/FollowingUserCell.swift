//
//  FollowingUserCell.swift
//  swae
//
//  Cell for displaying a user in the following/followers list
//  Optimized for performance with skeleton loading
//

import Kingfisher
import NostrSDK
import UIKit

// MARK: - Skeleton Cell

final class FollowingSkeletonCell: UITableViewCell {
    static let reuseIdentifier = "FollowingSkeletonCell"
    
    private let profileSkeleton = SkeletonView()
    private let nameSkeleton = SkeletonView()
    private let usernameSkeleton = SkeletonView()
    private let buttonSkeleton = SkeletonView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        isUserInteractionEnabled = false
        
        profileSkeleton.layer.cornerRadius = 22
        profileSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(profileSkeleton)
        
        nameSkeleton.layer.cornerRadius = 4
        nameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameSkeleton)
        
        usernameSkeleton.layer.cornerRadius = 4
        usernameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(usernameSkeleton)
        
        buttonSkeleton.layer.cornerRadius = 14
        buttonSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonSkeleton)
        
        NSLayoutConstraint.activate([
            // Profile skeleton - drives cell height
            profileSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileSkeleton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            profileSkeleton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            profileSkeleton.widthAnchor.constraint(equalToConstant: 44),
            profileSkeleton.heightAnchor.constraint(equalToConstant: 44),
            
            // Name skeleton
            nameSkeleton.leadingAnchor.constraint(equalTo: profileSkeleton.trailingAnchor, constant: 12),
            nameSkeleton.topAnchor.constraint(equalTo: profileSkeleton.topAnchor, constant: 6),
            nameSkeleton.widthAnchor.constraint(equalToConstant: 100),
            nameSkeleton.heightAnchor.constraint(equalToConstant: 14),
            
            // Username skeleton
            usernameSkeleton.leadingAnchor.constraint(equalTo: nameSkeleton.leadingAnchor),
            usernameSkeleton.topAnchor.constraint(equalTo: nameSkeleton.bottomAnchor, constant: 6),
            usernameSkeleton.widthAnchor.constraint(equalToConstant: 70),
            usernameSkeleton.heightAnchor.constraint(equalToConstant: 12),
            
            // Button skeleton
            buttonSkeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttonSkeleton.centerYAnchor.constraint(equalTo: profileSkeleton.centerYAnchor),
            buttonSkeleton.widthAnchor.constraint(equalToConstant: 72),
            buttonSkeleton.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        startAnimating()
    }
    
    func startAnimating() {
        [profileSkeleton, nameSkeleton, usernameSkeleton, buttonSkeleton].forEach {
            $0.startAnimating()
        }
    }
}

// MARK: - User Cell

final class FollowingUserCell: UITableViewCell {
    static let reuseIdentifier = "FollowingUserCell"
    
    // MARK: - UI Components
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
    
    private let followButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()
    
    private var currentPubkey: String?
    var onFollowToggle: ((String, Bool) -> Void)?
    
    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        selectionStyle = .none
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(textStack)
        contentView.addSubview(followButton)
        
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(usernameLabel)
        
        NSLayoutConstraint.activate([
            // Profile image - 44pt circle
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 44),
            profileImageView.heightAnchor.constraint(equalToConstant: 44),
            profileImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            profileImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            
            // Text stack - fills middle, compressed by button
            textStack.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -12),
            
            // Follow button - fixed size, right aligned
            followButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            followButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            followButton.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - Configuration
    func configure(with pubkey: String, metadata: UserMetadata?, isFollowing: Bool, isOwnProfile: Bool) {
        self.currentPubkey = pubkey
        
        // Name - prefer display name, fall back to username, then truncated pubkey
        let displayName = metadata?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = metadata?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let displayName, !displayName.isEmpty {
            nameLabel.text = displayName
        } else if let name, !name.isEmpty {
            nameLabel.text = name
        } else {
            nameLabel.text = String(pubkey.prefix(8)) + "..."
        }
        
        // Username - show if different from display name
        if let name, !name.isEmpty {
            usernameLabel.text = "@\(name)"
            usernameLabel.isHidden = false
        } else {
            usernameLabel.isHidden = true
        }
        
        // Profile picture
        if let pictureURL = metadata?.pictureURL {
            profileImageView.kf.setImage(
                with: pictureURL,
                options: [
                    .transition(.none),
                    .cacheOriginalImage,
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 88, height: 88))),
                    .scaleFactor(UIScreen.main.scale),
                    .backgroundDecode
                ]
            )
        } else {
            profileImageView.image = nil
            profileImageView.backgroundColor = .systemGray5
        }
        
        // Follow button - hide for own profile
        if isOwnProfile {
            followButton.isHidden = true
        } else {
            followButton.isHidden = false
            updateFollowButtonAppearance(isFollowing: isFollowing)
        }
    }
    
    private func updateFollowButtonAppearance(isFollowing: Bool) {
        if isFollowing {
            followButton.setTitle("Following", for: .normal)
            followButton.setTitleColor(.label, for: .normal)
            followButton.backgroundColor = .tertiarySystemFill
            followButton.layer.borderWidth = 0
        } else {
            followButton.setTitle("Follow", for: .normal)
            followButton.setTitleColor(.white, for: .normal)
            followButton.backgroundColor = .accentPurple
            followButton.layer.borderWidth = 0
        }
    }
    
    @objc private func followButtonTapped() {
        guard let pubkey = currentPubkey else { return }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        let isCurrentlyFollowing = followButton.title(for: .normal) == "Following"
        updateFollowButtonAppearance(isFollowing: !isCurrentlyFollowing)
        onFollowToggle?(pubkey, !isCurrentlyFollowing)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.kf.cancelDownloadTask()
        profileImageView.image = nil
        profileImageView.backgroundColor = .systemGray5
        nameLabel.text = nil
        usernameLabel.text = nil
        usernameLabel.isHidden = false
        followButton.isHidden = false
        currentPubkey = nil
        onFollowToggle = nil
    }
}
