// MARK: – MVVM | View
// Settings screen. Reads display values from SettingsViewModel and delegates all
// mutations and data operations to it. No UserDefaults or DataManager access here.

import UIKit

final class SettingsViewController: UIViewController {

    // MARK: – MVVM wiring

    private let viewModel = SettingsViewModel()

    // MARK: – Table structure

    private enum Section: Int, CaseIterable {
        case display, data, about
        var title: String {
            switch self {
            case .display: return "Display"
            case .data:    return "Data"
            case .about:   return "About"
            }
        }
    }

    private struct Row {
        let title: String
        let subtitle: String?
        let accessory: UITableViewCell.AccessoryType
        let isDestructive: Bool
        let action: (() -> Void)?
    }

    private lazy var rows: [[Row]] = [
        // Display
        [
            Row(title: "Default Privacy", subtitle: viewModel.defaultPrivacyLabel,
                accessory: .disclosureIndicator, isDestructive: false) { [weak self] in
                self?.viewModel.toggleDefaultPrivacy()
            },
            Row(title: "Sort By", subtitle: viewModel.currentSortOrder,
                accessory: .disclosureIndicator, isDestructive: false) { [weak self] in
                self?.showSortOptions()
            }
        ],
        // Data
        [
            Row(title: "Export Entries", subtitle: "Share as JSON",
                accessory: .disclosureIndicator, isDestructive: false) { [weak self] in
                self?.viewModel.exportData()
            },
            Row(title: "Delete All Entries", subtitle: nil,
                accessory: .none, isDestructive: true) { [weak self] in
                self?.confirmDeleteAll()
            }
        ],
        // About
        [
            Row(title: "Foodie", subtitle: "Version 1.0",
                accessory: .none, isDestructive: false, action: nil),
            Row(title: "Built with ❤️ in Swift", subtitle: nil,
                accessory: .none, isDestructive: false, action: nil)
        ]
    ]

    // MARK: – Header outlets (populated in buildHeaderView)

    private weak var avatarButton: UIButton?
    private weak var usernameField: UITextField?

