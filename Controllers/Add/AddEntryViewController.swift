// MARK: – MVVM | View
// Form for creating or editing a FoodEntry.
// Fields: photo, place, category, rating, check-in date, comment, visibility, location.

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

    private let placeField = AddEntryViewController.makeField(placeholder: "e.g. Blue Bottle Coffee")

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

    // Visibility: 0 = Private, 1 = Share (friends), 2 = Public
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

    private let locationSearchField = AddEntryViewController.makeField(placeholder: "Search nearby business (optional)")

    private lazy var locationResultsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 4
        sv.isHidden = true
        return sv
    }()

    private lazy var locationMapView: MKMapView = {
        let mv = MKMapView()
        mv.layer.cornerRadius = 12
        mv.clipsToBounds = true
        mv.isHidden = true
        mv.showsUserLocation = true
        mv.selectableMapFeatures = .pointsOfInterest
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    private lazy var locateMeButton: MKUserTrackingButton = {
        let btn = MKUserTrackingButton(mapView: locationMapView)
        btn.layer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9).cgColor
        btn.layer.cornerRadius = 6
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let locationPin = MKPointAnnotation()

    private var searchDebounceTimer: Timer?
    private var currentLocalSearch: MKLocalSearch?
    private var searchResults: [MKMapItem] = []

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
        // Stack view doesn't reliably unhide arranged subviews set during viewDidLoad.
        // Re-apply visibility and region once the view is fully on screen.
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
            // Entry is already saved locally — ask user what to do
            let alert = UIAlertController(title: "Sync Failed", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Keep Locally", style: .default) { [weak self] _ in
                // Navigate away — data is not lost
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
        navigationItem.leftBarButtonItem?.isEnabled  = !loading
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
        viewModel.visibility  = EntryVisibility.from(segmentIndex: visibilityControl.selectedSegmentIndex)
        viewModel.checkInDate = checkInPicker.date
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
        photoGallery.reloadData()
    }

    @objc private func locationSearchFieldChanged() {
        searchDebounceTimer?.invalidate()
        let query = locationSearchField.text ?? ""
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.refreshLocationSuggestions(query: query)
        }
    }

    @objc private func locationSearchFieldDidBeginEditing() {
        // Show the 5 closest places immediately, before the user types anything.
        if searchResults.isEmpty {
            refreshLocationSuggestions(query: locationSearchField.text ?? "")
        }
        scrollLocationCardIntoView()
    }

    /// Empty query → nearby points of interest ranked by distance. Non-empty → named search, still ranked by distance.
    private func refreshLocationSuggestions(query: String) {
        currentLocalSearch?.cancel()
        guard let coord = viewModel.location else {
            searchResults = []
            rebuildResultsStack()
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let search: MKLocalSearch
        if trimmed.isEmpty {
            let request = MKLocalPointsOfInterestRequest(center: coord, radius: 1000)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
                .restaurant, .cafe, .bakery, .foodMarket, .brewery, .winery, .nightlife
            ])
            search = MKLocalSearch(request: request)
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: coord, latitudinalMeters: 5000, longitudinalMeters: 5000)
            search = MKLocalSearch(request: request)
        }

        currentLocalSearch = search
        search.start { [weak self] response, error in
            guard let self else { return }
            guard let items = response?.mapItems, error == nil else {
                self.searchResults = []
                self.rebuildResultsStack()
                return
            }
            self.searchResults = self.sortedByDistance(items, from: coord)
            self.rebuildResultsStack()
        }
    }

    private func sortedByDistance(_ items: [MKMapItem], from coord: CLLocationCoordinate2D) -> [MKMapItem] {
        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return items.sorted {
            let d0 = CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude).distance(from: origin)
            let d1 = CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude).distance(from: origin)
            return d0 < d1
        }
    }

    private func rebuildResultsStack() {
        locationResultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !searchResults.isEmpty else {
            locationResultsStack.isHidden = true
            return
        }
        let origin = viewModel.location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        for (index, item) in searchResults.prefix(5).enumerated() {
            let btn = UIButton(type: .system)
            btn.contentHorizontalAlignment = .left
            btn.titleLabel?.font = .systemFont(ofSize: 14)
            btn.titleLabel?.lineBreakMode = .byTruncatingTail
            btn.tag = index
            var title = item.name ?? "Unknown"
            if let origin {
                let itemLocation = CLLocation(latitude: item.placemark.coordinate.latitude,
                                              longitude: item.placemark.coordinate.longitude)
                let formatter = MKDistanceFormatter()
                formatter.unitStyle = .abbreviated
                title += "  ·  \(formatter.string(fromDistance: itemLocation.distance(from: origin)))"
            }
            btn.setTitle(title, for: .normal)
            btn.addTarget(self, action: #selector(searchResultTapped(_:)), for: .touchUpInside)
            locationResultsStack.addArrangedSubview(btn)
        }
        locationResultsStack.isHidden = false
    }

    @objc private func searchResultTapped(_ sender: UIButton) {
        guard searchResults.indices.contains(sender.tag) else { return }
        let item = searchResults[sender.tag]
        placePin(at: item.placemark.coordinate)
        locationSearchField.text = item.name
        locationResultsStack.isHidden = true
        view.endEditing(true)
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
        } else if viewModel.isEditing {
            // Entry was saved without a location — reflect that honestly
            locationMapView.isHidden = true
        } else {
            // New entry: attach the current location implicitly, no user action needed
            if let coord = prefillCoordinate {
                // EXIF GPS from Share Extension — use it directly, skip live request
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
                // Cloud-fetched entry: download remote images
                let urls = viewModel.initialImageURLs
                guard !urls.isEmpty else { photoGallery.reloadData(); return }
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
            }
        }

        updateSaveButtonState()
    }

    private func placePin(at coord: CLLocationCoordinate2D) {
        viewModel.location = coord
        locationMapView.isHidden = false
        locationPin.coordinate = coord
        if locationMapView.annotations.isEmpty {
            locationMapView.addAnnotation(locationPin)
        }
        // 300 feet ≈ 91 metres
        locationMapView.setRegion(
            MKCoordinateRegion(center: coord, latitudinalMeters: 91, longitudinalMeters: 91),
            animated: true
        )
        // Surface the 5 closest places immediately, before the user has typed anything.
        if (locationSearchField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            refreshLocationSuggestions(query: "")
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
        locationSearchField.text = ""
        searchResults = []
        rebuildResultsStack()
        viewModel.selectedImages = []
        viewModel.location = nil
        photoGallery.reloadData()
        locationMapView.removeAnnotations(locationMapView.annotations)
        locationMapView.isHidden = false
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

        // Place
        placeField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
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

        // Location
        let locationNote = UILabel()
        locationNote.text = "Your current location is attached automatically. Search to pin a specific business instead."
        locationNote.font = .systemFont(ofSize: 12)
        locationNote.textColor = .secondaryLabel
        locationNote.numberOfLines = 0

        locationSearchField.backgroundColor = Theme.accentLight
        locationSearchField.layer.cornerRadius = 10
        locationSearchField.layer.borderWidth = 1
        locationSearchField.layer.borderColor = Theme.accentMid.cgColor
        locationSearchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        locationSearchField.leftViewMode = .always
        locationSearchField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        locationSearchField.addTarget(self, action: #selector(locationSearchFieldChanged), for: .editingChanged)
        locationSearchField.addTarget(self, action: #selector(locationSearchFieldDidBeginEditing), for: .editingDidBegin)
        locationMapView.delegate = self
        locationMapView.heightAnchor.constraint(equalToConstant: 234).isActive = true // 180 + 30%
        locationMapView.addSubview(locateMeButton)
        NSLayoutConstraint.activate([
            locateMeButton.topAnchor.constraint(equalTo: locationMapView.topAnchor, constant: 8),
            locateMeButton.trailingAnchor.constraint(equalTo: locationMapView.trailingAnchor, constant: -8)
        ])
        mainStack.addArrangedSubview(makeCard(title: "Location", views: [
            locationNote,
            locationSearchField,
            locationResultsStack,
            locationMapView
        ]))

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

    @objc private func textFieldChanged() { updateSaveButtonState() }
    @objc private func categoryChanged()  { /* synced to VM on save */ }

    // MARK: – Helpers

    private static func makeField(placeholder: String) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.font = .systemFont(ofSize: 15)
        f.textAlignment = .left
        f.clearButtonMode = .whileEditing
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

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

    private func makeDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
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
        let keyboardHeight = endFrame.height
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = keyboardHeight
            self.scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight
        }
        if locationSearchField.isFirstResponder {
            scrollLocationCardIntoView()
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

    /// Brings the search field, suggestion list, and map preview into view above the keyboard.
    private func scrollLocationCardIntoView() {
        let topPoint = locationSearchField.convert(CGPoint.zero, to: scrollView)
        let bottomPoint = locationMapView.convert(CGPoint(x: 0, y: locationMapView.bounds.height), to: scrollView)
        let rect = CGRect(x: 0, y: topPoint.y - 8,
                          width: scrollView.bounds.width,
                          height: max(bottomPoint.y - topPoint.y + 16, 1))
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
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
        photoGallery.reloadData()
    }
}

// MARK: – MKMapViewDelegate

extension AddEntryViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Let the system render built-in points of interest with their own style.
        guard annotation === locationPin else { return nil }
        let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
        view.isDraggable = false
        view.canShowCallout = false
        view.markerTintColor = Theme.accent
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        guard let feature = annotation as? MKMapFeatureAnnotation else { return }
        placePin(at: feature.coordinate)
        locationSearchField.text = feature.title
        locationResultsStack.isHidden = true
        mapView.deselectAnnotation(annotation, animated: true)
    }
}

// MARK: – CLLocationManagerDelegate

extension AddEntryViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        placePin(at: loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location stays unattached; user can still search for a nearby business manually.
    }

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
        return photos < AddEntryViewModel.maxPhotos ? photos + 1 : photos  // +1 for the Add cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let isAddCell = indexPath.item == viewModel.selectedImages.count
        if isAddCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PhotoGalleryAddCell.reuseID, for: indexPath) as! PhotoGalleryAddCell
            return cell
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

    func configure(with image: UIImage) {
        imageView.image = image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        onRemove = nil
    }

    @objc private func removeTapped() { onRemove?() }
}
