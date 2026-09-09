// MARK: – MVVM | View helper
// Hands a coordinate off to Apple Maps for turn-by-turn directions.
// Pure UI plumbing — no models, no ViewModels.

import MapKit

enum MapsNavigator {

    /// Opens Apple Maps with driving directions to `coordinate`.
    static func openDirections(to coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name.isEmpty ? "Destination" : name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
