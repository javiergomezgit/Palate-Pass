// MARK: – MVVM | View
// Renders entries as map pins. Binds to HomeViewModel — never reads DataManager or owns filter state.

import UIKit
import MapKit

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
        self.title    = pc.place.name.isEmpty ? cat.emoji : "\(cat.emoji) \(pc.place.name)"
        self.subtitle = pc.place.category
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
        mv.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        viewModel.addEntriesUpdatedHandler { [weak self] in self?.refreshPins() }
        refreshPins()
    }

    // MARK: – Private

    private func refreshPins() {
        let annotations = viewModel.entries
            .filter { $0.place.coordinate != nil }
            .map { EntryAnnotation(placeCheckin: $0) }

        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(annotations)

        if let first = annotations.first {
            mapView.setRegion(
                MKCoordinateRegion(center: first.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000),
                animated: true
            )
        }
    }
}

// MARK: – MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {

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

        // Star rating, shown below the category subtitle.
        let stars = UILabel()
        stars.attributedText = StarRatingView.compactAttributedStars(for: ann.rating)
        view?.detailCalloutAccessoryView = stars

        return view
    }

    func mapView(_ mapView: MKMapView,
                 annotationView view: MKAnnotationView,
                 calloutAccessoryControlTapped control: UIControl) {
        guard let ann = view.annotation as? EntryAnnotation,
              let coord = ann.placeCheckin.place.coordinate else { return }
        MapsNavigator.openDirections(to: coord, name: ann.placeCheckin.place.name)
    }
}
