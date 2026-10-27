import UIKit

@MainActor
final class SessionListViewController: UITableViewController {
    private let store: WorkoutStore
    private let recovery: Bool
    private var observer: UUID?
    private var document: WorkoutDocument? { recovery ? store.record?.recoveryCopy : store.record?.local }
    private var sections: [[WorkoutSession]] {
        let sessions = document?.sessions ?? []
        return [sessions.filter { !$0.discarded }.reversed(), sessions.filter(\.discarded).reversed()]
    }
    init(store: WorkoutStore, recovery: Bool = false) { self.store = store; self.recovery = recovery; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(store:recovery:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = recovery ? "Local recovery copy" : "Saved sessions"
        tableView.accessibilityIdentifier = "sessionList"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "session")
        if recovery {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Remove copy", primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                let alert = UIAlertController(title: "Remove this recovery copy?", message: "This permanently removes the local backup you're reviewing. Your current workouts and cloud history stay unchanged.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Keep copy", style: .cancel))
                alert.addAction(UIAlertAction(title: "Remove recovery copy", style: .destructive) { [weak self] _ in
                    guard let self else { return }
                    if self.store.removeRecoveryCopy() { self.navigationController?.popToRootViewController(animated: true) }
                }); self.present(alert, animated: true)
            })
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observer = store.observe { [weak self] in self?.tableView.reloadData() }; tableView.reloadData()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let observer { store.removeObserver(observer) }; observer = nil
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? (recovery ? "Read-only saved copy" : "Workouts and unfinished sessions") : "Recoverable discarded drafts"
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 && sections[0].isEmpty { return "Your saved sessions will appear here." }
        return section == 1 && !sections[1].isEmpty ? "Entered values stay preserved. A draft can only be restored if its date is available." : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "session", for: indexPath)
        let session = sections[indexPath.section][indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = session.date
        config.secondaryText = "\(session.discarded ? "Discarded draft" : session.stage.capitalized) · \(session.doneCount) of \(session.totalCount) sets"
        cell.contentConfiguration = config; cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "session-\(session.id)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let session = sections[indexPath.section][indexPath.row]
        if session.discarded && !recovery {
            let alert = UIAlertController(title: "Restore draft from \(session.date)?", message: "Its original date and entered values will be kept.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Restore draft", style: .default) { [weak self] _ in
                guard let self else { return }
                if !self.store.edit({ try $0.restoreDraft(session.id) }) {
                    let error = UIAlertController(title: "Draft retained", message: self.store.message, preferredStyle: .alert)
                    error.addAction(UIAlertAction(title: "OK", style: .default)); self.present(error, animated: true)
                }
            }); present(alert, animated: true)
        } else {
            if !recovery && !session.isCompleted, let profile = store.account?.profile {
                guard store.edit(autosync: false, {
                    try $0.select(session.id); _ = try $0.start(profile: profile)
                }) else { return }
            }
            navigationController?.pushViewController(WorkoutViewController(store: store, sessionID: session.id, recovery: recovery ? document : nil), animated: true)
        }
    }
}
