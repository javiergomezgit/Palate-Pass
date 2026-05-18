// MARK: – MVVM | View
// UITableViewCell that renders one FoodEntry.
// Place name is the primary label. No item name field.

import UIKit

final class EntryCell: UITableViewCell {

    static let reuseID = "EntryCell"

    // MARK: – UI

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 16
        v.layer.shadowColor  = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.14).cgColor
        v.layer.shadowOpacity = 1
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: 0, height: 2)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = .secondarySystemBackground
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let categoryPill: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 9
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Place name is now the primary label
    private let placeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .bold)
        l.numberOfLines = 1
        return l
    }()

    private let starView: StarRatingView = {
        let sv = StarRatingView()
        sv.isInteractive = false
        return sv
    }()

    private let commentLabel: UILabel = {
        let l = UILabel()
        l.font = .italicSystemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private let visibilityLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.layer.cornerRadius = 7
        l.clipsToBounds = true
        l.textAlignment = .center
        return l
    }()

    private let dateLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = .tertiaryLabel
        l.textAlignment = .right
        return l
    }()

    private let shareButton: UIButton = {
        let b = UIButton(type: .system)
        let img = UIImage(systemName: "square.and.arrow.up",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        b.setImage(img, for: .normal)
        b.tintColor = .tertiaryLabel
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    /// Called when the share button is tapped. Receives the cell's current thumbnail.
    var onShare: ((UIImage?) -> Void)?

    // MARK: – Reuse / cancellation

    /// Tracks the in-flight download so we can cancel it when the cell is reused.
    private var imageTask: URLSessionDataTask?

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        thumbImageView.image = nil
        onShare = nil
    }

    @objc private func shareTapped() {
        onShare?(thumbImageView.image)
    }

    // MARK: – Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Layout

    private func setup() {
        backgroundColor = .clear
        selectionStyle  = .none

        let starRow = UIStackView(arrangedSubviews: [starView, UIView()])
        starRow.axis = .horizontal
        starRow.alignment = .center

        // Top row: place (primary text) + date
        let topRow = UIStackView(arrangedSubviews: [placeLabel, dateLabel])
        topRow.axis = .horizontal
        topRow.spacing = 6
        topRow.alignment = .center

        let bottomRow = UIStackView(arrangedSubviews: [visibilityLabel, UIView()])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 4

        let textStack = UIStackView(arrangedSubviews: [topRow, starRow, commentLabel, bottomRow])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        contentView.addSubview(cardView)
        cardView.addSubview(thumbImageView)
        cardView.addSubview(categoryPill)
        cardView.addSubview(textStack)
        cardView.addSubview(shareButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            thumbImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            thumbImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            thumbImageView.widthAnchor.constraint(equalToConstant: 62),
            thumbImageView.heightAnchor.constraint(equalToConstant: 62),
            thumbImageView.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 12),
            thumbImageView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),

            categoryPill.leadingAnchor.constraint(equalTo: thumbImageView.leadingAnchor),
            categoryPill.topAnchor.constraint(equalTo: thumbImageView.topAnchor),
            categoryPill.heightAnchor.constraint(equalToConstant: 18),
            categoryPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),

            // Share button — right edge, vertically centered
            shareButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            shareButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 28),
            shareButton.heightAnchor.constraint(equalToConstant: 28),

            // Text stack stops before the share button
            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -6),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }

    // MARK: – Configure

    func configure(with entry: FoodEntry) {
        placeLabel.text = entry.placeName.isEmpty ? "Unknown place" : entry.placeName

        let color = Theme.categoryColor(entry.category)
        categoryPill.text = " \(entry.category.emoji) "
        categoryPill.backgroundColor = color

        starView.rating = entry.rating

        commentLabel.text    = entry.comment.isEmpty ? nil : "\"\(entry.comment)\""
        commentLabel.isHidden = entry.comment.isEmpty

        applyVisibility(entry.visibility)

        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        dateLabel.text = fmt.string(from: entry.checkInDate)

        loadThumbnail(entry: entry, fallbackColor: color)
    }

    // MARK: – Image loading

    private func loadThumbnail(entry: FoodEntry, fallbackColor: UIColor) {
        // 1. Local image (created on this device)
        if let path = entry.imagePath, let img = DataManager.shared.loadImage(named: path) {
            applyThumbnail(img)
            return
        }

        // 2. Remote URL from Firebase Storage
        if let urlString = entry.imageURL {
            // Show placeholder while loading
            applyPlaceholder(color: fallbackColor)

            // Check in-memory cache first (no flicker on scroll-back)
            if let cached = ImageLoader.shared.cachedImage(for: urlString) {
                applyThumbnail(cached)
                return
            }

            imageTask = ImageLoader.shared.load(urlString: urlString) { [weak self] image in
                if let image {
                    self?.applyThumbnail(image)
                }
                // If download fails, placeholder stays — no crash
            }
            return
        }

        // 3. No image at all
        applyPlaceholder(color: fallbackColor)
    }

    private func applyThumbnail(_ image: UIImage) {
        thumbImageView.image           = image
        thumbImageView.tintColor       = nil
        thumbImageView.backgroundColor = .secondarySystemBackground
    }

    private func applyPlaceholder(color: UIColor) {
        thumbImageView.image           = UIImage(systemName: "fork.knife.circle.fill")
        thumbImageView.tintColor       = color.withAlphaComponent(0.7)
        thumbImageView.backgroundColor = color.withAlphaComponent(0.1)
    }

    private func applyVisibility(_ visibility: EntryVisibility) {
        switch visibility {
        case .public:
            visibilityLabel.text            = " 🌍 "
            visibilityLabel.backgroundColor = Theme.accentLight
        case .friends:
            visibilityLabel.text            = " 👥 "
            visibilityLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        case .private:
            visibilityLabel.text            = " 🔒 "
            visibilityLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
        }
    }
}
