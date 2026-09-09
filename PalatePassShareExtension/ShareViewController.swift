import UIKit
import MobileCoreServices
import ImageIO

private let appGroupID = "group.com.palatepass.app"

class ShareViewController: UIViewController {

    // MARK: – State

    private var sharedImage: UIImage?
    private var latitude:    Double?
    private var longitude:   Double?
    private var captureDate: Date?
    private var starRating:  Int = 0

    // MARK: – UI

    /// Shows the date the entry will be filed under, so it's clear the photo's own
    /// timestamp was picked up rather than "now".
    private let dateLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let sheet: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 24
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let handle: UIView = {
        let v = UIView()
        v.backgroundColor = .systemFill
        v.layer.cornerRadius = 2.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.keyboardDismissMode = .interactive
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let content: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let thumbView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameField: UITextField = {
        let f = UITextField()
        f.placeholder = "Place name (e.g. Blue Bottle Coffee)"
        f.font = .systemFont(ofSize: 16)
        f.borderStyle = .none
        f.returnKeyType = .next
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    private let commentView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 15)
        tv.isScrollEnabled = false
        tv.layer.cornerRadius = 10
        tv.backgroundColor = .secondarySystemBackground
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let commentPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "Comment (optional)"
        l.font = .systemFont(ofSize: 15)
        l.textColor = .placeholderText
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let starStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.distribution = .fillEqually
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let saveButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Save Entry"
        cfg.cornerStyle = .large
        cfg.baseBackgroundColor = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 1)
        cfg.baseForegroundColor = .white
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isEnabled = false
        return b
    }()

    private let cancelButton: UIButton = {
        var cfg = UIButton.Configuration.plain()
        cfg.title = "Cancel"
        cfg.baseForegroundColor = .secondaryLabel
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private var sheetBottomConstraint: NSLayoutConstraint!

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        setupUI()
        extractImage()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: – Layout

    private func setupUI() {
        view.addSubview(sheet)

        sheetBottomConstraint = sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.82),
            sheetBottomConstraint
        ])

        // Handle
        sheet.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 10),
            handle.centerXAnchor.constraint(equalTo: sheet.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5)
        ])

        // ScrollView
        sheet.addSubview(scrollView)
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sheet.safeAreaLayoutGuide.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        buildContent()

        // Tap outside to dismiss keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func buildContent() {
        // Image
        content.addSubview(thumbView)

        // Name field card
        let nameCard = makeCard()
        let nameLabel = makeSectionLabel("PLACE")
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameCard.addSubview(nameField)

        // Stars card
        let starsCard = makeCard()
        let starsLabel = makeSectionLabel("RATING")
        buildStars()

        // Comment card
        let commentCard = makeCard()
        let commentLabel = makeSectionLabel("COMMENT")
        commentCard.addSubview(commentView)
        commentCard.addSubview(commentPlaceholder)
        commentView.delegate = self

        // Buttons
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [saveButton, cancelButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        [nameCard, starsCard, commentCard, buttonStack,
         nameLabel, starsLabel, commentLabel, dateLabel].forEach { content.addSubview($0) }
        updateDateLabel()

        nameCard.addSubview(nameField)
        starsCard.addSubview(starStack)

        NSLayoutConstraint.activate([
            // Thumb
            thumbView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            thumbView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            thumbView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            thumbView.heightAnchor.constraint(equalToConstant: 180),

            // Capture date
            dateLabel.topAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: 10),
            dateLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            // Place
            nameLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            nameCard.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            nameCard.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            nameCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            nameField.topAnchor.constraint(equalTo: nameCard.topAnchor, constant: 14),
            nameField.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor, constant: -16),
            nameField.bottomAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: -14),

            // Stars
            starsLabel.topAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: 16),
            starsLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            starsCard.topAnchor.constraint(equalTo: starsLabel.bottomAnchor, constant: 6),
            starsCard.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            starsCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            starStack.topAnchor.constraint(equalTo: starsCard.topAnchor, constant: 14),
            starStack.leadingAnchor.constraint(equalTo: starsCard.leadingAnchor, constant: 16),
            starStack.trailingAnchor.constraint(equalTo: starsCard.trailingAnchor, constant: -16),
            starStack.bottomAnchor.constraint(equalTo: starsCard.bottomAnchor, constant: -14),
            starStack.heightAnchor.constraint(equalToConstant: 40),

            // Comment
            commentLabel.topAnchor.constraint(equalTo: starsCard.bottomAnchor, constant: 16),
            commentLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            commentCard.topAnchor.constraint(equalTo: commentLabel.bottomAnchor, constant: 6),
            commentCard.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            commentCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            commentView.topAnchor.constraint(equalTo: commentCard.topAnchor, constant: 4),
            commentView.leadingAnchor.constraint(equalTo: commentCard.leadingAnchor, constant: 8),
            commentView.trailingAnchor.constraint(equalTo: commentCard.trailingAnchor, constant: -8),
            commentView.bottomAnchor.constraint(equalTo: commentCard.bottomAnchor, constant: -4),
            commentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

            commentPlaceholder.topAnchor.constraint(equalTo: commentView.topAnchor, constant: 18),
            commentPlaceholder.leadingAnchor.constraint(equalTo: commentView.leadingAnchor, constant: 20),

            // Buttons
            buttonStack.topAnchor.constraint(equalTo: commentCard.bottomAnchor, constant: 20),
            buttonStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),

            saveButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func buildStars() {
        for i in 1...5 {
            let btn = UIButton(type: .system)
            btn.tag = i
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            btn.setImage(UIImage(systemName: "star", withConfiguration: cfg), for: .normal)
            btn.tintColor = UIColor.systemYellow
            btn.addTarget(self, action: #selector(starTapped(_:)), for: .touchUpInside)
            starStack.addArrangedSubview(btn)
        }
    }

    // MARK: – Helpers

    private func makeCard() -> UIView {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 14
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    // MARK: – Image extraction

    private func extractImage() {
        guard
            let item     = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier("public.image")
            })
        else { return }

        provider.loadItem(forTypeIdentifier: "public.image", options: nil) { [weak self] data, _ in
            var image:    UIImage?
            var source:   CGImageSource?
            var fileDate: Date?

            // loadItem hands back a URL, raw Data, or an already-decoded UIImage
            // depending on the source. Only the first two carry metadata — a UIImage
            // has already lost it.
            if let url = data as? URL {
                image    = UIImage(contentsOfFile: url.path)
                source   = CGImageSourceCreateWithURL(url as CFURL, nil)
                fileDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            } else if let raw = data as? Data {
                image  = UIImage(data: raw)
                source = CGImageSourceCreateWithData(raw as CFData, nil)
            } else if let img = data as? UIImage {
                image = img
            }

            guard let image else { return }

            var latitude:  Double?
            var longitude: Double?
            var captured:  Date?

            if let source,
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {

                if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                    var lat = gps[kCGImagePropertyGPSLatitude  as String] as? Double
                    var lng = gps[kCGImagePropertyGPSLongitude as String] as? Double
                    if gps[kCGImagePropertyGPSLatitudeRef  as String] as? String == "S" { lat?  *= -1 }
                    if gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "W" { lng? *= -1 }
                    latitude  = lat
                    longitude = lng
                }

                captured = Self.captureDate(from: props)
            }

            // Screenshots and edited copies often carry no EXIF timestamp; the file's
            // own creation date is the next best thing.
            let resolved = captured ?? fileDate

            DispatchQueue.main.async {
                guard let self else { return }
                self.sharedImage = image
                self.latitude    = latitude
                self.longitude   = longitude
                self.captureDate = resolved
                self.thumbView.image = image
                self.updateDateLabel()
            }
        }
    }

    // MARK: – Capture date

    private func updateDateLabel() {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        fmt.doesRelativeDateFormatting = true
        if let captureDate {
            dateLabel.text = "📅 \(fmt.string(from: captureDate))"
        } else {
            dateLabel.text = "📅 \(fmt.string(from: Date())) · no photo date found"
        }
    }

    /// Pulls the moment the photo was taken out of its metadata.
    /// Prefers EXIF, then the TIFF tag, then the GPS clock.
    nonisolated private static func captureDate(from properties: [String: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        // EXIF timestamps are bare wall-clock readings with no zone. Newer files record
        // the original UTC offset next to them; without it, local time is the only
        // sensible reading — which is also what the photo appears to say in Photos.
        let offset = (exif?[kCGImagePropertyExifOffsetTimeOriginal  as String] as? String)
                  ?? (exif?[kCGImagePropertyExifOffsetTimeDigitized as String] as? String)

        let stamps = [
            exif?[kCGImagePropertyExifDateTimeOriginal  as String] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String,
            tiff?[kCGImagePropertyTIFFDateTime          as String] as? String
        ]
        for stamp in stamps.compactMap({ $0 }) {
            if let date = parseEXIFTimestamp(stamp, offset: offset) { return date }
        }

        // GPS time is always UTC, so it needs no offset guessing.
        if let gps  = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let day  = gps[kCGImagePropertyGPSDateStamp as String] as? String,
           let time = gps[kCGImagePropertyGPSTimeStamp as String] as? String {
            let fmt = DateFormatter()
            fmt.locale     = Locale(identifier: "en_US_POSIX")
            fmt.timeZone   = TimeZone(secondsFromGMT: 0)
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
            let seconds = time.split(separator: ".").first.map(String.init) ?? time
            if let date = fmt.date(from: "\(day) \(seconds)") { return date }
        }

        return nil
    }

    /// EXIF timestamps look like "2026:03:03 19:42:11".
    nonisolated private static func parseEXIFTimestamp(_ stamp: String, offset: String?) -> Date? {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.timeZone   = offset.flatMap(timeZone(fromEXIFOffset:)) ?? .current
        return fmt.date(from: stamp)
    }

    /// Parses an EXIF UTC offset such as "+02:00" or "-05:30".
    nonisolated private static func timeZone(fromEXIFOffset offset: String) -> TimeZone? {
        let parts = offset.split(separator: ":")
        guard parts.count == 2,
              let hours   = Int(parts[0]),
              let minutes = Int(parts[1])
        else { return nil }
        let sign = offset.hasPrefix("-") ? -1 : 1
        return TimeZone(secondsFromGMT: hours * 3600 + sign * minutes * 60)
    }

    // MARK: – Actions

    @objc private func starTapped(_ sender: UIButton) {
        starRating = sender.tag
        updateStars()
        updateSaveButton()
    }

    private func updateStars() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        starStack.arrangedSubviews.enumerated().forEach { i, view in
            guard let btn = view as? UIButton else { return }
            let filled = i < starRating
            btn.setImage(UIImage(systemName: filled ? "star.fill" : "star", withConfiguration: cfg), for: .normal)
        }
    }

    @objc private func nameChanged() { updateSaveButton() }

    private func updateSaveButton() {
        let hasName   = !(nameField.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let hasRating = starRating > 0
        saveButton.isEnabled = hasName && hasRating
    }

    @objc private func saveTapped() {
        let defaults = UserDefaults(suiteName: appGroupID)!
        defaults.set(sharedImage?.jpegData(compressionQuality: 0.8), forKey: "sharedImage")
        defaults.set(latitude,                                        forKey: "sharedLatitude")
        defaults.set(longitude,                                       forKey: "sharedLongitude")
        defaults.set(nameField.text ?? "",                            forKey: "sharedEntryName")
        defaults.set(starRating,                                      forKey: "sharedEntryRating")
        defaults.set(commentView.text ?? "",                          forKey: "sharedEntryComment")
        defaults.set(captureDate?.timeIntervalSince1970 ?? 0,         forKey: "sharedEntryDate")
        defaults.synchronize()

        // Animate confirmation then dismiss
        saveButton.configuration?.title = "Saved ✓"
        saveButton.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    // MARK: – Keyboard

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard
            let info     = notification.userInfo,
            let frame    = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        let keyboardHeight = view.bounds.height - frame.origin.y
        sheetBottomConstraint.constant = -max(0, keyboardHeight)
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }
}

// MARK: – UITextFieldDelegate

extension ShareViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commentView.becomeFirstResponder()
        return false
    }
}

// MARK: – UITextViewDelegate

extension ShareViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        commentPlaceholder.isHidden = !textView.text.isEmpty
    }
}