    // MARK: – UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.dataSource = self
        tv.delegate   = self
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var headerView: UIView = buildHeaderView()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        tableView.tableHeaderView = headerView

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Bind ViewModel output
        viewModel.onMessage = { [weak self] msg in
            let alert = UIAlertController(title: "Updated", message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
        viewModel.onExportReady = { [weak self] url in
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = self?.view
            self?.present(vc, animated: true)
        }

        // Dismiss keyboard when tapping outside text field
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    // MARK: – Actions

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func avatarTapped() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true

        let sheet = UIAlertController(title: "Change Photo", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self] _ in
                picker.sourceType = .camera
                self?.present(picker, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            picker.sourceType = .photoLibrary
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Remove Photo", style: .destructive) { [weak self] _ in
            self?.applyAvatarImage(nil)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = avatarButton
        present(sheet, animated: true)
    }

    private func applyAvatarImage(_ image: UIImage?) {
        guard let btn = avatarButton else { return }
        if let image {
            viewModel.saveAvatar(image)
            btn.setImage(image, for: .normal)
            btn.imageView?.contentMode = .scaleAspectFill
            btn.tintColor = nil
        } else {
            // Reset to default fork icon
            UserDefaults.standard.removeObject(forKey: "avatarImageData")
            let cfg = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
            btn.setImage(UIImage(systemName: "fork.knife", withConfiguration: cfg), for: .normal)
            btn.imageView?.contentMode = .scaleAspectFit
            btn.tintColor = .white
        }
    }

    private func showSortOptions() {
        let alert = UIAlertController(title: "Sort By", message: nil, preferredStyle: .actionSheet)
        let options = ["Date (newest first)", "Date (oldest first)", "Rating (highest first)", "Rating (lowest first)"]
        for opt in options {
            alert.addAction(UIAlertAction(title: opt, style: .default) { [weak self] _ in
                self?.viewModel.setSortOrder(opt)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func confirmDeleteAll() {
        let alert = UIAlertController(
            title: "Delete All Entries?",
            message: "This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteAllEntries()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: – Header builder

    private func buildHeaderView() -> UIView {
        // Outer container: 10 % shorter than original 160 pt → 144 pt
        // Transparent so table's grouped background shows through
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 144))
        container.backgroundColor = .clear

        // ── Card — the visible section delimiter ──
        // White card with rounded corners + subtle blue shadow creates a clear
        // visual boundary between the profile block and the table rows below.
        let card = UIView()
        card.backgroundColor    = .systemBackground
        card.layer.cornerRadius = 20
        card.layer.shadowColor  = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.12).cgColor
        card.layer.shadowOpacity = 1
        card.layer.shadowRadius  = 10
        card.layer.shadowOffset  = CGSize(width: 0, height: 3)
        card.translatesAutoresizingMaskIntoConstraints = false

        // ── Avatar shadow wrapper (no clipsToBounds → shadow renders) ──
        let shadowWrap = UIView()
        shadowWrap.layer.shadowColor   = Theme.accentMid.cgColor
        shadowWrap.layer.shadowOpacity = 1
        shadowWrap.layer.shadowRadius  = 10
        shadowWrap.layer.shadowOffset  = CGSize(width: 0, height: 3)
        shadowWrap.translatesAutoresizingMaskIntoConstraints = false

        // 20 % bigger than the old 72 pt → 86 pt
        let avatarSize: CGFloat = 86

        // ── Avatar button (clips image to circle) ──
        let avatarBtn = UIButton(type: .custom)
        avatarBtn.backgroundColor    = Theme.accent
        avatarBtn.layer.cornerRadius = avatarSize / 2
        avatarBtn.clipsToBounds      = true
        avatarBtn.translatesAutoresizingMaskIntoConstraints = false
        avatarBtn.addTarget(self, action: #selector(avatarTapped), for: .touchUpInside)

        if let savedImg = viewModel.avatarImage {
            avatarBtn.setImage(savedImg, for: .normal)
            avatarBtn.imageView?.contentMode = .scaleAspectFill
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 34, weight: .medium)
            avatarBtn.setImage(UIImage(systemName: "fork.knife", withConfiguration: cfg), for: .normal)
            avatarBtn.imageView?.contentMode = .scaleAspectFit
            avatarBtn.tintColor = .white
        }

        shadowWrap.addSubview(avatarBtn)

        // ── Username text field ──
        let field = UITextField()
        field.text            = viewModel.username
        field.placeholder     = "Your name"
        field.font            = .systemFont(ofSize: 20, weight: .bold)
        field.delegate        = self
        field.returnKeyType   = .done
        field.clearButtonMode = .whileEditing

        // ── Stats label ──
        let statsLabel = UILabel()
        statsLabel.text      = viewModel.statsLine
        statsLabel.font      = .systemFont(ofSize: 12)
        statsLabel.textColor = .secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [field, statsLabel])
        textStack.axis    = .vertical
        textStack.spacing = 3

        let hStack = UIStackView(arrangedSubviews: [shadowWrap, textStack])
        hStack.axis      = .horizontal
        hStack.spacing   = 16
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(hStack)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            // Card inset from outer container — gives breathing room that acts as margin
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            // Avatar size in shadow wrapper
            shadowWrap.widthAnchor.constraint(equalToConstant: avatarSize),
            shadowWrap.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarBtn.topAnchor.constraint(equalTo: shadowWrap.topAnchor),
            avatarBtn.leadingAnchor.constraint(equalTo: shadowWrap.leadingAnchor),
            avatarBtn.trailingAnchor.constraint(equalTo: shadowWrap.trailingAnchor),
            avatarBtn.bottomAnchor.constraint(equalTo: shadowWrap.bottomAnchor),

            // Content row centred vertically in card, with left/right padding
            hStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            hStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            hStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18)
        ])

        // Store weak refs for later mutation
        self.avatarButton  = avatarBtn
        self.usernameField = field

        return container
    }
}

// MARK: – UITextFieldDelegate (username save)

extension SettingsViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        viewModel.username = textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

// MARK: – UIImagePickerControllerDelegate (avatar photo)

extension SettingsViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        applyAvatarImage(img)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: – UITableViewDataSource / Delegate

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.section][indexPath.row]
        let cell = UITableViewCell(style: row.subtitle != nil ? .subtitle : .default, reuseIdentifier: nil)
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = row.accessory
        if row.isDestructive { cell.textLabel?.textColor = .systemRed }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.section][indexPath.row].action?()
    }
}
