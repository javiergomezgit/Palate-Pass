// MARK: – MVVM | View
// Form for creating or editing a PlaceCheckin.
// Fields: photo, place (picker sheet), category, rating, check-in date, comment, visibility.

import UIKit
import CoreLocation
import MapKit

final class AddEntryViewController: UIViewController {

    // MARK: – MVVM

    private let viewModel: AddEntryViewModel

    init(viewModel: AddEntryViewModel = AddEntryViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: – Share Extension prefill (set before viewDidLoad)

    /// When set by SceneDelegate (Share Extension flow), skips live location request.
    var prefillCoordinate: CLLocationCoordinate2D?

    // MARK: – Location

    private let locationManager = CLLocationManager()

    // MARK: – UI

    private let scrollView  = UIScrollView()
    private let contentView = UIView()

    private lazy var photoGallery: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 90, height: 90)
        layout.minimumInteritemSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(PhotoGalleryAddCell.self,   forCellWithReuseIdentifier: PhotoGalleryAddCell.reuseID)
        cv.register(PhotoGalleryImageCell.self, forCellWithReuseIdentifier: PhotoGalleryImageCell.reuseID)
        cv.dataSource = self
        cv.delegate   = self
        return cv
    }()

    /// Tapping opens the PlacePickerViewController sheet. Not directly editable.
    private let placeField: UITextField = {
        let f = UITextField()
        f.placeholder  = "Tap to search…"
        f.font         = .systemFont(ofSize: 15)
        f.textAlignment = .left
        f.clearButtonMode = .never
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 0, y: 0, width: 30, height: 20)
        f.rightView = icon
        f.rightViewMode = .always
        return f
    }()

    private let categoryControl: UISegmentedControl = {
        let items = FoodCategory.allCases.map { $0.emoji }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        let bigFont = UIFont.systemFont(ofSize: 17, weight: .regular)
        sc.setTitleTextAttributes([.font: bigFont], for: .normal)
        sc.setTitleTextAttributes([.font: bigFont], for: .selected)
        return sc
    }()

    private let starView = StarRatingView()

    private let ratingValueLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = Theme.accent
        l.text = "–"
        return l
    }()

    private let checkInPicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode  = .dateAndTime
        dp.preferredDatePickerStyle = .compact
        dp.maximumDate     = Date()
        dp.tintColor       = Theme.accent
        return dp
    }()

    private let commentView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 15)
        tv.layer.cornerRadius = 10
        tv.layer.borderWidth  = 1
        tv.layer.borderColor  = UIColor.systemGray4.cgColor
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let commentPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "Add a comment (optional)"
        l.font = .systemFont(ofSize: 15)
        l.textColor = .placeholderText
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let visibilityControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["🔒 Private", "👥 Share", "🌍 Public"])
        sc.selectedSegmentIndex = 2
        sc.selectedSegmentTintColor = Theme.accent
        sc.setTitleTextAttributes(
            [.foregroundColor: UIColor.white,
             .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
        sc.setTitleTextAttributes(
            [.foregroundColor: Theme.accent,
             .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        return sc
    }()

    /// Read-only map preview shown after a place is selected.
    private lazy var locationMapView: MKMapView = {
        let mv = MKMapView()
        mv.layer.cornerRadius = 12
        mv.clipsToBounds = true
        mv.isHidden = true
        mv.isUserInteractionEnabled = false
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    private let locationPin = MKPointAnnotation()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.isEditing ? "Edit Entry" : "New Entry"
        view.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        let saveBtn = UIBarButtonItem(title: "Save", style: .done,
                                     target: self, action: #selector(saveTapped))
        saveBtn.tintColor = Theme.accent
        saveBtn.isEnabled = false
        navigationItem.rightBarButtonItem = saveBtn

        let cancelBtn = UIBarButtonItem(title: "Cancel", style: .plain,
                                       target: self, action: #selector(cancelTapped))
        cancelBtn.tintColor = .secondaryLabel
        navigationItem.leftBarButtonItem = cancelBtn

        setupScrollView()
        setupContent()
        addKeyboardDismissGesture()
        registerKeyboardObservers()
        configureLocationManager()
        bindViewModel()
        populateFormFromViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let coord = viewModel.location else { return }
        locationMapView.isHidden = false
        placePin(at: coord)
    }

    // MARK: – ViewModel bindings

    private func bindViewModel() {
        viewModel.onSaving = { [weak self] in
            self?.setSaveLoading(true)
        }

        viewModel.onSaveSuccess = { [weak self] in
            guard let self else { return }
            self.setSaveLoading(false)
            if self.viewModel.isEditing {
                self.navigationController?.popViewController(animated: true)
            } else {
                self.clearForm()
                self.tabBarController?.selectedIndex = 0
            }
        }

        viewModel.onSaveError = { [weak self] message in
            guard let self else { return }
            self.setSaveLoading(false)
            let alert = UIAlertController(title: "Sync Failed", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Keep Locally", style: .default) { [weak self] _ in
                guard let self else { return }
                if self.viewModel.isEditing {
                    self.navigationController?.popViewController(animated: true)
                } else {
                    self.clearForm()
                    self.tabBarController?.selectedIndex = 0
                }
            })
            alert.addAction(UIAlertAction(title: "Try Again", style: .cancel) { [weak self] _ in
                self?.viewModel.save()
            })
            self.present(alert, animated: true)
        }

        viewModel.onValidationError = { [weak self] message in
            guard let self else { return }
            if message.contains("Place") { self.shake(self.placeField) }
            let alert = UIAlertController(title: "Oops", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    // MARK: – Loading state

    private func setSaveLoading(_ loading: Bool) {
        if loading {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            let saveBtn = UIBarButtonItem(title: "Save", style: .done,
                                         target: self, action: #selector(saveTapped))
            saveBtn.tintColor = Theme.accent
            navigationItem.rightBarButtonItem = saveBtn
        }
        navigationItem.leftBarButtonItem?.isEnabled = !loading
        view.isUserInteractionEnabled = !loading
    }

    // MARK: – Save button validation

    private func updateSaveButtonState() {
        let placeOK  = !(placeField.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let ratingOK = starView.rating > 0
        navigationItem.rightBarButtonItem?.isEnabled = placeOK && ratingOK
    }

    // MARK: – Actions

    @objc private func saveTapped() {
        viewModel.placeName   = placeField.text ?? ""
        viewModel.category    = FoodCategory.allCases[categoryControl.selectedSegmentIndex]
        viewModel.rating      = starView.rating
        viewModel.comment     = commentView.text ?? ""
        viewModel.visibility  = Visibility.from(segmentIndex: visibilityControl.selectedSegmentIndex)
        viewModel.checkInDate = checkInPicker.date
        print("📝 saveTapped: placeName=\(viewModel.placeName), placeIsClaimed=\(viewModel.placeIsClaimed)")
        viewModel.save()
    }

    @objc private func cancelTapped() {
        if viewModel.isEditing {
            navigationController?.popViewController(animated: true)
        } else {
            clearForm()
        }
    }

    @objc private func pickPhoto() {
        guard viewModel.selectedImages.count < AddEntryViewModel.maxPhotos else {
            let alert = UIAlertController(title: "Photo Limit",
                                          message: "You can add up to \(AddEntryViewModel.maxPhotos) photos.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true
        let alert = UIAlertController(title: "Add Photo", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self] _ in
                picker.sourceType = .camera; self?.present(picker, animated: true)
            })
        }
        alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            picker.sourceType = .photoLibrary; self?.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = photoGallery
        present(alert, animated: true)
    }

    private func removePhoto(at index: Int) {
        viewModel.selectedImages.remove(at: index)
        viewModel.imagesModified = true
        photoGallery.reloadData()
    }

    // MARK: – Place picker

    private func presentPlacePicker() {
        let picker = PlacePickerViewController()
        picker.initialCoordinate = viewModel.location
        picker.onSelect = { [weak self] name, coordinate, isClaimed in
            guard let self else { print("❌ onSelect: self is nil"); return }
            print("✅ onSelect fired: name=\(name), isClaimed=\(isClaimed)")
            self.placeField.text = name
            self.viewModel.placeIsClaimed = isClaimed
            if let coordinate {
                self.placePin(at: coordinate)
            }
            self.updatePlaceFieldState()
            self.updateSaveButtonState()
        }
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(picker, animated: true)
    }

    // MARK: – Place field state

    /// Updates the place field's right-side icon and interactivity to reflect claimed status.
    private func updatePlaceFieldState() {
        let locked = viewModel.placeIsClaimed
        let iconName = locked ? "lock.fill" : "magnifyingglass"
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 0, y: 0, width: 30, height: 20)
        placeField.rightView = icon
        placeField.alpha = locked ? 0.6 : 1.0
    }

    // MARK: – Map preview

    private func placePin(at coord: CLLocationCoordinate2D) {
        viewModel.location = coord
        locationMapView.isHidden = false
        locationPin.coordinate = coord
        if locationMapView.annotations.isEmpty {
            locationMapView.addAnnotation(locationPin)
        }
        locationMapView.setRegion(
            MKCoordinateRegion(center: coord, latitudinalMeters: 91, longitudinalMeters: 91),
            animated: true
        )
    }

    // MARK: – Form helpers

    private func populateFormFromViewModel() {
        placeField.text = viewModel.placeName
        categoryControl.selectedSegmentIndex = FoodCategory.allCases.firstIndex(of: viewModel.category) ?? 0
        starView.rating = viewModel.rating
        ratingValueLabel.text = viewModel.rating > 0 ? String(format: "%.1f", viewModel.rating) : "–"
        commentView.text = viewModel.comment
        commentPlaceholder.isHidden = !viewModel.comment.isEmpty
        visibilityControl.selectedSegmentIndex = viewModel.visibility.segmentIndex
        checkInPicker.date = viewModel.checkInDate

        if let coord = viewModel.location {
            locationMapView.isHidden = false
            placePin(at: coord)
        } else if !viewModel.isEditing {
            if let coord = prefillCoordinate {
                placePin(at: coord)
            } else {
                locationManager.requestWhenInUseAuthorization()
                let status = locationManager.authorizationStatus
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    locationManager.requestLocation()
                }
            }
        }

        // Pre-load existing images when editing
        if viewModel.selectedImages.isEmpty {
            let local = viewModel.initialImages
            if !local.isEmpty {
                viewModel.selectedImages = local
                photoGallery.reloadData()
            } else {
                let urls = viewModel.initialImageURLs
                if !urls.isEmpty {
                    let group = DispatchGroup()
                    var downloaded = [Int: UIImage]()
                    for (i, url) in urls.enumerated() {
                        group.enter()
                        ImageLoader.shared.load(urlString: url) { image in
                            if let image { downloaded[i] = image }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) { [weak self] in
                        guard let self else { return }
                        self.viewModel.selectedImages = (0..<urls.count).compactMap { downloaded[$0] }
                        self.photoGallery.reloadData()
                    }
                } else {
                    photoGallery.reloadData()
                }
            }
        }

        updatePlaceFieldState()
        updateSaveButtonState()

        // If editing and place name is missing, shake the field so the user
        // knows exactly what's blocking the Save button.
        if viewModel.isEditing && (placeField.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.shake(self.placeField)
                self.placeField.layer.borderColor = UIColor.systemRed.cgColor
                self.placeField.layer.borderWidth = 1
                self.placeField.layer.cornerRadius = 6
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.placeField.layer.borderWidth = 0
                }
            }
        }
    }

    private func clearForm() {
        placeField.text = ""
        categoryControl.selectedSegmentIndex = 0
        starView.rating = 0
        ratingValueLabel.text = "–"
        commentView.text = ""
        commentPlaceholder.isHidden = false
        visibilityControl.selectedSegmentIndex = viewModel.visibility.segmentIndex
        checkInPicker.date = Date()
        viewModel.selectedImages = []
        viewModel.imagesModified = false
        viewModel.location = nil
        photoGallery.reloadData()
        locationMapView.removeAnnotations(locationMapView.annotations)
        locationMapView.isHidden = true
        locationManager.requestLocation()
        updateSaveButtonState()
    }

    // MARK: – Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func setupContent() {
        contentView.addSubview(photoGallery)

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        // Place — tapping opens PlacePickerViewController
        placeField.delegate = self
        mainStack.addArrangedSubview(makeCard(title: "Place", views: [
            makeRow(label: "Where", view: placeField)
        ]))

        // Category
        categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        mainStack.addArrangedSubview(makeCard(title: "Category", views: [categoryControl]))

        // Rating
        starView.delegate = self
        starView.translatesAutoresizingMaskIntoConstraints = false
        let ratingRow = UIStackView(arrangedSubviews: [starView, ratingValueLabel, UIView()])
        ratingRow.axis = .horizontal
        ratingRow.spacing = 10
        ratingRow.alignment = .center
        mainStack.addArrangedSubview(makeCard(title: "Rating", views: [ratingRow]))

        // Check In
        mainStack.addArrangedSubview(makeCard(title: "Check In", views: [
            makeRow(label: "Date & Time", view: checkInPicker)
        ]))

        // Comment
        commentView.delegate = self
        commentView.addSubview(commentPlaceholder)
        NSLayoutConstraint.activate([
            commentPlaceholder.topAnchor.constraint(equalTo: commentView.topAnchor, constant: 8),
            commentPlaceholder.leadingAnchor.constraint(equalTo: commentView.leadingAnchor, constant: 5)
        ])
        commentView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        mainStack.addArrangedSubview(makeCard(title: "Comment", views: [commentView]))

        // Visibility
        let visibilityNote = UILabel()
        visibilityNote.text = "Share: visible to friends only. Public: visible to everyone."
        visibilityNote.font = .systemFont(ofSize: 12)
        visibilityNote.textColor = .secondaryLabel
        visibilityNote.numberOfLines = 0
        mainStack.addArrangedSubview(makeCard(title: "Visibility", views: [
            visibilityControl,
            visibilityNote
        ]))

        // Location preview map (read-only — shown after a place is selected)
        locationMapView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        mainStack.addArrangedSubview(makeCard(title: "Location", views: [locationMapView]))

        NSLayoutConstraint.activate([
            photoGallery.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            photoGallery.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            photoGallery.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            photoGallery.heightAnchor.constraint(equalToConstant: 90),
            mainStack.topAnchor.constraint(equalTo: photoGallery.bottomAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }

    @objc private func categoryChanged()  { /* synced to VM on save */ }

    // MARK: – Helpers

    private func makeCard(title: String, views: [UIView]) -> UIView {
        let header = UILabel()
        header.text = title.uppercased()
        header.font = .systemFont(ofSize: 11, weight: .bold)
        header.textColor = Theme.accent

        let card = UIView()
        Theme.applyCardStyle(to: card)

        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = 10
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        for v in views { cardStack.addArrangedSubview(v) }
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        let outer = UIStackView(arrangedSubviews: [header, card])
        outer.axis = .vertical
        outer.spacing = 6
        return outer
    }

    private func makeRow(label text: String, view: UIView) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, view])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    private func shake(_ view: UIView) {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values = [-8, 8, -6, 6, -4, 4, 0]
        anim.duration = 0.4
        view.layer.add(anim, forKey: nil)
    }

    private func addKeyboardDismissGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = endFrame.height
            self.scrollView.verticalScrollIndicatorInsets.bottom = endFrame.height
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
}

// MARK: – UITextFieldDelegate (intercept place field tap)

extension AddEntryViewController: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === placeField {
            if viewModel.placeIsClaimed {
                showClaimedPlaceOptions()
            } else {
                presentPlacePicker()
            }
            return false
        }
        return true
    }

    private func showClaimedPlaceOptions() {
        let sheet = UIAlertController(
            title: "Linked Business",
            message: "This place is linked to a verified business listing. You can still edit your rating, comment, and other details.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Change Place", style: .default) { [weak self] _ in
            guard let self else { return }
            self.viewModel.placeIsClaimed = false
            self.updatePlaceFieldState()
            self.presentPlacePicker()
        })
        sheet.addAction(UIAlertAction(title: "Keep as Is", style: .cancel))
        sheet.popoverPresentationController?.sourceView = placeField
        present(sheet, animated: true)
    }
}

// MARK: – StarRatingViewDelegate

extension AddEntryViewController: StarRatingViewDelegate {
    func starRatingView(_ view: StarRatingView, didUpdateRating rating: Double) {
        ratingValueLabel.text = String(format: "%.1f", rating)
        updateSaveButtonState()
    }
}

// MARK: – UITextViewDelegate

extension AddEntryViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        commentPlaceholder.isHidden = !textView.text.isEmpty
    }
}

