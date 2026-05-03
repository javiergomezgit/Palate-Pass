// MARK: – MVVM | View
// App entry point for the View layer. Assembles the three top-level View hierarchies.
// No business logic — each tab's ViewController creates its own ViewModel internally.

import UIKit

final class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        styleTabBar()
        styleNavBar()
    }

    private func setupTabs() {
        let homeVC = HomeViewController()
        homeVC.tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage(systemName: "fork.knife"),
            selectedImage: UIImage(systemName: "fork.knife")
        )

        let addVC = AddEntryViewController()
        addVC.tabBarItem = UITabBarItem(
            title: "Add",
            image: UIImage(systemName: "plus.circle"),
            selectedImage: UIImage(systemName: "plus.circle.fill")
        )

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        viewControllers = [
            UINavigationController(rootViewController: homeVC),
            UINavigationController(rootViewController: addVC),
            UINavigationController(rootViewController: settingsVC)
        ]
    }

    private func styleTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor   = .tertiaryLabel
        itemAppearance.normal.titleTextAttributes   = [.foregroundColor: UIColor.tertiaryLabel]
        itemAppearance.selected.iconColor = Theme.accent
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: Theme.accent,
                                                       .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]

        appearance.stackedLayoutAppearance = itemAppearance
        tabBar.standardAppearance   = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = Theme.accent
    }

    private func styleNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [
            .foregroundColor: Theme.accent,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: Theme.accentDeep,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = Theme.accent
    }
}
