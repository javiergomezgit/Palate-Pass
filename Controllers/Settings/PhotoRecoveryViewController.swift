// MARK: – MVVM | View
// Surfaces photos sitting in Documents/ that no entry references any more.
//
// These are the remains of entries the old `replaceAll` dropped: the cloud fetch
// replaced the local cache, the entry's metadata went with it, but the JPEG was never
// deleted. Each one can be turned back into an entry or thrown away.
//
// The photo's original capture date and location are NOT recoverable — jpegData()
// strips EXIF when the file is written — so the file's own creation date is offered
// as the closest available stand-in.

import UIKit

final class PhotoRecoveryViewController: UITableViewController {

    private var filenames: [String] = []

    // MARK: – Lifecycle

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recover Photos"
        tableView.rowHeight = 76
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Delete All", style: .plain, target: self, action: #selector(confirmDeleteAll)
        )
        navigationItem.rightBarButtonItem?.tintColor = .systemRed
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        filenames = DataManager.shared.orphanedImageFilenames()
        navigationItem.rightBarButtonItem?.isEnabled = !filenames.isEmpty
        tableView.reloadData()
    }

    // MARK: – Data source

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(filenames.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        filenames.isEmpty ? nil : "\(filenames.count) unattached photo\(filenames.count == 1 ? "" : "s")"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard !filenames.isEmpty else { return nil }
        return "Photos on this device that no entry uses. Some belong to entries that were lost; "
             + "others are leftovers from entries that synced fine. Tap one to rebuild an entry from it, "
             + "or swipe to delete. The date shown is when the file was saved — the photo's original "
             + "capture date and location were not kept."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.row < filenames.count else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "No unattached photos — nothing to recover."
            cell.textLabel?.font = .italicSystemFont(ofSize: 14)
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.numberOfLines = 0
            cell.selectionStyle = .none
            return cell
        }

        let name = filenames[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = Self.dateText(DataManager.shared.imageFileDate(named: name))
        cell.detailTextLabel?.text = "Tap to rebuild an entry from this photo"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator

        cell.imageView?.image = thumbnail(for: name)
        cell.imageView?.contentMode = .scaleAspectFill
        cell.imageView?.clipsToBounds = true
        cell.imageView?.layer.cornerRadius = 8
        return cell
    }

    /// UITableViewCell sizes imageView to the image, so downscale to a fixed square.
    private func thumbnail(for name: String) -> UIImage? {
        guard let image = DataManager.shared.loadImage(named: name) else { return nil }
        let side = CGSize(width: 58, height: 58)
        return UIGraphicsImageRenderer(size: side).image { _ in
            let scale = max(side.width / image.size.width, side.height / image.size.height)
            let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side.width - scaled.width) / 2,
                                  y: (side.height - scaled.height) / 2,
                                  width: scaled.width, height: scaled.height))
        }
    }

    // MARK: – Recover

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filenames.count else { return }
        let name = filenames[indexPath.row]
        guard let image = DataManager.shared.loadImage(named: name) else { return }

        let vm = AddEntryViewModel()
        vm.selectedImages = [image]
        vm.imagesModified = true
        if let date = DataManager.shared.imageFileDate(named: name) { vm.checkInDate = date }

        let addVC = AddEntryViewController(viewModel: vm)
        // The saved entry writes its own copy of the photo, so the original orphan
        // is only retired once the rebuild actually goes through.
        addVC.onEntrySaved = { [weak self] in
            DataManager.shared.discardImageFile(named: name)
            self?.reload()
        }
        addVC.title = "Rebuild Entry"
        navigationController?.pushViewController(addVC, animated: true)
    }

    // MARK: – Delete

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard indexPath.row < filenames.count else { return nil }
        let name = filenames[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            DataManager.shared.discardImageFile(named: name)
            self?.reload()
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func confirmDeleteAll() {
        let count = filenames.count
        let alert = UIAlertController(
            title: "Delete \(count) photo\(count == 1 ? "" : "s")?",
            message: "This permanently removes every unattached photo from this device. Entries that already use a photo are not affected.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            self?.filenames.forEach { DataManager.shared.discardImageFile(named: $0) }
            self?.reload()
        })
        present(alert, animated: true)
    }

    // MARK: – Helpers

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "Unknown date" }
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
