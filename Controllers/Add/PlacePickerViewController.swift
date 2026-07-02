// MARK: – MVVM | View
// Modal sheet for selecting a place by name + location.
// Shows nearby POIs immediately, live-filters as the user types,
// and resolves with a name + optional coordinate.

import UIKit
import MapKit
import CoreLocation

final class PlacePickerViewController: UIViewController {

    // MARK: – Public

    /// Called when the user confirms a selection.
    /// - isClaimed: true when selected from the search list or a map pin (real business); false for custom-typed names.
    var onSelect: ((String, CLLocationCoordinate2D?, Bool) -> Void)?
    /// Seed coordinate (caller's current viewModel.location or device location).
    var initialCoordinate: CLLocationCoordinate2D?

    // MARK: – Private state

    private var coordinate: CLLocationCoordinate2D? {
        didSet {
            guard let coord = coordinate else { return }
            // 900m ≈ 10% tighter than 1000m default
            mapView.setRegion(
                MKCoordinateRegion(center: coord, latitudinalMeters: 900, longitudinalMeters: 900),
                animated: true
            )
            userPin.coordinate = coord
            if !mapView.annotations.contains(where: { $0 === userPin }) {
                mapView.addAnnotation(userPin)
            }
            refreshSuggestions(query: searchField.text ?? "")
        }
    }
    private var searchResults: [MKMapItem] = []
    private var currentSearch: MKLocalSearch?
    private var debounceTimer: Timer?
    private let locationManager = CLLocationManager()
    private let userPin = MKPointAnnotation()

    // MARK: – UI

    private let searchField: UITextField = {
        let f = UITextField()
        f.placeholder = "Search or type a place name"
        f.font = .systemFont(ofSize: 15)
        f.backgroundColor = .secondarySystemBackground
        f.layer.cornerRadius = 10
        f.clearButtonMode = .whileEditing
        f.returnKeyType = .search
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 0, y: 0, width: 36, height: 20)
        f.leftView = icon
        f.leftViewMode = .always
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView()
        tv.dataSource = self
        tv.delegate   = self
        tv.rowHeight  = 52
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var mapView: MKMapView = {
        let mv = MKMapView()
        mv.showsUserLocation = true
        mv.delegate = self
        mv.selectableMapFeatures = .pointsOfInterest
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    private lazy var locateMeButton: MKUserTrackingButton = {
        let b = MKUserTrackingButton(mapView: mapView)
        b.layer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9).cgColor
        b.layer.cornerRadius = 6
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private var tableHeightConstraint: NSLayoutConstraint!
    private var mapBottomConstraint: NSLayoutConstraint!
    private var searchHeightConstraint: NSLayoutConstraint!
    private var searchTopConstraint: NSLayoutConstraint!
    private var searchIsVisible = false
    private weak var searchToggleButton: UIButton?

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)

        locationManager.delegate = self
        coordinate = initialCoordinate

        if coordinate == nil {
            locationManager.requestWhenInUseAuthorization()
            let status = locationManager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.requestLocation()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Search field starts collapsed — user opens it with the magnifier button
    }

    // MARK: – Layout

