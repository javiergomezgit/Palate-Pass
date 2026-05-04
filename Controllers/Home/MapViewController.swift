// MARK: – MVVM | View
// Renders entries as map pins. Binds to HomeViewModel — never reads DataManager or owns filter state.

import UIKit
import MapKit

// MARK: – Map annotation (View-layer helper, not a Model)

final class EntryAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let entry: FoodEntry

    init(entry: FoodEntry) {
        self.entry = entry
        self.coordinate = entry.coordinate ?? CLLocationCoordinate2D()
        self.title    = entry.placeName.isEmpty ? entry.category.emoji : "\(entry.category.emoji) \(entry.placeName)"
        self.subtitle = entry.category.rawValue
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

        // Bind to ViewModel output
        viewModel.onEntriesUpdated = { [weak self] in
            self?.refreshPins()
        }
        refreshPins()
    }

    // MARK: – Private

    private func refreshPins() {
        let annotations = viewModel.entries
            .filter { $0.coordinate != nil }
            .map { EntryAnnotation(entry: $0) }

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
        view?.glyphText      = ann.entry.category.emoji
        view?.markerTintColor = categoryColor(ann.entry.category)
        view?.canShowCallout  = true
        view?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        return view
    }

    func mapView(_ mapView: MKMapView,
                 annotationView view: MKAnnotationView,
                 calloutAccessoryControlTapped control: UIControl) {
        guard let ann = view.annotation as? EntryAnnotation else { return }
        let entryVM = EntryDetailViewModel(entry: ann.entry)
        let detail  = EntryDetailViewController(viewModel: entryVM)
        navigationController?.pushViewController(detail, animated: true)
    }

    private func categoryColor(_ cat: FoodCategory) -> UIColor {
        Theme.categoryColor(cat)
    }
}
