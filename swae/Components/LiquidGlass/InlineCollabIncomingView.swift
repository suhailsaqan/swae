import UIKit

/// Inline view for incoming collab call banner — accept/decline buttons.
/// Shown inside the MorphingGlassModal when an invite arrives.
class InlineCollabIncomingView: UIView {

    // MARK: - Callbacks

    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    // MARK: - Views

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let acceptButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
    private let buttonStack = UIStackView()

    // MARK: - Init

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
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Incoming Collab Invite"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        subtitleLabel.textAlignment = .center
        addSubview(subtitleLabel)

        // Decline button
        declineButton.translatesAutoresizingMaskIntoConstraints = false
        declineButton.setTitle("Decline", for: .normal)
        declineButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        declineButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        declineButton.tintColor = .white
        declineButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        declineButton.layer.cornerRadius = 20
        declineButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)

        // Accept button
        acceptButton.translatesAutoresizingMaskIntoConstraints = false
        acceptButton.setTitle("Accept", for: .normal)
        acceptButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
        acceptButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        acceptButton.tintColor = .white
        acceptButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.8)
        acceptButton.layer.cornerRadius = 20
        acceptButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 16
        buttonStack.distribution = .fillEqually
        buttonStack.addArrangedSubview(declineButton)
        buttonStack.addArrangedSubview(acceptButton)
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            buttonStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - Public

    func configure(streamTitle: String) {
        subtitleLabel.text = streamTitle
    }

    // MARK: - Actions

    @objc private func acceptTapped() { onAccept?() }
    @objc private func declineTapped() { onDecline?() }
}
