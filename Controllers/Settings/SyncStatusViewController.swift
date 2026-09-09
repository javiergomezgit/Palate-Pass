// MARK: – MVVM | View
// Answers "does what's on my phone match what's in the cloud?".
//
// Shows the outbox (writes that haven't uploaded yet) and a straight comparison of the
// local cache against a fresh Firestore fetch: on this device only, in the cloud only,
// or present in both but different.

import UIKit
import FirebaseAuth

final class SyncStatusViewController: UITableViewController {

    // MARK: – Comparison result

    private struct Difference {
        let placeCheckin: PlaceCheckin
        let detail:       String
    }

    private var localOnly: [PlaceCheckin] = []
    private var cloudOnly: [PlaceCheckin] = []
    private var differing: [Difference]   = []

    private var isComparing = false
    private var compareError: String?
    private var hasCompared  = false

    // MARK: – Sections

    private enum Section: Int, CaseIterable {
        case status, pending, localOnly, cloudOnly, differing

        var title: String {
            switch self {
            case .status:    return "Status"
            case .pending:   return "Waiting to upload"
            case .localOnly: return "On this device only"
            case .cloudOnly: return "In the cloud only"
            case .differing: return "Different in the cloud"
            }
        }
    }

    // MARK: – Lifecycle

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sync Status"
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(compare), for: .valueChanged)

        NotificationCenter.default.addObserver(
            self, selector: #selector(syncStateChanged),
            name: .syncStateDidChange, object: nil
        )
        compare()
    }

    // MARK: – Actions

    @objc private func syncStateChanged() {
        tableView.reloadData()
    }

    /// Pulls the cloud copy and diffs it against the local cache.
    @objc private func compare() {
        guard let uid = Auth.auth().currentUser?.uid else {
            compareError = "Not signed in."
            finishComparing()
            return
        }
        guard !isComparing else { return }
        isComparing = true
        compareError = nil
        tableView.reloadData()

        EntryService.shared.fetchCheckins(for: uid) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.compareError = error.localizedDescription
            case .success(let cloud):
                self.diff(cloud: cloud)
            }
            self.hasCompared = true
            self.finishComparing()
        }
    }

    private func finishComparing() {
        isComparing = false
        tableView.refreshControl?.endRefreshing()
        tableView.reloadData()
    }

    private func diff(cloud: [PlaceCheckin]) {
        let local     = DataManager.shared.checkins
        let cloudByID = Dictionary(cloud.map { ($0.checkin.id, $0) }, uniquingKeysWith: { a, _ in a })
        let localIDs  = Set(local.map { $0.checkin.id })

        localOnly = local.filter { cloudByID[$0.checkin.id] == nil }
        cloudOnly = cloud.filter { !localIDs.contains($0.checkin.id) }

        differing = local.compactMap { localPC in
            guard let cloudPC = cloudByID[localPC.checkin.id] else { return nil }
            let reasons = Self.differences(local: localPC, cloud: cloudPC)
            guard !reasons.isEmpty else { return nil }
            return Difference(placeCheckin: localPC, detail: reasons.joined(separator: ", "))
        }
    }

    /// Compares the fields the user can actually change. Local-only bookkeeping
    /// (imagePaths) is ignored — it never exists in Firestore by design.
    private static func differences(local: PlaceCheckin, cloud: PlaceCheckin) -> [String] {
        var reasons: [String] = []
        if local.place.name != cloud.place.name { reasons.append("name") }
        if local.place.category != cloud.place.category { reasons.append("category") }
        if local.checkin.personalRating != cloud.checkin.personalRating { reasons.append("rating") }
        if local.checkin.personalComment != cloud.checkin.personalComment { reasons.append("comment") }
        if local.checkin.visibility != cloud.checkin.visibility { reasons.append("privacy") }
        if local.checkin.imageURLs.count != cloud.checkin.imageURLs.count { reasons.append("photos") }
        // Sub-second drift is an artefact of Timestamp rounding, not a real edit.
        if abs(local.checkin.checkedInAt.timeIntervalSince(cloud.checkin.checkedInAt)) > 1 {
            reasons.append("date")
        }
        return reasons
    }

    @objc private func syncNow() {
        SyncCoordinator.shared.flush(force: true) { [weak self] in
            self?.compare()
        }
        tableView.reloadData()
    }

    // MARK: – Data source

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .status:    return 2
        case .pending:   return max(DataManager.shared.pendingOperations.count, 1)
        case .localOnly: return max(localOnly.count, 1)
        case .cloudOnly: return max(cloudOnly.count, 1)
        case .differing: return max(differing.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .localOnly:
            return "Entries saved here that Firebase has never received. They upload automatically once you're online."
        case .cloudOnly:
            return "Entries in your account that this device hasn't downloaded. Pull to refresh on the list to fetch them."
        case .status:
            return compareError.map { "Comparison failed: \($0)" }
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {

        case .status:
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                cell.textLabel?.text = SyncCoordinator.shared.isOnline ? "Connected" : "Offline"
                cell.detailTextLabel?.text = SyncCoordinator.shared.statusSummary
                cell.imageView?.image = UIImage(systemName: SyncCoordinator.shared.isOnline
                                                ? "checkmark.icloud" : "icloud.slash")
                cell.imageView?.tintColor = SyncCoordinator.shared.isOnline ? .systemGreen : .systemOrange
                cell.selectionStyle = .none
                return cell
            }
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = SyncCoordinator.shared.isFlushing ? "Syncing…" : "Sync Now"
            cell.textLabel?.textColor = Theme.accent
            let busy = SyncCoordinator.shared.isFlushing || !SyncCoordinator.shared.isOnline
            cell.textLabel?.isEnabled = !busy
            cell.selectionStyle = busy ? .none : .default
            return cell

        case .pending:
            let ops = DataManager.shared.pendingOperations
            guard indexPath.row < ops.count else { return emptyCell("Nothing waiting — everything is uploaded.") }
            let op = ops[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "\(op.kind.label) · \(op.placeCheckin.place.name)"
            var detail = "Queued \(Self.relative(op.queuedAt))"
            if op.attempts > 0 { detail += " · \(op.attempts) failed attempt\(op.attempts == 1 ? "" : "s")" }
            if let err = op.lastError { detail += " · \(err)" }
            cell.detailTextLabel?.text = detail
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = op.hasExhaustedRetries ? .systemRed : .secondaryLabel
            cell.imageView?.image = UIImage(systemName: op.hasExhaustedRetries
                                            ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                                            : "arrow.up.circle")
            cell.imageView?.tintColor = op.hasExhaustedRetries ? .systemRed : .systemOrange
            cell.selectionStyle = .none
            return cell

        case .localOnly:
            guard indexPath.row < localOnly.count else { return emptyCell(placeholder("Nothing — the cloud has everything on this device.")) }
            return entryCell(localOnly[indexPath.row], detail: "Not in the cloud")

        case .cloudOnly:
            guard indexPath.row < cloudOnly.count else { return emptyCell(placeholder("Nothing — this device has everything in the cloud.")) }
            return entryCell(cloudOnly[indexPath.row], detail: "Not on this device")

        case .differing:
            guard indexPath.row < differing.count else { return emptyCell(placeholder("Nothing — matching entries are identical.")) }
            let d = differing[indexPath.row]
            return entryCell(d.placeCheckin, detail: "Differs: \(d.detail)")
        }
    }

    // MARK: – Swipe to discard a stuck operation

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .pending else { return nil }
        let ops = DataManager.shared.pendingOperations
        guard indexPath.row < ops.count else { return nil }
        let op = ops[indexPath.row]

        let discard = UIContextualAction(style: .destructive, title: "Discard") { [weak self] _, _, done in
            self?.confirmDiscard(op)
            done(true)
        }
        discard.image = UIImage(systemName: "xmark.bin")
        return UISwipeActionsConfiguration(actions: [discard])
    }

    private func confirmDiscard(_ op: PendingOperation) {
        let alert = UIAlertController(
            title: "Discard queued \(op.kind.label.lowercased())?",
            message: "\"\(op.placeCheckin.place.name)\" will stop trying to upload. The entry stays on this device but the cloud will not be updated.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            SyncCoordinator.shared.discard(id: op.id)
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .status, indexPath.row == 1 else { return }
        guard SyncCoordinator.shared.isOnline, !SyncCoordinator.shared.isFlushing else { return }
        syncNow()
    }

    // MARK: – Cell helpers

    private func entryCell(_ pc: PlaceCheckin, detail: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = pc.place.name.isEmpty ? "Unknown place" : pc.place.name
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        cell.detailTextLabel?.text = "\(fmt.string(from: pc.checkin.checkedInAt)) · \(detail)"
        cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        return cell
    }

    private func emptyCell(_ text: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = text
        cell.textLabel?.font = .italicSystemFont(ofSize: 14)
        cell.textLabel?.textColor = .secondaryLabel
        cell.textLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        return cell
    }

    /// Avoids claiming "nothing to report" before the first comparison has run.
    private func placeholder(_ text: String) -> String {
        if isComparing { return "Checking…" }
        if compareError != nil { return "Couldn't compare with the cloud." }
        return hasCompared ? text : "Pull to compare with the cloud."
    }

    private static func relative(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