// MARK: – UIImagePickerControllerDelegate

extension AddEntryViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage else { return }
        viewModel.selectedImages.append(img)
        viewModel.imagesModified = true
        photoGallery.reloadData()
    }
}

// MARK: – CLLocationManagerDelegate

extension AddEntryViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, viewModel.location == nil else { return }
        placePin(at: loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard viewModel.location == nil, !viewModel.isEditing else { return }
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

// MARK: – UICollectionViewDataSource / Delegate (photo gallery)

extension AddEntryViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let photos = viewModel.selectedImages.count
        return photos < AddEntryViewModel.maxPhotos ? photos + 1 : photos
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let isAddCell = indexPath.item == viewModel.selectedImages.count
        if isAddCell {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: PhotoGalleryAddCell.reuseID, for: indexPath) as! PhotoGalleryAddCell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PhotoGalleryImageCell.reuseID, for: indexPath) as! PhotoGalleryImageCell
        cell.configure(with: viewModel.selectedImages[indexPath.item])
        cell.onRemove = { [weak self] in self?.removePhoto(at: indexPath.item) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == viewModel.selectedImages.count { pickPhoto() }
    }
}

// MARK: – Photo gallery cells

final class PhotoGalleryAddCell: UICollectionViewCell {

    static let reuseID = "PhotoGalleryAddCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Theme.accentLight
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        let img = UIImageView(image: UIImage(systemName: "plus",
                                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)))
        img.tintColor = Theme.accent
        img.contentMode = .center
        img.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(img)
        NSLayoutConstraint.activate([
            img.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            img.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class PhotoGalleryImageCell: UICollectionViewCell {

    static let reuseID = "PhotoGalleryImageCell"

    var onRemove: (() -> Void)?

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let removeButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        b.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        b.layer.cornerRadius = 11
        b.clipsToBounds = true
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(removeButton)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            removeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            removeButton.widthAnchor.constraint(equalToConstant: 22),
            removeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with image: UIImage) { imageView.image = image }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        onRemove = nil
    }

    @objc private func removeTapped() { onRemove?() }
}
