//
//  AttachmentOptionsView.swift
//  swae
//
//  Content view for the expanded attachment modal
//  Contains a grid of attachment option buttons
//

import UIKit

/// The expanded content that appears inside the morphing attachment modal
class AttachmentOptionsView: UIView {
    
    // MARK: - Properties
    
    private let grabHandle = UIView()
    private let buttonGrid = UIStackView()
    
    // Buttons
    private var cameraButton: AttachmentOptionButton!
    private var photoLibraryButton: AttachmentOptionButton!
    private var documentButton: AttachmentOptionButton!
    private var locationButton: AttachmentOptionButton!
    private var contactButton: AttachmentOptionButton!
    private var pollButton: AttachmentOptionButton!
    
    // MARK: - Callbacks
    
    var onCameraTapped: (() -> Void)?
    var onPhotoLibraryTapped: (() -> Void)?
    var onDocumentTapped: (() -> Void)?
    var onLocationTapped: (() -> Void)?
    var onContactTapped: (() -> Void)?
    var onPollTapped: (() -> Void)?
    
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

        // Grab handle at top
        grabHandle.translatesAutoresizingMaskIntoConstraints = false
        grabHandle.backgroundColor = UIColor(white: 1.0, alpha: 0.4)
        grabHandle.layer.cornerRadius = 2.5
        addSubview(grabHandle)
        
        // Create buttons
        cameraButton = AttachmentOptionButton(symbolName: "camera.fill", title: "Camera")
        photoLibraryButton = AttachmentOptionButton(symbolName: "photo.fill", title: "Photos")
        documentButton = AttachmentOptionButton(symbolName: "doc.fill", title: "Document")
        locationButton = AttachmentOptionButton(symbolName: "location.fill", title: "Location")
        contactButton = AttachmentOptionButton(symbolName: "person.crop.circle.fill", title: "Contact")
        pollButton = AttachmentOptionButton(symbolName: "chart.bar.fill", title: "Poll")
        
        // Wire up actions
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)
        photoLibraryButton.addTarget(self, action: #selector(photoLibraryTapped), for: .touchUpInside)
        documentButton.addTarget(self, action: #selector(documentTapped), for: .touchUpInside)
        locationButton.addTarget(self, action: #selector(locationTapped), for: .touchUpInside)
        contactButton.addTarget(self, action: #selector(contactTapped), for: .touchUpInside)
        pollButton.addTarget(self, action: #selector(pollTapped), for: .touchUpInside)
        
        // Button grid - vertical stack of rows
        buttonGrid.axis = .vertical
        buttonGrid.spacing = 24
        buttonGrid.distribution = .fillEqually
        buttonGrid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonGrid)
        
        // Row 1: Camera, Photos, Document
        let row1 = createRow([cameraButton, photoLibraryButton, documentButton])
        
        // Row 2: Location, Contact, Poll
        let row2 = createRow([locationButton, contactButton, pollButton])
        
        buttonGrid.addArrangedSubview(row1)
        buttonGrid.addArrangedSubview(row2)
        
        NSLayoutConstraint.activate([
            // Grab handle
            grabHandle.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            grabHandle.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabHandle.widthAnchor.constraint(equalToConstant: 36),
            grabHandle.heightAnchor.constraint(equalToConstant: 5),
            
            // Button grid
            buttonGrid.topAnchor.constraint(equalTo: grabHandle.bottomAnchor, constant: 32),
            buttonGrid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            buttonGrid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttonGrid.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
        ])
    }
    
    private func createRow(_ buttons: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 16
        return row
    }
    
    // MARK: - Actions
    
    @objc private func cameraTapped() { onCameraTapped?() }
    @objc private func photoLibraryTapped() { onPhotoLibraryTapped?() }
    @objc private func documentTapped() { onDocumentTapped?() }
    @objc private func locationTapped() { onLocationTapped?() }
    @objc private func contactTapped() { onContactTapped?() }
    @objc private func pollTapped() { onPollTapped?() }
}
