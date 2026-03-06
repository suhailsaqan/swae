//
//  EditProfileHeroView.swift
//  swae
//
//  Banner + Profile Picture section for Edit Profile
//

import Kingfisher
import UIKit

protocol EditProfileHeroViewDelegate: AnyObject {
    func heroViewDidTapBanner(_ heroView: EditProfileHeroView)
    func heroViewDidTapProfilePicture(_ heroView: EditProfileHeroView)
}

final class EditProfileHeroView: UIView {
    
    // MARK: - Constants
    private enum Layout {
        static let bannerHeight: CGFloat = 150
        static let profilePicSize: CGFloat = 100
        static let profilePicBorderWidth: CGFloat = 4
        static let profilePicOverlap: CGFloat = 50
        static let cameraOverlaySize: CGFloat = 28
    }
    
    // MARK: - Properties
    weak var delegate: EditProfileHeroViewDelegate?
    
    private var bannerShimmerLayer: CAGradientLayer?
    private var profileShimmerLayer: CAGradientLayer?
    
    // MARK: - UI Components
    
    // Banner
    private let bannerContainer = UIView()
    private let bannerImageView = UIImageView()
    private let bannerOverlay = UIView()
    private let bannerCameraStack = UIStackView()
    private let bannerCameraIcon = UIImageView()
    private let bannerCameraLabel = UILabel()
    private let bannerGradientLayer = CAGradientLayer()
    
