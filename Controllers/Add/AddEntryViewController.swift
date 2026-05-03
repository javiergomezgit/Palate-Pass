// MARK: – MVVM | View
// Form for creating or editing a FoodEntry. Writes user input to AddEntryViewModel
// and listens for save/validation outcomes via closures. No DataManager access here.

import UIKit
import CoreLocation
import MapKit

final class AddEntryViewController: UIViewController {

    // MARK: – MVVM wiring

    private let viewModel: AddEntryViewModel

    init(viewModel: AddEntryViewModel = AddEntryViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Location

    private let locationManager = CLLocationManager()

    // MARK: – UI

    private let scrollView  = UIScrollView()
    private let contentView = UIView()

    private let photoButton: UIButton = {
        let btn = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "camera.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium))
        config.baseBackgroundColor = Theme.accentLight
        config.baseForegroundColor = Theme.accent
        config.cornerStyle = .large
        config.title = "Add Photo"
        config.imagePlacement = .top
        config.imagePadding = 8
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 13, weight: .medium); return a
        }
        btn.configuration = config
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let photoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameField  = AddEntryViewController.makeField(placeholder: "e.g. Cappuccino")
    private let placeField = AddEntryViewController.makeField(placeholder: "e.g. Blue Bottle Coffee")

    private let categoryControl: UISegmentedControl = {
        let items = FoodCategory.allCases.map { $0.emoji }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        // 20% bigger emoji font
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

    private let privacySwitch  = UISwitch()
    private let locationSwitch = UISwitch()

    private let locationStatusLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.text = "Requesting location…"
        return l
    }()

