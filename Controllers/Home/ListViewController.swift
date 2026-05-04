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
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
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

        // Bind to ViewModel output
        viewModel.onEntriesUpdated = { [weak self] in
            self?.refreshUI()
        }
        refreshUI()
    }

    // MARK: – Private

    private func refreshUI() {
        emptyLabel.isHidden = !viewModel.entries.isEmpty
        tableView.reloadData()
    }
}

// MARK: – UITableViewDataSource / Delegate

extension ListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EntryCell.reuseID, for: indexPath) as! EntryCell
        cell.configure(with: viewModel.entries[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entryVM = EntryDetailViewModel(entry: viewModel.entries[indexPath.row])
        let detail = EntryDetailViewController(viewModel: entryVM)
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let entry = viewModel.entries[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, done in
            DataManager.shared.delete(entry)
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
}
