import UIKit
// import FirebaseAuth   ← uncomment after Firebase is configured

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

        // After Firebase is configured, replace the line below with:
        //   let isLoggedIn = Auth.auth().currentUser != nil
        //   window.rootViewController = isLoggedIn ? MainTabBarController() : makeAuthNavigation()
        window.rootViewController = makeAuthNavigation()

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

    // MARK: – Private

    private func makeAuthNavigation() -> UINavigationController {
        let nav = UINavigationController(rootViewController: AuthLandingViewController())
        nav.navigationBar.tintColor = Theme.accent
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }
}