    private lazy var locationMapView: MKMapView = {
        let mv = MKMapView()
        mv.layer.cornerRadius = 12
        mv.clipsToBounds = true
        mv.isHidden = true
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    private let locationPin = MKPointAnnotation()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.isEditing ? "Edit Entry" : "New Entry"
        view.backgroundColor = .systemGroupedBackground

        // Large title
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        // Save button — starts disabled until required fields are filled
        let saveBtn = UIBarButtonItem(title: "Save", style: .done,
                                     target: self, action: #selector(saveTapped))
        saveBtn.tintColor = Theme.accent
        saveBtn.isEnabled = false
        navigationItem.rightBarButtonItem = saveBtn

        // Cancel button
        let cancelBtn = UIBarButtonItem(title: "Cancel", style: .plain,
                                       target: self, action: #selector(cancelTapped))
        cancelBtn.tintColor = .secondaryLabel
        navigationItem.leftBarButtonItem = cancelBtn

        setupScrollView()
        setupContent()
        addKeyboardDismissGesture()
        configureLocationManager()
        bindViewModel()
        populateFormFromViewModel()
    }

    // MARK: – ViewModel bindings

    private func bindViewModel() {
        viewModel.onSaveSuccess = { [weak self] in
            guard let self else { return }
            if self.viewModel.isEditing {
                self.navigationController?.popViewController(animated: true)
            } else {
                self.clearForm()
                self.tabBarController?.selectedIndex = 0
            }
        }
        viewModel.onValidationError = { [weak self] message in
            guard let self else { return }
            if message.contains("name") { self.shake(self.nameField) }
            let alert = UIAlertController(title: "Oops", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    // MARK: – Save button validation

    private func updateSaveButtonState() {
        let nameOK   = !(nameField.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let placeOK  = !(placeField.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let ratingOK = starView.rating > 0
        // category always has a selection; comment is optional
        navigationItem.rightBarButtonItem?.isEnabled = nameOK && placeOK && ratingOK
    }

    // MARK: – Actions

    @objc private func saveTapped() {
        viewModel.name      = nameField.text ?? ""
        viewModel.placeName = placeField.text ?? ""
        viewModel.category  = FoodCategory.allCases[categoryControl.selectedSegmentIndex]
        viewModel.rating    = starView.rating
        viewModel.comment   = commentView.text ?? ""
        viewModel.isPublic  = privacySwitch.isOn
        viewModel.save()
    }

    @objc private func cancelTapped() {
        if viewModel.isEditing {
            navigationController?.popViewController(animated: true)
        } else {
            // Clear so the form is fresh if user comes back
            clearForm()
        }
    }

    @objc private func pickPhoto() {
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
        if viewModel.selectedImage != nil {
            alert.addAction(UIAlertAction(title: "Remove Photo", style: .destructive) { [weak self] _ in
                self?.viewModel.selectedImage = nil
                self?.photoImageView.isHidden = true
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = photoButton
        present(alert, animated: true)
    }

    @objc private func locationToggled() {
        if locationSwitch.isOn {
            locationManager.requestWhenInUseAuthorization()
            locationManager.requestLocation()
            locationStatusLabel.text = "Requesting location…"
            locationMapView.isHidden = false
        } else {
            viewModel.location = nil
            locationStatusLabel.text = "Location not attached"
            locationMapView.isHidden = true
            locationMapView.removeAnnotations(locationMapView.annotations)
        }
    }

    @objc private func mapLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: locationMapView)
        let coord = locationMapView.convert(point, toCoordinateFrom: locationMapView)
        placePin(at: coord)
    }

    // MARK: – Form helpers

    private func populateFormFromViewModel() {
        nameField.text  = viewModel.name
        placeField.text = viewModel.placeName
        categoryControl.selectedSegmentIndex = FoodCategory.allCases.firstIndex(of: viewModel.category) ?? 0
        starView.rating = viewModel.rating
        ratingValueLabel.text = viewModel.rating > 0 ? String(format: "%.1f", viewModel.rating) : "–"
        commentView.text = viewModel.comment
        commentPlaceholder.isHidden = !viewModel.comment.isEmpty
        privacySwitch.isOn = viewModel.isPublic

        if let coord = viewModel.location {
            locationSwitch.isOn = true
            locationMapView.isHidden = false
            placePin(at: coord)
        } else if !viewModel.isEditing {
            // Default location ON for new entries — map visible, pin drops when location arrives
            locationSwitch.isOn = true
            locationMapView.isHidden = false
            locationManager.requestWhenInUseAuthorization()
        }

        if let img = viewModel.initialImage {
            photoImageView.image = img
            photoImageView.isHidden = false
        }

        updateSaveButtonState()
    }

    private func placePin(at coord: CLLocationCoordinate2D) {
        viewModel.location = coord
        locationPin.coordinate = coord
        if locationMapView.annotations.isEmpty {
            locationMapView.addAnnotation(locationPin)
        }
        locationMapView.setRegion(
            MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500),
            animated: true
        )
        locationStatusLabel.text = String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
    }

    private func clearForm() {
        nameField.text  = ""
        placeField.text = ""
        categoryControl.selectedSegmentIndex = 0
        starView.rating = 0
        ratingValueLabel.text = "–"
        commentView.text = ""
        commentPlaceholder.isHidden = false
        privacySwitch.isOn = viewModel.isPublic  // respect default
        locationSwitch.isOn = true
        photoImageView.isHidden = true
        viewModel.selectedImage = nil
        viewModel.location = nil
        locationMapView.removeAnnotations(locationMapView.annotations)
        locationMapView.isHidden = false
        locationStatusLabel.text = "Requesting location…"
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
        contentView.addSubview(photoButton)
        contentView.addSubview(photoImageView)
        photoButton.addTarget(self, action: #selector(pickPhoto), for: .touchUpInside)

        let mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        // Item Info — name/place with text change listeners
        nameField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        placeField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        mainStack.addArrangedSubview(makeCard(title: "Item Info", views: [
            makeRow(label: "Name",  view: nameField),
            makeDivider(),
            makeRow(label: "Place", view: placeField)
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

        // Comment
        commentView.delegate = self
        commentView.addSubview(commentPlaceholder)
        NSLayoutConstraint.activate([
            commentPlaceholder.topAnchor.constraint(equalTo: commentView.topAnchor, constant: 8),
            commentPlaceholder.leadingAnchor.constraint(equalTo: commentView.leadingAnchor, constant: 5)
        ])
        commentView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        mainStack.addArrangedSubview(makeCard(title: "Comment", views: [commentView]))

        // Privacy — default from Settings
        privacySwitch.isOn = viewModel.isPublic
        privacySwitch.onTintColor = Theme.accent
        let privacyNote = UILabel()
        privacyNote.text = "When off, only you can see this entry."
        privacyNote.font = .systemFont(ofSize: 12)
        privacyNote.textColor = .secondaryLabel
        privacyNote.numberOfLines = 0
        mainStack.addArrangedSubview(makeCard(title: "Privacy", views: [
            makeRow(label: "Public rating & comment", view: privacySwitch),
            privacyNote
        ]))

        // Location — ON by default; map + draggable pin let the user refine the spot
        locationSwitch.isOn = true
        locationSwitch.onTintColor = Theme.accent
        locationSwitch.addTarget(self, action: #selector(locationToggled), for: .valueChanged)
        locationMapView.delegate = self
        locationMapView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        locationMapView.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(mapLongPressed(_:)))
        )
        mainStack.addArrangedSubview(makeCard(title: "Location", views: [
            makeRow(label: "Attach current location", view: locationSwitch),
            locationStatusLabel,
            locationMapView
        ]))

        NSLayoutConstraint.activate([
            photoButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            photoButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            photoButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            photoButton.heightAnchor.constraint(equalToConstant: 112),
            photoImageView.topAnchor.constraint(equalTo: photoButton.topAnchor),
            photoImageView.leadingAnchor.constraint(equalTo: photoButton.leadingAnchor),
            photoImageView.trailingAnchor.constraint(equalTo: photoButton.trailingAnchor),
            photoImageView.bottomAnchor.constraint(equalTo: photoButton.bottomAnchor),
            mainStack.topAnchor.constraint(equalTo: photoButton.bottomAnchor, constant: 12),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }

    @objc private func textFieldChanged() { updateSaveButtonState() }
    @objc private func categoryChanged()  { /* synced to VM on save */ }

    // MARK: – Helpers

    /// Creates a left-aligned text field. Label hugs tight; field expands to fill the row.
    private static func makeField(placeholder: String) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.font = .systemFont(ofSize: 15)
        f.textAlignment = .left
        f.clearButtonMode = .whileEditing
        // Allow the field to expand
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
        // Label hugs its content; view (text field / switch) gets all remaining space
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
        let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
        viewModel.selectedImage = img
        photoImageView.image = img
        photoImageView.isHidden = img == nil
        picker.dismiss(animated: true)
    }
}

// MARK: – MKMapViewDelegate

extension AddEntryViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
        view.isDraggable = true
        view.canShowCallout = false
        view.markerTintColor = Theme.accent
        return view
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                 didChange newState: MKAnnotationView.DragState,
                 fromOldState oldState: MKAnnotationView.DragState) {
        guard newState == .ending, let coord = view.annotation?.coordinate else { return }
        viewModel.location = coord
        locationStatusLabel.text = String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
    }
}

// MARK: – CLLocationManagerDelegate

extension AddEntryViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        placePin(at: loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatusLabel.text = "Location unavailable"
        locationSwitch.isOn = false
        viewModel.location = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            if locationSwitch.isOn { manager.requestLocation() }
        }
    }
}
