// MARK: – MVVM | View
// Reusable star-rating control. Reports user taps through StarRatingViewDelegate.
// Knows nothing about models or ViewModels.

import UIKit

protocol StarRatingViewDelegate: AnyObject {
    func starRatingView(_ view: StarRatingView, didUpdateRating rating: Double)
}

final class StarRatingView: UIView {

    weak var delegate: StarRatingViewDelegate?
    var isInteractive = true

    var rating: Double = 0 {
        didSet { updateStars() }
    }

    // Fixed intrinsic size — prevents vertical and horizontal stretching in stack views
    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(starCount) * (starSize + spacing) - spacing, height: starSize)
    }

    private let starCount = 5
    private let starSize:  CGFloat = 26
    private let spacing:   CGFloat = 6
    private var starButtons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = spacing
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: starSize)
        ])

        for i in 0..<starCount {
            let btn = UIButton(type: .custom)
            btn.tag = i + 1
            btn.tintColor = Theme.accent
            btn.contentMode = .center
            btn.addTarget(self, action: #selector(starTapped(_:)), for: .touchUpInside)
            starButtons.append(btn)
            stack.addArrangedSubview(btn)
        }
        updateStars()
    }

    @objc private func starTapped(_ sender: UIButton) {
        guard isInteractive else { return }
        let tapped = Double(sender.tag)
        rating = (rating == tapped) ? tapped - 0.5 : tapped
        delegate?.starRatingView(self, didUpdateRating: rating)

        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }) { _ in
            UIView.animate(withDuration: 0.12) { sender.transform = .identity }
        }
    }

    private func updateStars() {
        let cfg = UIImage.SymbolConfiguration(pointSize: starSize - 2, weight: .medium)
        for btn in starButtons {
            let val = Double(btn.tag)
            let name: String
            if rating >= val {
                name = "star.fill"
            } else if rating >= val - 0.5 {
                name = "star.leadinghalf.filled"
            } else {
                name = "star"
            }
            btn.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        }
    }
}
