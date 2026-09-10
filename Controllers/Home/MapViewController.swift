// MARK: – MVVM | View
// Renders entries as map pins. Binds to HomeViewModel — never reads DataManager or owns filter state.

import UIKit
import MapKit
import CoreLocation

// MARK: – Map annotation (View-layer helper, not a Model)

final class EntryAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let placeCheckin: PlaceCheckin

    /// Personal rating, rendered under the category line in the callout.
    var rating: Double { placeCheckin.checkin.personalRating }

    init(placeCheckin pc: PlaceCheckin) {
        self.placeCheckin = pc
        self.coordinate = pc.place.coordinate ?? CLLocationCoordinate2D()
        let cat = pc.place.foodCategory
        // MapKit only reports taps from controls inside the callout's accessory views —
        // its title text is not a hit target. The name therefore lives in the detail
        // accessory as a button (see MapViewController.calloutContent) and the category
        // takes the title slot, which also has to stay non-nil for the callout to show.
        self.title    = "\(cat.emoji) \(pc.place.category)"
        self.subtitle = nil
        super.init()
    }
}

// MARK: – MapViewController

final class MapViewController: UIViewController {

    // MARK: – MVVM wiring

    private let viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – UI

    private lazy var mapView: MKMapView = {
        let mv = MKMapView()
        mv.showsUserLocation = true
        mv.delegate = self
        // The built-in compass only appears while the map is rotated; MKCompassButton
        // below is placed with the other controls and stays visible.
        mv.showsCompass = false
        mv.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    /// Hand-rolled rather than MKUserTrackingButton: that control paints its own
    /// background when tracking becomes active and resets it on every mode change,
    /// which covered the white capsule. Here the capsule stays white at all times and
    /// only the glyph changes — outline when idle, filled while pressed or tracking.
    private lazy var trackingButton: UIButton = {
        let b = UIButton(type: .system)
        b.tintColor = Theme.accent
        b.setImage(Self.locationGlyph(filled: false), for: .normal)
        b.setImage(Self.locationGlyph(filled: true),  for: .highlighted)
        b.accessibilityLabel = "Show current location"
        b.addAction(UIAction { [weak self] _ in self?.toggleUserTracking() }, for: .touchUpInside)
        return b
    }()

    private static func locationGlyph(filled: Bool) -> UIImage? {
        UIImage(systemName: filled ? "location.fill" : "location",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
    }

    /// Standard map controls, stacked in the top-trailing corner.
    private lazy var controlsStack: UIStackView = {
        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .visible

        let stack = UIStackView(arrangedSubviews: [capsule(around: trackingButton), compass])
        stack.axis      = .vertical
        stack.spacing   = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: – Location

    private let locationManager = CLLocationManager()

    /// True once the map has been positioned — on the user, or on the entries when
    /// location is unavailable. Keeps later entry updates from yanking the region
    /// out from under someone who has panned somewhere.
    private var hasPositionedMap = false

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(mapView)
        view.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Safe area keeps the controls clear of the navigation and search bars.
            controlsStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])

        locationManager.delegate = self

        viewModel.addEntriesUpdatedHandler { [weak self] in self?.refreshPins() }
        refreshPins()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Opening the map should show where you are, not the first entry in the list.
        positionOnUserLocation()
    }

    // MARK: – Private

    /// Centres on the blue dot. Follow mode also keeps the tracking button's state in
    /// sync, and MapKit drops it back to `.none` by itself as soon as the user pans.
    private func positionOnUserLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // locationManagerDidChangeAuthorization retries once the user answers.
            locationManager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            hasPositionedMap = true
            mapView.setUserTrackingMode(.follow, animated: true)

        case .denied, .restricted:
            fitEntriesIfNeeded()

