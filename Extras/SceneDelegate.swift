import UIKit
import CoreLocation
import FirebaseAuth

private let appGroupID = "group.com.palatepass.app"

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // Convenience accessor used by auth controllers to trigger the transition
    static var current: SceneDelegate? {
        UIApplication.shared.connectedScenes
            .compactMap { $0.delegate as? SceneDelegate }
            .first
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

       let isLoggedIn = Auth.auth().currentUser != nil
       window.rootViewController = isLoggedIn ? MainTabBarController() : makeAuthNavigation()

        window.makeKeyAndVisible()
        self.window = window
    }

    // MARK: – Transitions

    func showMainApp() {
        guard let window else { return }
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = MainTabBarController()
        }
    }

    func showAuthFlow() {
        guard let window else { return }
        UIView.transition(with: window, duration: 0.4, options: .transitionCrossDissolve) {
            window.rootViewController = self.makeAuthNavigation()
        }
    }

    // MARK: – Scene active (picks up data saved by Share Extension)

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Coming back to the app is a good moment to drain anything still queued.
        SyncCoordinator.shared.flush()
        checkForSharedData()
    }

    private func checkForSharedData() {
        guard Auth.auth().currentUser != nil else { return }
        let defaults = UserDefaults(suiteName: appGroupID)!
        guard let imageData = defaults.data(forKey: "sharedImage") else { return }

        let latitude  = defaults.double(forKey: "sharedLatitude")
        let longitude = defaults.double(forKey: "sharedLongitude")
        let name      = defaults.string(forKey: "sharedEntryName")   ?? ""
        let rating    = defaults.integer(forKey: "sharedEntryRating")
        let comment   = defaults.string(forKey: "sharedEntryComment") ?? ""
        let dateStamp = defaults.double(forKey: "sharedEntryDate")

        ["sharedImage", "sharedLatitude", "sharedLongitude",
         "sharedEntryName", "sharedEntryRating", "sharedEntryComment",
         "sharedEntryDate"]
            .forEach { defaults.removeObject(forKey: $0) }

        let image = UIImage(data: imageData)
        let coordinate: CLLocationCoordinate2D? = (latitude != 0 || longitude != 0)
            ? CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            : nil
        // 0 means the extension found no date in the photo — fall back to "now".
        let captureDate: Date? = dateStamp > 0 ? Date(timeIntervalSince1970: dateStamp) : nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.openAddEntry(image: image, coordinate: coordinate,
                               name: name, rating: Double(rating), comment: comment,
                               captureDate: captureDate)
        }
    }

    private func openAddEntry(image: UIImage?,
                              coordinate: CLLocationCoordinate2D?,
                              name: String = "",
                              rating: Double = 0,
                              comment: String = "",
                              captureDate: Date? = nil) {
        guard let tabBar = window?.rootViewController as? MainTabBarController else { return }

        let vm = AddEntryViewModel()
        if let image        { vm.selectedImages = [image] }
        if let coordinate   { vm.location   = coordinate }
        if !name.isEmpty    { vm.placeName  = name }
        if rating > 0       { vm.rating     = rating }
        if !comment.isEmpty { vm.comment    = comment }
        if let captureDate  { vm.checkInDate = captureDate }
        vm.visibility = .private

        // Save immediately — entry will appear in the list for the user to edit if needed
        vm.onSaveSuccess = { [weak tabBar] in
            tabBar?.selectedIndex = 0   // go to home/list tab
        }
        vm.onSaveQueued = { [weak tabBar] _ in
            tabBar?.selectedIndex = 0   // still navigate; the entry is queued for upload
        }
        vm.onValidationError = { [weak tabBar] _ in
            // name or rating missing — open AddEntry so user can complete it
            guard let tabBar else { return }
            let addVC = AddEntryViewController(viewModel: vm)
            addVC.prefillCoordinate = coordinate
            tabBar.selectedIndex = 1
            (tabBar.selectedViewController as? UINavigationController)?
                .pushViewController(addVC, animated: true)
        }

        vm.save()
    }

    // MARK: – Private

    private func makeAuthNavigation() -> UINavigationController {
        let nav = UINavigationController(rootViewController: AuthLandingViewController())
        nav.navigationBar.tintColor = Theme.accent
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }
}