    private func setupUI() {
        // Header
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Select a Place"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let searchBtn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        searchBtn.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: cfg), for: .normal)
        searchBtn.tintColor = Theme.accent
        searchBtn.addTarget(self, action: #selector(toggleSearch), for: .touchUpInside)
        searchBtn.translatesAutoresizingMaskIntoConstraints = false
        searchToggleButton = searchBtn

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(cancelBtn)
        header.addSubview(titleLabel)
        header.addSubview(searchBtn)

        // Search field starts collapsed (height=0, no top spacing)
        searchField.isHidden = true
        searchField.clipsToBounds = true

        view.addSubview(header)
        view.addSubview(searchField)
        view.addSubview(tableView)
        view.addSubview(mapView)
        mapView.addSubview(locateMeButton)

        tableHeightConstraint  = tableView.heightAnchor.constraint(equalToConstant: 0)
        mapBottomConstraint    = mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        // Collapsed by default: top=0, height=0 so tableView sits flush under header
        searchTopConstraint    = searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 0)
        searchHeightConstraint = searchField.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            cancelBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            cancelBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            searchBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchBtn.widthAnchor.constraint(equalToConstant: 36),
            searchBtn.heightAnchor.constraint(equalToConstant: 36),

            searchTopConstraint,
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchHeightConstraint,

            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableHeightConstraint,

            mapView.topAnchor.constraint(equalTo: tableView.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapBottomConstraint,

            locateMeButton.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 8),
            locateMeButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -8)
        ])

        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    }

    // MARK: – Search toggle

    @objc private func toggleSearch() {
        searchIsVisible ? collapseSearch() : expandSearch()
    }

    private func expandSearch() {
        searchIsVisible = true
        searchField.isHidden = false
        searchTopConstraint.constant    = 8
        searchHeightConstraint.constant = 44
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        searchToggleButton?.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() } completion: { _ in
            self.searchField.becomeFirstResponder()
        }
    }

    private func collapseSearch() {
        searchIsVisible = false
        searchField.resignFirstResponder()
        searchField.text = ""
        searchTopConstraint.constant    = 0
        searchHeightConstraint.constant = 0
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        searchToggleButton?.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: cfg), for: .normal)
        UIView.animate(withDuration: 0.2, animations: {
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.searchField.isHidden = true
            // Restore the single nearest result
            self.refreshSuggestions(query: "")
        })
    }

    // MARK: – Search

    @objc private func searchChanged() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.refreshSuggestions(query: self?.searchField.text ?? "")
        }
        updateTableHeight()
    }

    private func refreshSuggestions(query: String) {
        currentSearch?.cancel()
        guard let coord = coordinate else {
            searchResults = []
            reloadTable()
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let search: MKLocalSearch

        if trimmed.isEmpty {
            let req = MKLocalPointsOfInterestRequest(center: coord, radius: 1000)
            req.pointOfInterestFilter = MKPointOfInterestFilter(including: [
                .restaurant, .cafe, .bakery, .foodMarket, .brewery, .winery, .nightlife
            ])
            search = MKLocalSearch(request: req)
        } else {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = trimmed
            req.resultTypes = .pointOfInterest
            // No region set — search the full Apple Maps database globally.
            // Results are sorted by distance afterward so closest appear first.
            search = MKLocalSearch(request: req)
        }

        let isEmptyQuery = trimmed.isEmpty
        currentSearch = search
        search.start { [weak self] response, error in
            guard let self else { return }
            guard let items = response?.mapItems, error == nil else {
                self.searchResults = []
                self.reloadTable()
                return
            }
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let sorted = items.sorted {
                let a = CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
                let b = CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
                return a.distance(from: origin) < b.distance(from: origin)
            }
            // No query → show only the single closest place; typing → show up to 10 globally sorted by distance
            self.searchResults = isEmptyQuery ? Array(sorted.prefix(1)) : Array(sorted.prefix(10))
            self.reloadTable()
            self.refreshMapPins()
        }
    }

    private func reloadTable() {
        tableView.reloadData()
        updateTableHeight()
    }

    private func updateTableHeight() {
        let rows = CGFloat((hasCustomRow ? 1 : 0) + searchResults.count)
        let newHeight = rows * tableView.rowHeight
        guard tableHeightConstraint.constant != newHeight else { return }
        tableHeightConstraint.constant = newHeight
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    private var hasCustomRow: Bool {
        !(searchField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func refreshMapPins() {
        let existing = mapView.annotations.filter { !($0 is MKUserLocation) && $0 !== userPin }
        mapView.removeAnnotations(existing)
        for item in searchResults {
            let ann = MKPointAnnotation()
            ann.coordinate = item.placemark.coordinate
            ann.title = item.name
            mapView.addAnnotation(ann)
        }
    }

    // MARK: – Selection

    private func selectPlace(name: String, coordinate: CLLocationCoordinate2D?, isClaimed: Bool) {
        searchField.resignFirstResponder()
        searchIsVisible = false
        // Capture onSelect directly — UIKit releases the presented VC before the completion
        // fires, so a [weak self] reference would already be nil at that point.
        print("🗺 selectPlace: name=\(name), isClaimed=\(isClaimed), hasCallback=\(onSelect != nil)")
        let callback = onSelect
        dismiss(animated: true) {
            print("🗺 dismiss complete, firing callback")
            callback?(name, coordinate, isClaimed)
        }
    }

    // MARK: – Keyboard

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        // Convert keyboard frame from screen to our view's coordinate space
        let keyboardInView = view.convert(frame, from: nil)
        let overlap = view.bounds.maxY - keyboardInView.minY
        mapBottomConstraint.constant = -max(0, overlap)
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        mapBottomConstraint.constant = 0
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func cancelTapped() {
        searchField.resignFirstResponder()
        dismiss(animated: true)
    }
}

// MARK: – UITableViewDataSource / Delegate

extension PlacePickerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        (hasCustomRow ? 1 : 0) + searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()

        if hasCustomRow && indexPath.row == 0 {
            let text = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
            config.text = "Use \"\(text)\""
            config.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
            config.textProperties.color = Theme.accent
            cell.contentConfiguration = config
            return cell
        }

        let offset = hasCustomRow ? 1 : 0
        let item   = searchResults[indexPath.row - offset]
        config.text = item.name
        config.textProperties.font = .systemFont(ofSize: 15)

        if let coord = coordinate {
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist   = CLLocation(latitude: item.placemark.coordinate.latitude,
                                    longitude: item.placemark.coordinate.longitude)
                .distance(from: origin)
            let fmt = MKDistanceFormatter()
            fmt.unitStyle = .abbreviated
            config.secondaryText = fmt.string(fromDistance: dist)
            config.secondaryTextProperties.font  = .systemFont(ofSize: 12)
            config.secondaryTextProperties.color = .secondaryLabel
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if hasCustomRow && indexPath.row == 0 {
            let name = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
            selectPlace(name: name, coordinate: coordinate, isClaimed: false)
            return
        }

        let offset = hasCustomRow ? 1 : 0
        let item   = searchResults[indexPath.row - offset]
        selectPlace(name: item.name ?? "", coordinate: item.placemark.coordinate, isClaimed: true)
    }
}

// MARK: – UITextFieldDelegate

extension PlacePickerViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        selectPlace(name: text, coordinate: coordinate, isClaimed: false)
        return true
    }
}

// MARK: – MKMapViewDelegate

extension PlacePickerViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }

        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
            for: annotation
        ) as? MKMarkerAnnotationView

        if annotation === userPin {
            // Location indicator — not selectable as a place
            view?.markerTintColor = Theme.accent
            view?.glyphImage = UIImage(systemName: "location.fill")
            view?.canShowCallout = false
            view?.isDraggable = false
        } else {
            view?.canShowCallout = false
        }
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        mapView.deselectAnnotation(annotation, animated: true)
        // Skip user location dot and our own location indicator pin
        guard !(annotation is MKUserLocation), annotation !== userPin else { return }

        if let feature = annotation as? MKMapFeatureAnnotation {
            selectPlace(name: feature.title ?? "", coordinate: feature.coordinate, isClaimed: true)
        } else if let name = annotation.title ?? nil {
            selectPlace(name: name, coordinate: annotation.coordinate, isClaimed: true)
        }
    }
}

// MARK: – CLLocationManagerDelegate

extension PlacePickerViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, coordinate == nil else { return }
        coordinate = loc.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard coordinate == nil else { return }
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}