        @unknown default:
            fitEntriesIfNeeded()
        }
    }

    /// Tapping the arrow: centre and follow when idle, release tracking when already
    /// following. Routed through positionOnUserLocation so a tap also drives the
    /// permission prompt on a first run.
    private func toggleUserTracking() {
        if mapView.userTrackingMode == .none {
            positionOnUserLocation()
        } else {
            mapView.setUserTrackingMode(.none, animated: true)
        }
    }

    /// MapKit drops tracking to `.none` by itself as soon as the user pans, so the
    /// glyph follows the map's actual state rather than the last tap.
    private func updateTrackingGlyph() {
        trackingButton.setImage(
            Self.locationGlyph(filled: mapView.userTrackingMode != .none),
            for: .normal
        )
    }

    /// Fallback framing when there is no user location to centre on: show every pin
    /// rather than jumping to whichever entry happens to be first.
    private func fitEntriesIfNeeded() {
        guard !hasPositionedMap else { return }
        let entryAnnotations = mapView.annotations.compactMap { $0 as? EntryAnnotation }
        guard !entryAnnotations.isEmpty else { return }

        hasPositionedMap = true
        mapView.showAnnotations(entryAnnotations, animated: true)
    }

    private func refreshPins() {
        let annotations = viewModel.entries
            .filter { $0.place.coordinate != nil }
            .map { EntryAnnotation(placeCheckin: $0) }

        // Only our own pins — passing MKUserLocation to removeAnnotations takes the
        // blue dot with it.
        mapView.removeAnnotations(mapView.annotations.filter { $0 is EntryAnnotation })
        mapView.addAnnotations(annotations)

        fitEntriesIfNeeded()
    }

}

// MARK: – CLLocationManagerDelegate

extension MapViewController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        positionOnUserLocation()
    }
}

// MARK: – MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        updateTrackingGlyph()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let ann = annotation as? EntryAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
            for: annotation
        ) as? MKMarkerAnnotationView
        view?.glyphText       = ann.placeCheckin.place.foodCategory.emoji
        view?.markerTintColor = Theme.categoryColor(ann.placeCheckin.place.foodCategory)
        view?.canShowCallout  = true

        // Arrow accessory — taps launch directions rather than opening the entry.
        let directions = UIButton(type: .system)
        directions.setImage(
            UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)),
            for: .normal
        )
        directions.tintColor = Theme.accent
        directions.sizeToFit()
        view?.rightCalloutAccessoryView = directions

        // Tappable place name over the star rating.
        view?.detailCalloutAccessoryView = calloutContent(for: ann)

        return view
    }

    /// Callout body: the place name as a button, with the stars underneath.
    private func calloutContent(for ann: EntryAnnotation) -> UIView {
        let pc = ann.placeCheckin

        let name = UIButton(type: .system)
        name.setTitle(pc.place.name.isEmpty ? "Unknown place" : pc.place.name, for: .normal)
        name.setTitleColor(Theme.accent, for: .normal)
        name.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        name.titleLabel?.numberOfLines = 2
        name.titleLabel?.lineBreakMode = .byWordWrapping
        name.contentHorizontalAlignment = .leading
        // Acted on directly rather than through calloutAccessoryControlTapped, which
        // is only dependable for the left and right accessory views.
        name.addAction(UIAction { [weak self] _ in self?.openDetail(for: pc) }, for: .touchUpInside)

        let stars = UILabel()
        stars.attributedText = StarRatingView.compactAttributedStars(for: ann.rating)

        let stack = UIStackView(arrangedSubviews: [name, stars])
        stack.axis      = .vertical
        stack.spacing   = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Callouts have no intrinsic width; cap it so a long name wraps instead of
        // stretching the bubble across the map.
        stack.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        return stack
    }

    /// White capsule plate behind a map control, so the glyph stays legible over any
    /// map content without needing a shadow halo of its own.
    private func capsule(around control: UIView) -> UIView {
        let side: CGFloat = 40

        let container = UIView()
        Theme.applyCardStyle(to: container)
        container.backgroundColor    = .white
        container.layer.cornerRadius = side / 2
        container.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: side),
            container.heightAnchor.constraint(equalToConstant: side),
            control.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func openDetail(for pc: PlaceCheckin) {
        let detail = EntryDetailViewController(viewModel: EntryDetailViewModel(placeCheckin: pc))
        navigationController?.pushViewController(detail, animated: true)
    }

    func mapView(_ mapView: MKMapView,
                 annotationView view: MKAnnotationView,
                 calloutAccessoryControlTapped control: UIControl) {
        guard control === view.rightCalloutAccessoryView,
              let ann = view.annotation as? EntryAnnotation,
              let coord = ann.placeCheckin.place.coordinate else { return }
        MapsNavigator.openDirections(to: coord, name: ann.placeCheckin.place.name)
    }
}
