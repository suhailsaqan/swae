//
//  ProfileStreamCells.swift
//  swae
//
//  UIKit cells for profile streams list
//

import Kingfisher
import NostrSDK
import UIKit

// MARK: - Profile Section Header View
final class ProfileSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "ProfileSectionHeaderView"
    
    private let liveIndicator = UIView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    
    private var titleLeadingToIndicatorConstraint: NSLayoutConstraint!
    private var titleLeadingToEdgeConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Live indicator (pulsing red dot)
        liveIndicator.backgroundColor = .systemRed
        liveIndicator.layer.cornerRadius = 4
        liveIndicator.translatesAutoresizingMaskIntoConstraints = false
        liveIndicator.isHidden = true
        addSubview(liveIndicator)
        
        // Title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        // Count badge
        countLabel.font = .systemFont(ofSize: 14, weight: .medium)
        countLabel.textColor = .secondaryLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)
        
        // Create both title leading constraints
        titleLeadingToIndicatorConstraint = titleLabel.leadingAnchor.constraint(equalTo: liveIndicator.trailingAnchor, constant: 8)
        titleLeadingToEdgeConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        
        NSLayoutConstraint.activate([
            liveIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            liveIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            liveIndicator.widthAnchor.constraint(equalToConstant: 8),
            liveIndicator.heightAnchor.constraint(equalToConstant: 8),
            
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLeadingToEdgeConstraint,  // Default: no indicator
            
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    func configure(title: String, count: Int, isLive: Bool = false) {
        titleLabel.text = title
        countLabel.text = count > 0 ? "\(count)" : nil
        
        // Toggle live indicator
        liveIndicator.isHidden = !isLive
        titleLeadingToEdgeConstraint.isActive = !isLive
        titleLeadingToIndicatorConstraint.isActive = isLive
        
        if isLive {
            startPulseAnimation()
        } else {
            liveIndicator.layer.removeAllAnimations()
        }
    }
    
    private func startPulseAnimation() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 1.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        liveIndicator.layer.add(animation, forKey: "pulse")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        liveIndicator.layer.removeAllAnimations()
    }
}

// MARK: - Profile Stream Skeleton Cell
final class ProfileStreamSkeletonCell: UICollectionViewCell {
    static let reuseIdentifier = "ProfileStreamSkeletonCell"
    
    // MARK: - UI Components
    private let thumbnailSkeleton = SkeletonView()
    private let badgeSkeleton = SkeletonView()
    private let titleSkeleton = SkeletonView()
    private let dateSkeleton = SkeletonView()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        contentView.backgroundColor = .clear
        
        // Thumbnail skeleton
        thumbnailSkeleton.layer.cornerRadius = 12
        thumbnailSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailSkeleton)
        
        // Badge skeleton (on top of thumbnail)
        badgeSkeleton.layer.cornerRadius = 4
        badgeSkeleton.translatesAutoresizingMaskIntoConstraints = false
        thumbnailSkeleton.addSubview(badgeSkeleton)
        
        // Title skeleton
        titleSkeleton.layer.cornerRadius = 6
        titleSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleSkeleton)
        
        // Date skeleton
        dateSkeleton.layer.cornerRadius = 6
        dateSkeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateSkeleton)
        
        NSLayoutConstraint.activate([
            // Thumbnail - 16:9 aspect ratio
            thumbnailSkeleton.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnailSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnailSkeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnailSkeleton.heightAnchor.constraint(equalTo: thumbnailSkeleton.widthAnchor, multiplier: 9.0/16.0),
            
            // Badge on thumbnail
            badgeSkeleton.topAnchor.constraint(equalTo: thumbnailSkeleton.topAnchor, constant: 8),
            badgeSkeleton.leadingAnchor.constraint(equalTo: thumbnailSkeleton.leadingAnchor, constant: 8),
            badgeSkeleton.widthAnchor.constraint(equalToConstant: 50),
            badgeSkeleton.heightAnchor.constraint(equalToConstant: 20),
            
            // Title below thumbnail
            titleSkeleton.topAnchor.constraint(equalTo: thumbnailSkeleton.bottomAnchor, constant: 10),
            titleSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleSkeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -60),
            titleSkeleton.heightAnchor.constraint(equalToConstant: 16),
            
            // Date below title
            dateSkeleton.topAnchor.constraint(equalTo: titleSkeleton.bottomAnchor, constant: 6),
            dateSkeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dateSkeleton.widthAnchor.constraint(equalToConstant: 80),
            dateSkeleton.heightAnchor.constraint(equalToConstant: 12),
            dateSkeleton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
        
        // Start animations
        startAnimations()
    }
    
    private func startAnimations() {
        [thumbnailSkeleton, badgeSkeleton, titleSkeleton, dateSkeleton].forEach {
            $0.startAnimating()
        }
    }
    
    func restartAnimations() {
        [thumbnailSkeleton, badgeSkeleton, titleSkeleton, dateSkeleton].forEach {
            $0.stopAnimating()
            $0.startAnimating()
        }
    }
}

// MARK: - Profile Empty Cell
final class ProfileEmptyCell: UICollectionViewCell {
    static let reuseIdentifier = "ProfileEmptyCell"
    
    // MARK: - UI Components
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        // Icon
        iconImageView.image = UIImage(systemName: "video.slash")
        iconImageView.tintColor = .secondaryLabel.withAlphaComponent(0.5)
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(iconImageView)
        
        // Title
        titleLabel.text = "No streams yet"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        stackView.addArrangedSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.text = "Your live streams will appear here"
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        stackView.addArrangedSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
            
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),
        ])
    }
}