    // Profile Picture
    private let profilePicContainer = UIView()
    private let profilePicImageView = UIImageView()
    private let profilePicCameraOverlay = UIView()
    private let profilePicCameraIcon = UIImageView()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        bannerGradientLayer.frame = bannerImageView.bounds
    }
    
    // MARK: - Setup
    private func setupUI() {
        setupBanner()
        setupProfilePicture()
        setupGestures()
    }
    
    private func setupBanner() {
        // Banner container
        bannerContainer.clipsToBounds = true
        bannerContainer.layer.cornerRadius = 16
        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerContainer)
        
        // Banner image
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.backgroundColor = .systemGray5
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(bannerImageView)
        
        // Default gradient background
        bannerGradientLayer.colors = [
            UIColor.editProfilePurple.cgColor,
            UIColor.systemIndigo.cgColor
        ]
        bannerGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        bannerGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        bannerImageView.layer.addSublayer(bannerGradientLayer)
        
        // Dark overlay
        bannerOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        bannerOverlay.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(bannerOverlay)
        
        // Camera icon and label stack
        bannerCameraStack.axis = .vertical
        bannerCameraStack.alignment = .center
        bannerCameraStack.spacing = 4
        bannerCameraStack.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(bannerCameraStack)
        
        bannerCameraIcon.image = UIImage(systemName: "camera.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium))
        bannerCameraIcon.tintColor = .white
        bannerCameraIcon.contentMode = .scaleAspectFit
        
        bannerCameraLabel.text = "Change Banner"
        bannerCameraLabel.font = .systemFont(ofSize: 13, weight: .medium)
        bannerCameraLabel.textColor = .white
        
        bannerCameraStack.addArrangedSubview(bannerCameraIcon)
        bannerCameraStack.addArrangedSubview(bannerCameraLabel)
        
        NSLayoutConstraint.activate([
            bannerContainer.topAnchor.constraint(equalTo: topAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerContainer.heightAnchor.constraint(equalToConstant: Layout.bannerHeight),
            
            bannerImageView.topAnchor.constraint(equalTo: bannerContainer.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor),
            bannerImageView.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            
            bannerOverlay.topAnchor.constraint(equalTo: bannerContainer.topAnchor),
            bannerOverlay.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor),
            bannerOverlay.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor),
            bannerOverlay.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            
            bannerCameraStack.centerXAnchor.constraint(equalTo: bannerContainer.centerXAnchor),
            bannerCameraStack.centerYAnchor.constraint(equalTo: bannerContainer.centerYAnchor),
        ])
        
        // Accessibility
        bannerContainer.isAccessibilityElement = true
        bannerContainer.accessibilityLabel = "Change banner image"
        bannerContainer.accessibilityTraits = .button
    }
    
    private func setupProfilePicture() {
        // Profile pic container
        profilePicContainer.backgroundColor = .clear
        profilePicContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(profilePicContainer)
        
        // Profile pic image
        profilePicImageView.contentMode = .scaleAspectFill
        profilePicImageView.clipsToBounds = true
        profilePicImageView.layer.cornerRadius = Layout.profilePicSize / 2
        profilePicImageView.layer.borderWidth = Layout.profilePicBorderWidth
        profilePicImageView.layer.borderColor = UIColor.systemBackground.cgColor
        profilePicImageView.backgroundColor = .systemGray5
        profilePicImageView.image = UIImage(named: "swae")
        profilePicImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Shadow
        profilePicContainer.layer.shadowColor = UIColor.black.cgColor
        profilePicContainer.layer.shadowOffset = CGSize(width: 0, height: 4)
        profilePicContainer.layer.shadowRadius = 12
        profilePicContainer.layer.shadowOpacity = 0.15
        
        profilePicContainer.addSubview(profilePicImageView)
        
        // Camera overlay
        profilePicCameraOverlay.backgroundColor = .editProfilePurple
        profilePicCameraOverlay.layer.cornerRadius = Layout.cameraOverlaySize / 2
        profilePicCameraOverlay.translatesAutoresizingMaskIntoConstraints = false
        profilePicContainer.addSubview(profilePicCameraOverlay)
        
        profilePicCameraIcon.image = UIImage(systemName: "camera.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        profilePicCameraIcon.tintColor = .white
        profilePicCameraIcon.contentMode = .scaleAspectFit
        profilePicCameraIcon.translatesAutoresizingMaskIntoConstraints = false
        profilePicCameraOverlay.addSubview(profilePicCameraIcon)
        
        NSLayoutConstraint.activate([
            profilePicContainer.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor, constant: -Layout.profilePicOverlap),
            profilePicContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            profilePicContainer.widthAnchor.constraint(equalToConstant: Layout.profilePicSize),
            profilePicContainer.heightAnchor.constraint(equalToConstant: Layout.profilePicSize),
            profilePicContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            profilePicImageView.topAnchor.constraint(equalTo: profilePicContainer.topAnchor),
            profilePicImageView.leadingAnchor.constraint(equalTo: profilePicContainer.leadingAnchor),
            profilePicImageView.trailingAnchor.constraint(equalTo: profilePicContainer.trailingAnchor),
            profilePicImageView.bottomAnchor.constraint(equalTo: profilePicContainer.bottomAnchor),
            
            profilePicCameraOverlay.trailingAnchor.constraint(equalTo: profilePicContainer.trailingAnchor),
            profilePicCameraOverlay.bottomAnchor.constraint(equalTo: profilePicContainer.bottomAnchor),
            profilePicCameraOverlay.widthAnchor.constraint(equalToConstant: Layout.cameraOverlaySize),
            profilePicCameraOverlay.heightAnchor.constraint(equalToConstant: Layout.cameraOverlaySize),
            
            profilePicCameraIcon.centerXAnchor.constraint(equalTo: profilePicCameraOverlay.centerXAnchor),
            profilePicCameraIcon.centerYAnchor.constraint(equalTo: profilePicCameraOverlay.centerYAnchor),
        ])
        
        // Accessibility
        profilePicContainer.isAccessibilityElement = true
        profilePicContainer.accessibilityLabel = "Change profile picture"
        profilePicContainer.accessibilityTraits = .button
    }
    
    private func setupGestures() {
        let bannerTap = UITapGestureRecognizer(target: self, action: #selector(bannerTapped(_:)))
        bannerContainer.addGestureRecognizer(bannerTap)
        bannerContainer.isUserInteractionEnabled = true
        
        let profileTap = UITapGestureRecognizer(target: self, action: #selector(profilePicTapped(_:)))
        profilePicContainer.addGestureRecognizer(profileTap)
        profilePicContainer.isUserInteractionEnabled = true
    }
    
    // MARK: - Actions
    @objc private func bannerTapped(_ gesture: UITapGestureRecognizer) {
        delegate?.heroViewDidTapBanner(self)
    }
    
    @objc private func profilePicTapped(_ gesture: UITapGestureRecognizer) {
        delegate?.heroViewDidTapProfilePicture(self)
    }
    
    // MARK: - Public Methods
    func setBannerImage(url: URL?) {
        bannerShimmerLayer?.removeFromSuperlayer()
        
        if let url = url {
            bannerShimmerLayer = bannerImageView.addShimmerEffect()
            
            bannerImageView.kf.setImage(
                with: url,
                options: [
                    .transition(.fade(0.3)),
                    .cacheOriginalImage,
                    .backgroundDecode
                ]
            ) { [weak self] result in
                self?.bannerShimmerLayer?.removeFromSuperlayer()
                self?.bannerShimmerLayer = nil
                
                switch result {
                case .success:
                    self?.bannerGradientLayer.isHidden = true
                case .failure:
                    self?.bannerGradientLayer.isHidden = false
                }
            }
        } else {
            bannerGradientLayer.isHidden = false
            bannerImageView.image = nil
        }
    }
    
    func setProfileImage(url: URL?) {
        profileShimmerLayer?.removeFromSuperlayer()
        
        if let url = url {
            profileShimmerLayer = profilePicImageView.addShimmerEffect()
            
            profilePicImageView.kf.setImage(
                with: url,
                options: [
                    .transition(.fade(0.3)),
                    .cacheOriginalImage,
                    .processor(DownsamplingImageProcessor(size: CGSize(
                        width: Layout.profilePicSize * 2,
                        height: Layout.profilePicSize * 2
                    )))
                ]
            ) { [weak self] result in
                self?.profileShimmerLayer?.removeFromSuperlayer()
                self?.profileShimmerLayer = nil
                
                if case .failure = result {
                    self?.profilePicImageView.image = UIImage(named: "swae")
                }
            }
        } else {
            profilePicImageView.image = UIImage(named: "swae")
        }
    }
    
    func updateBorderColor() {
        profilePicImageView.layer.borderColor = UIColor.systemBackground.cgColor
    }
}
