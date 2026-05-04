// MARK: – MVVM | View
// Settings screen. Reads display values from SettingsViewModel and delegates all
// mutations to it. Reloads when the Firestore profile arrives.

import UIKit

final class SettingsViewController: UIViewController {

    // MARK: – MVVM

    private let viewModel = SettingsViewModel()

    // MARK: – Table sections

    private enum Section: Int, CaseIterable {
        case display, account, data, about
        var title: String {
            switch self {
            case .display: return "Display"
            case .account: return "Account"
            case .data:    return "Data"
            case .about:   return "About"
            }
        }
    }

    private struct Row {
        let title:        String
        let subtitle:     String?
        let accessory:    UITableViewCell.AccessoryType
        let isDestructive: Bool
        let action:       (() -> Void)?
    }

    // Computed so it re-reads fresh values after profile loads
    private var rows: [[Row]] {[
        // Display
        [
            Row(title: "Default Privacy", subtitle: viewModel.defaultPrivacyLabel,
                accessory: .disclosureIndicator, isDestructive: false) { [weak self] in
                self?.viewModel.toggleDefaultPrivacy()
                self?.tableView.reloadData()
            },
            Row(title: "Sort By", subtitle: viewModel.currentSortOrder,
                accessory: .disclosureIndicator, isDestructive: false) { [weak self] in
                self?.showSortOptions()
            }
        ],
        // Account
        [
            Row(title: "Member Since", subtitle: viewModel.memberSince,
                accessory: .none, isDestructive: false, action: nil),
            Row(title: "Email Verified", subtitle: viewModel.isEmailVerified ? "✓ Verified" : "Not verified",
                accessory: .none, isDestructive: false, action: nil),
            Row(title: "Sign Out", subtitle: nil,
                accessory: .none, isDestructive: true) { [weak self] in
                self?.confirmSignOut()
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
            Row(title: "Palate Pass", subtitle: "Version 1.0",
                accessory: .none, isDestructive: false, action: nil),
            Row(title: "Built with ❤️ in Swift", subtitle: nil,
                accessory: .none, isDestructive: false, action: nil)
        ]
    ]}

    // MARK: – Header outlets

    private weak var avatarButton:   UIButton?
    private weak var nameField:      UITextField?
    private weak var emailLabel:     UILabel?
    private weak var statsLabel:     UILabel?

    // MARK: – UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.dataSource = self
        tv.delegate   = self
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        tableView.tableHeaderView = buildHeaderView()
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        bindViewModel()
        viewModel.loadProfile()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh stats (entry count may have changed)
        statsLabel?.text = viewModel.statsLine
        tableView.reloadData()
    }

    // MARK: – ViewModel bindings

    private func bindViewModel() {
        viewModel.onMessage = { [weak self] msg in
            self?.present(UIAlertController.simpleAlert(title: "Updated", message: msg), animated: true)
        }
        viewModel.onExportReady = { [weak self] url in
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = self?.view
            self?.present(vc, animated: true)
        }
        viewModel.onProfileLoaded = { [weak self] in
            guard let self else { return }
            // Refresh header labels with Firestore data
            self.nameField?.text  = self.viewModel.displayName
            self.emailLabel?.text = self.viewModel.email
            self.statsLabel?.text = self.viewModel.statsLine
            self.tableView.reloadData()
        }
        viewModel.onSignOut = {
            SceneDelegate.current?.showAuthFlow()
        }
    }

    // MARK: – Header builder

    private func buildHeaderView() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 160))
        container.backgroundColor = .clear

        // Card
        let card = UIView()
        card.backgroundColor    = .systemBackground
        card.layer.cornerRadius = 20
        card.layer.shadowColor  = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.12).cgColor
        card.layer.shadowOpacity = 1
        card.layer.shadowRadius  = 10
        card.layer.shadowOffset  = CGSize(width: 0, height: 3)
        card.translatesAutoresizingMaskIntoConstraints = false

        // Avatar shadow wrapper
        let shadowWrap = UIView()
        shadowWrap.layer.shadowColor   = Theme.accentMid.cgColor
        shadowWrap.layer.shadowOpacity = 1
        shadowWrap.layer.shadowRadius  = 10
        shadowWrap.layer.shadowOffset  = CGSize(width: 0, height: 3)
        shadowWrap.translatesAutoresizingMaskIntoConstraints = false

        let avatarSize: CGFloat = 86
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

        // Name field — shows displayName from Firebase; editable
        let field = UITextField()
        field.text            = viewModel.displayName
        field.placeholder     = "Your name"
        field.font            = .systemFont(ofSize: 20, weight: .bold)
        field.delegate        = self
        field.returnKeyType   = .done
        field.clearButtonMode = .whileEditing

        // Email label — read-only
        let emailLbl = UILabel()
        emailLbl.text      = viewModel.email
        emailLbl.font      = .systemFont(ofSize: 13)
        emailLbl.textColor = .secondaryLabel

        // Stats label
        let statsLbl = UILabel()
        statsLbl.text      = viewModel.statsLine
        statsLbl.font      = .systemFont(ofSize: 12)
        statsLbl.textColor = .tertiaryLabel

        let textStack = UIStackView(arrangedSubviews: [field, emailLbl, statsLbl])
        textStack.axis    = .vertical
        textStack.spacing = 2

        let hStack = UIStackView(arrangedSubviews: [shadowWrap, textStack])
        hStack.axis      = .horizontal
        hStack.spacing   = 16
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(hStack)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            shadowWrap.widthAnchor.constraint(equalToConstant: avatarSize),
            shadowWrap.heightAnchor.constraint(equalToConstant: avatarSize),
            avatarBtn.topAnchor.constraint(equalTo: shadowWrap.topAnchor),
            avatarBtn.leadingAnchor.constraint(equalTo: shadowWrap.leadingAnchor),
            avatarBtn.trailingAnchor.constraint(equalTo: shadowWrap.trailingAnchor),
            avatarBtn.bottomAnchor.constraint(equalTo: shadowWrap.bottomAnchor),

            hStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            hStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            hStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18)
        ])

        // Store weak refs for later updates
        self.avatarButton = avatarBtn
        self.nameField    = field
        self.emailLabel   = emailLbl
        self.statsLabel   = statsLbl

        return container
    }

    // MARK: – Actions

    @objc private func dismissKeyboard() { view.endEditing(true) }

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
            UserDefaults.standard.removeObject(forKey: "avatarImageData")
            let cfg = UIImage.SymbolConfiguration(pointSize: 34, weight: .medium)
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
                self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(title: "Sign Out?",
                                      message: "You will need to sign in again to access your entries.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
            self?.viewModel.signOut()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func confirmDeleteAll() {
        let alert = UIAlertController(title: "Delete All Entries?",
                                      message: "This cannot be undone.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteAllEntries()
            self?.statsLabel?.text = self?.viewModel.statsLine
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: – UITextFieldDelegate (display name save)

extension SettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let name = textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        viewModel.displayName = name
        // Re-populate in case it was empty and fell back to email prefix
        textField.text = viewModel.displayName
    }
}

// MARK: – UIImagePickerControllerDelegate

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
        let cell = UITableViewCell(style: row.subtitle != nil ? .value1 : .default, reuseIdentifier: nil)
        cell.textLabel?.text          = row.title
        cell.detailTextLabel?.text    = row.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType            = row.accessory
        if row.isDestructive { cell.textLabel?.textColor = .systemRed }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.section][indexPath.row].action?()
    }
}
