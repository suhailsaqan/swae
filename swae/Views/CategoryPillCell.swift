//
//  CategoryPillCell.swift
//  swae
//
//  Horizontal pill cell for the category navigation bar.
//  SF Symbol icon + label, rounded rect, tappable with selected state.
//

import UIKit

final class CategoryPillCell: UICollectionViewCell {
    static let reuseIdentifier = "CategoryPillCell"

    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()

    /// "All" pill uses this to show a special state
    private(set) var categoryId: String?

    /// Tracks whether this pill is visually active (independent of UICollectionView selection)
    private var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.layer.cornerRadius = 18
        contentView.clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .label
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func configure(with category: StreamCategory, isActive: Bool) {
        categoryId = category.id
        self.isActive = isActive
        iconView.image = UIImage(systemName: category.icon)
        iconView.isHidden = false
        label.text = category.name
        updateAppearance()
    }

    /// Configure as the "All" reset pill
    func configureAsAll(isActive: Bool) {
        categoryId = nil
        self.isActive = isActive
        iconView.image = UIImage(systemName: "square.grid.2x2")
        iconView.isHidden = false
        label.text = "All"
        updateAppearance()
    }

    private func updateAppearance() {
        if isActive {
            contentView.backgroundColor = .white
            label.textColor = .black
            iconView.tintColor = .black
        } else {
            contentView.backgroundColor = .secondarySystemBackground
            label.textColor = .label
            iconView.tintColor = .label
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        categoryId = nil
        isActive = false
    }
}
