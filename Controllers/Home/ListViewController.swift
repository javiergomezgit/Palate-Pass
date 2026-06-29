// MARK: – MVVM | View
// Renders the entry list. Binds to HomeViewModel — never reads DataManager or owns filter state.

import UIKit

final class ListViewController: UIViewController {

    // MARK: – MVVM wiring

    private let viewModel: HomeViewModel

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.register(EntryCell.self, forCellReuseIdentifier: EntryCell.reuseID)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 90
        tv.dataSource = self
        tv.delegate = self
        tv.refreshControl = refreshControl
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return rc
    }()

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No entries yet.\nTap + to add your first rating!"
        l.numberOfLines = 2
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 16)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)

        viewModel.onEntriesUpdated = { [weak self] in
            self?.refreshControl.endRefreshing()
            self?.refreshUI()
        }
        viewModel.onFetchError = { [weak self] message in
            self?.refreshControl.endRefreshing()
            self?.showFetchError(message)
        }
        viewModel.onPinLimitReached = { [weak self] in
            let alert = UIAlertController(
                title: "Pin Limit Reached",
                message: "You can pin up to \(HomeViewModel.maxPins) entries. Unpin one to add another.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
        refreshUI()
    }

    // MARK: – Private

    private func refreshUI() {
        let totalEmpty = viewModel.pinnedEntries.isEmpty && viewModel.entries.isEmpty
        emptyLabel.isHidden = !totalEmpty
        if totalEmpty {
            emptyLabel.text = viewModel.searchQuery.isEmpty
                ? "No entries yet.\nTap + to add your first rating!"
                : "No results for \"\(viewModel.searchQuery)\"."
        }
        tableView.reloadData()
    }

    @objc private func handleRefresh() {
        viewModel.fetchFromFirestore()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let entry = entryFor(indexPath) else { return }
        let isPinned = viewModel.isPinned(entry)
        let title = isPinned ? "Unpin \"\(entry.placeName)\"" : "Pin \"\(entry.placeName)\""
        let actionTitle = isPinned ? "Unpin" : "📌 Pin to Top"

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
            self?.viewModel.togglePin(entry)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(alert, animated: true)
    }

    // Returns the FoodEntry for a given indexPath across both sections.
    private func entryFor(_ indexPath: IndexPath) -> FoodEntry? {
        if indexPath.section == 0 && !viewModel.pinnedEntries.isEmpty {
            guard indexPath.row < viewModel.pinnedEntries.count else { return nil }
            return viewModel.pinnedEntries[indexPath.row]
        } else {
            guard indexPath.row < viewModel.entries.count else { return nil }
            return viewModel.entries[indexPath.row]
        }
    }

    private func shareEntry(_ entry: FoodEntry, image: UIImage?) {
        let stars = String(repeating: "⭐", count: Int(entry.rating.rounded()))
        var text = "Check out \(entry.placeName)! I rated it \(stars) (\(String(format: "%.1f", entry.rating))/5) on Palate Pass \(entry.category.emoji)"
        if !entry.comment.isEmpty {
            text += "\n\"\(entry.comment)\""
        }

        var items: [Any] = [text]
        if let image { items.append(image) }

        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad popover anchor — find the tapped cell's share button if possible
        ac.popoverPresentationController?.sourceView = view
        ac.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        present(ac, animated: true)
    }

    private func showFetchError(_ message: String) {
        // Show a non-intrusive toast-style alert that auto-dismisses
        let alert = UIAlertController(
            title: "Sync Failed",
            message: "Showing cached entries. \(message)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: – UITableViewDataSource / Delegate

extension ListViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        // Section 0 = Pinned (hidden when empty), Section 1 = All entries
        viewModel.pinnedEntries.isEmpty ? 1 : 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !viewModel.pinnedEntries.isEmpty && section == 0 {
            return viewModel.pinnedEntries.count
        }
        return viewModel.entries.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !viewModel.pinnedEntries.isEmpty else { return nil }
        return section == 0 ? "📌 Pinned" : "My Ratings"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EntryCell.reuseID, for: indexPath) as! EntryCell
        guard let entry = entryFor(indexPath) else { return cell }
        cell.configure(with: entry)
        cell.onShare = { [weak self] image in
            self?.shareEntry(entry, image: image)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let entry = entryFor(indexPath) else { return }
        let entryVM = EntryDetailViewModel(entry: entry)
        let detail = EntryDetailViewController(viewModel: entryVM)
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let entry = entryFor(indexPath) else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.viewModel.delete(entry)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")

        let nextVisibility: EntryVisibility
        let visibilityTitle: String
        let visibilityIcon: String
        switch entry.visibility {
        case .public:  nextVisibility = .friends; visibilityTitle = "Share"; visibilityIcon = "person.2"
        case .friends: nextVisibility = .private; visibilityTitle = "Make Private"; visibilityIcon = "lock"
        case .private: nextVisibility = .public;  visibilityTitle = "Make Public";  visibilityIcon = "globe"
        }

        let privacy = UIContextualAction(style: .normal, title: visibilityTitle) { _, _, done in
            var updated = entry
            updated.visibility = nextVisibility
            DataManager.shared.update(updated)
            done(true)
        }
        privacy.backgroundColor = .systemIndigo
        privacy.image = UIImage(systemName: visibilityIcon)

        return UISwipeActionsConfiguration(actions: [delete, privacy])
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let entry = entryFor(indexPath), viewModel.isPinned(entry) else { return nil }

        let unpin = UIContextualAction(style: .normal, title: "Unpin") { [weak self] _, _, done in
            self?.viewModel.togglePin(entry)
            done(true)
        }
        unpin.image = UIImage(systemName: "pin.slash.fill")
        unpin.backgroundColor = .systemOrange

        return UISwipeActionsConfiguration(actions: [unpin])
    }
}
