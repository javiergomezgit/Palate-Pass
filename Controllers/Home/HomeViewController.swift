// MARK: – MVVM | View
// Container for the Home tab. Owns the shared HomeViewModel and passes it to both
// child view controllers. Handles the segment toggle and filter UI only.

import UIKit

final class HomeViewController: UIViewController {

    // MARK: – MVVM wiring

    private let viewModel = HomeViewModel()

    // MARK: – Child VCs (receive the shared ViewModel at creation)

    private lazy var listVC = ListViewController(viewModel: viewModel)
    private lazy var mapVC  = MapViewController(viewModel: viewModel)
    private var activeChild: UIViewController?

    // MARK: – UI

    private let segmentControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["  List  ", "  Map  "])
        sc.selectedSegmentIndex = 0
        // Blue fill for selected; tinted background makes the capsule visible at a glance
        sc.selectedSegmentTintColor = Theme.accent
        sc.backgroundColor = Theme.accentLight
        sc.setTitleTextAttributes([.foregroundColor: UIColor.white,
                                   .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
        sc.setTitleTextAttributes([.foregroundColor: Theme.accent,
                                   .font: UIFont.systemFont(ofSize: 13, weight: .regular)], for: .normal)
        // 20 % wider: fix each segment at 108 pt → total control ~216 pt
        sc.setWidth(108, forSegmentAt: 0)
        sc.setWidth(108, forSegmentAt: 1)
        return sc
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My Ratings"
        view.backgroundColor = .systemBackground

        navigationItem.titleView = segmentControl
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(showFilter)
        )

        show(listVC)
    }

    // MARK: – Actions

    @objc private func segmentChanged() {
        show(segmentControl.selectedSegmentIndex == 0 ? listVC : mapVC)
    }

    @objc private func showFilter() {
        let alert = UIAlertController(title: "Filter by Category", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "All", style: .default) { [weak self] _ in
            self?.viewModel.applyFilter(nil)
        })
        for cat in FoodCategory.allCases {
            alert.addAction(UIAlertAction(title: "\(cat.emoji) \(cat.rawValue)", style: .default) { [weak self] _ in
                self?.viewModel.applyFilter(cat)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }

    // MARK: – Child VC container

    private func show(_ child: UIViewController) {
        guard child !== activeChild else { return }
        activeChild?.willMove(toParent: nil)
        activeChild?.view.removeFromSuperview()
        activeChild?.removeFromParent()

        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
        activeChild = child
    }
}
