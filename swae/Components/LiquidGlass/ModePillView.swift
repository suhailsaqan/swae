import UIKit

/// The VIDEO | PHOTO mode selector pill with liquid glass
/// This is the collapsed state that morphs into the expanded modal on swipe up
class ModePillView: UIView {
    
    // MARK: - Properties
    
    private var glassContainer: GlassContainerView!
    private let videoLabel = UILabel()
    private let photoLabel = UILabel()
    private var selectorGlass: GlassContainerView!
    
    var isPhotoSelected: Bool = true {
        didSet { updateSelection(animated: false) }
    }
    
    var onModeChanged: ((Bool) -> Void)? // true = photo, false = video
    
    // MARK: - Constants
    
    static let pillWidth: CGFloat = 180
    static let pillHeight: CGFloat = 44
    static let pillCornerRadius: CGFloat = 22
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        
        // Main pill container - liquid glass
        glassContainer = GlassFactory.makeGlassView(cornerRadius: Self.pillCornerRadius)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassContainer)
        
        // Selector highlight - also liquid glass (nested)
        selectorGlass = GlassFactory.makeGlassView(cornerRadius: 18)
        selectorGlass.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.glassContentView.addSubview(selectorGlass)
        
        // Video label
        videoLabel.translatesAutoresizingMaskIntoConstraints = false
        videoLabel.text = "VIDEO"
        videoLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        videoLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        videoLabel.textAlignment = .center
        glassContainer.glassContentView.addSubview(videoLabel)
        
        // Photo label
        photoLabel.translatesAutoresizingMaskIntoConstraints = false
        photoLabel.text = "PHOTO"
        photoLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        photoLabel.textColor = .systemYellow
        photoLabel.textAlignment = .center
        glassContainer.glassContentView.addSubview(photoLabel)
        
        NSLayoutConstraint.activate([
            // Glass container fills self
            glassContainer.topAnchor.constraint(equalTo: topAnchor),
            glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Self size
            widthAnchor.constraint(equalToConstant: Self.pillWidth),
            heightAnchor.constraint(equalToConstant: Self.pillHeight),
            
            // Labels
            videoLabel.leadingAnchor.constraint(equalTo: glassContainer.glassContentView.leadingAnchor),
            videoLabel.centerYAnchor.constraint(equalTo: glassContainer.glassContentView.centerYAnchor),
            videoLabel.widthAnchor.constraint(equalTo: glassContainer.glassContentView.widthAnchor, multiplier: 0.5),
            
            photoLabel.trailingAnchor.constraint(equalTo: glassContainer.glassContentView.trailingAnchor),
            photoLabel.centerYAnchor.constraint(equalTo: glassContainer.glassContentView.centerYAnchor),
            photoLabel.widthAnchor.constraint(equalTo: glassContainer.glassContentView.widthAnchor, multiplier: 0.5),
        ])
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectorFrame(animated: false)
    }
    
    // MARK: - Selection
    
    private func updateSelectorFrame(animated: Bool) {
        let containerBounds = glassContainer.glassContentView.bounds
        guard containerBounds.width > 0 else { return }
        
        let selectorWidth = containerBounds.width * 0.48 - 8
        let selectorHeight: CGFloat = 36
        let y = (containerBounds.height - selectorHeight) / 2
        let targetX: CGFloat = isPhotoSelected ? (containerBounds.width - selectorWidth - 4) : 4
        
        let frame = CGRect(x: targetX, y: y, width: selectorWidth, height: selectorHeight)
        
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.allowUserInteraction]) {
                self.selectorGlass.frame = frame
            }
        } else {
            selectorGlass.frame = frame
        }
    }
    
    private func updateSelection(animated: Bool) {
        updateSelectorFrame(animated: animated)
        
        let photoColor = isPhotoSelected ? UIColor.systemYellow : UIColor(white: 1.0, alpha: 0.6)
        let videoColor = isPhotoSelected ? UIColor(white: 1.0, alpha: 0.6) : UIColor.systemYellow
        
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.photoLabel.textColor = photoColor
                self.videoLabel.textColor = videoColor
            }
        } else {
            photoLabel.textColor = photoColor
            videoLabel.textColor = videoColor
        }
    }
    
    func setMode(photo: Bool, animated: Bool) {
        guard isPhotoSelected != photo else { return }
        isPhotoSelected = photo
        updateSelection(animated: animated)
        onModeChanged?(photo)
    }
    
    // MARK: - Gesture
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let tappedPhoto = location.x > bounds.width * 0.5
        setMode(photo: tappedPhoto, animated: true)
    }
}
