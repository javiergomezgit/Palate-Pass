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

    /// Shown while the entry has changes waiting to upload.
    private let syncBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = .systemOrange
        l.text = "  ↑ Not synced  "
        l.layer.cornerRadius = 7
        l.clipsToBounds = true
        l.textAlignment = .center
        l.setContentHuggingPriority(.required, for: .horizontal)
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

    /// Bumped on every configure and reuse. An async thumbnail whose generation no
    /// longer matches is dropped, so a late decode can't paint onto another row.
    private var thumbGeneration = 0

    /// Shared: building a DateFormatter per cell was measurable during table reloads.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Thumbnail is displayed at 62 pt; decode at 3x for the densest screens.
    private static let thumbMaxPixel: CGFloat = 62 * 3

    override func prepareForReuse() {
        super.prepareForReuse()
        clear()
    }

    /// Resets every field. Also used when the data source has no entry for a row,
    /// so a recycled cell can never be shown still carrying another entry's data.
    func clear() {
        thumbGeneration += 1
        imageTask?.cancel()
        imageTask = nil

        placeLabel.text                 = nil
        commentLabel.text               = nil
        commentLabel.isHidden           = true
        dateLabel.text                  = nil
        categoryPill.text               = nil
        categoryPill.backgroundColor    = .clear
        visibilityLabel.text            = nil
        visibilityLabel.backgroundColor = .clear
        syncBadge.isHidden              = true
        starView.rating                 = 0
        thumbImageView.image            = nil
        thumbImageView.tintColor        = nil
        thumbImageView.backgroundColor  = .secondarySystemBackground
        onShare                         = nil
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

        let bottomRow = UIStackView(arrangedSubviews: [visibilityLabel, syncBadge, UIView()])
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

    func configure(with pc: PlaceCheckin, isPending: Bool = false) {
        thumbGeneration += 1
        imageTask?.cancel()
        imageTask = nil

        placeLabel.text = pc.place.name.isEmpty ? "Unknown place" : pc.place.name
        syncBadge.isHidden = !isPending

        let color = Theme.categoryColor(pc.place.foodCategory)
        categoryPill.text = " \(pc.place.foodCategory.emoji) "
        categoryPill.backgroundColor = color

        starView.rating = pc.checkin.personalRating

        commentLabel.text     = pc.checkin.personalComment.isEmpty ? nil : "\"\(pc.checkin.personalComment)\""
        commentLabel.isHidden = pc.checkin.personalComment.isEmpty

        applyVisibility(pc.checkin.visibility)

        dateLabel.text = Self.dateFormatter.string(from: pc.checkin.checkedInAt)

        loadThumbnail(pc: pc, fallbackColor: color)
    }

    // MARK: – Image loading

    private func loadThumbnail(pc: PlaceCheckin, fallbackColor: UIColor) {
        let generation = thumbGeneration

        // 1. Local image (created on this device). Full-resolution JPEGs are decoded
        //    off the main thread and downsampled, so a reload never blocks on disk I/O.
        if let path = pc.checkin.imagePaths.first {
            if let cached = ImageLoader.shared.cachedThumbnail(named: path, maxPixel: Self.thumbMaxPixel) {
                applyThumbnail(cached)
                return
            }

            applyPlaceholder(color: fallbackColor)
            ImageLoader.shared.loadThumbnail(named: path, maxPixel: Self.thumbMaxPixel) { [weak self] image in
                guard let self, self.thumbGeneration == generation, let image else { return }
                self.applyThumbnail(image)
            }
            return
        }

        // 2. Remote URL from Firebase Storage
        if let urlString = pc.checkin.imageURLs.first {
            // Show placeholder while loading
            applyPlaceholder(color: fallbackColor)

            // Check in-memory cache first (no flicker on scroll-back)
            if let cached = ImageLoader.shared.cachedImage(for: urlString) {
                applyThumbnail(cached)
                return
            }

            imageTask = ImageLoader.shared.load(urlString: urlString) { [weak self] image in
                guard let self, self.thumbGeneration == generation, let image else { return }
                // If download fails, placeholder stays — no crash
                self.applyThumbnail(image)
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

    private func applyVisibility(_ visibility: Visibility) {
        switch visibility {
        case .public:
            visibilityLabel.text            = " 🌍 "
            visibilityLabel.backgroundColor = Theme.accentLight
        case .shared:
            visibilityLabel.text            = " 👥 "
            visibilityLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        case .private:
            visibilityLabel.text            = " 🔒 "
            visibilityLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
        }
    }
}
