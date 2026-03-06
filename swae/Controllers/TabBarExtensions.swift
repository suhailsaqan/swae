//
//  TabBarExtensions.swift
//  swae
//
//  Shared extensions for tab bar controllers
//

import UIKit

// MARK: - UIView Extensions

extension UIView {
    func pinToSuperview(edges: UIRectEdge = .all, padding: CGFloat = 0, safeArea: Bool = false) {
        guard let superview = superview else { return }

        translatesAutoresizingMaskIntoConstraints = false

        if edges.contains(.top) {
            topAnchor.constraint(
                equalTo: safeArea ? superview.safeAreaLayoutGuide.topAnchor : superview.topAnchor,
                constant: padding
            ).isActive = true
        }
        if edges.contains(.bottom) {
            bottomAnchor.constraint(
                equalTo: safeArea
                    ? superview.safeAreaLayoutGuide.bottomAnchor : superview.bottomAnchor,
                constant: -padding
            ).isActive = true
        }
        if edges.contains(.left) {
            leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: padding).isActive =
                true
        }
        if edges.contains(.right) {
            trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -padding)
                .isActive = true
        }
    }

    func constrainToSize(height: CGFloat? = nil, width: CGFloat? = nil) -> UIView {
        translatesAutoresizingMaskIntoConstraints = false
        if let height = height {
            heightAnchor.constraint(equalToConstant: height).isActive = true
        }
        if let width = width {
            widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return self
    }

    func findAllSubviews<T: UIView>(ofType type: T.Type = T.self) -> [T] {
        var result: [T] = []

        for subview in subviews {
            if let typedSubview = subview as? T {
                result.append(typedSubview)
            }
            result.append(contentsOf: subview.findAllSubviews(ofType: type))
        }

        return result
    }
}

// MARK: - Array Safe Access

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
