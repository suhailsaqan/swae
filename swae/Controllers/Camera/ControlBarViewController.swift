//
//  ControlBarViewController.swift
//  swae
//
//  UIKit-based control bar
//  The actual Go Live orb is rendered in MorphingOrbContainerView (full screen)
//  This controller provides the control bar background and optional labels
//

import UIKit

// MARK: - ControlBarViewController

class ControlBarViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var model: Model?
    
    // Optional label below orb position
    private var goLiveLabel: UILabel?
    
    // MARK: - Initialization
    
    init(model: Model) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        view.backgroundColor = .clear
        
        // Optional: Add "GO LIVE" label below orb position
        // The orb itself is rendered by MorphingOrbContainerView
        let label = UILabel()
        label.text = "GO LIVE"
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white.withAlphaComponent(0.5)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        
        goLiveLabel = label
    }
    
    // MARK: - Public Methods
    
    func updateLabel(isLive: Bool) {
        goLiveLabel?.text = isLive ? "LIVE" : "GO LIVE"
        goLiveLabel?.textColor = isLive 
            ? UIColor.red.withAlphaComponent(0.8) 
            : UIColor.white.withAlphaComponent(0.5)
    }
}
