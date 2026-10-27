import UIKit

@MainActor
final class SessionListViewController: UITableViewController, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
    private let store: WorkoutStore
    private let recovery: Bool
    private var observer: UUID?
    private var document: WorkoutDocument? { recovery ? store.record?.recoveryCopy : store.record?.local }
    private var sections: [[WorkoutSession]] = [[], []]
    private var progress: WorkoutProgress?
    private var selectedDay: String?
    private let calendarView = UICalendarView()
    private let header = UIStackView()
    private let filters = UISegmentedControl(items: ["All", "Completed", "Unfinished"])
    private let status = UILabel()
    private let dayLabel = UILabel()
    private var notifications: [NSObjectProtocol] = []
    private var decoratedDays: Set<String> = []
    init(store: WorkoutStore, recovery: Bool = false) { self.store = store; self.recovery = recovery; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(store:recovery:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = recovery ? "Local recovery copy" : "History & calendar"
        view.tintColor = navigationController?.navigationBar.tintColor
        tableView.accessibilityIdentifier = "sessionList"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "session")
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 84
        if !recovery { configureCalendar() }
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
        observer = store.observe { [weak self] in self?.reload() }
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification, .NSSystemTimeZoneDidChange] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.reload() } })
        }
        reload()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let observer { store.removeObserver(observer) }; observer = nil
        notifications.forEach(NotificationCenter.default.removeObserver); notifications = []
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !recovery else { return }
        let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if abs(header.frame.height-size.height) > 0.5 || header.frame.width != tableView.bounds.width {
            header.frame.size = size; tableView.tableHeaderView = header
        }
    }
    private func configureCalendar() {
        header.axis = .vertical; header.spacing = 12; header.isLayoutMarginsRelativeArrangement = true; header.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 20, trailing: 16)
        for label in [status, dayLabel] { label.font = .preferredFont(forTextStyle: .callout); label.adjustsFontForContentSizeCategory = true; label.numberOfLines = 0 }
        status.accessibilityIdentifier = "historySyncStatus"; dayLabel.accessibilityIdentifier = "historyDay"
        header.addArrangedSubview(status)
        var calendar = WorkoutDate.calendar; calendar.firstWeekday = 2
        calendarView.calendar = calendar; calendarView.delegate = self; calendarView.fontDesign = .rounded; calendarView.accessibilityIdentifier = "historyCalendar"
        calendarView.selectionBehavior = UICalendarSelectionSingleDate(delegate: self)
        header.addArrangedSubview(calendarView)
        let legend = UILabel(); legend.text = "✓ Completed workout · orange dot: unfinished\nCompleted workouts appear on the day you finished. Drafts keep their original date."
        legend.font = .preferredFont(forTextStyle: .footnote); legend.adjustsFontForContentSizeCategory = true; legend.numberOfLines = 0; header.addArrangedSubview(legend)
        let actions = UIStackView(); actions.axis = .horizontal; actions.distribution = .fillEqually; actions.spacing = 12
        for (title, id) in [("Today", "historyToday"), ("Latest", "historyLatest"), ("All dates", "historyAllDates")] {
            let button = UIButton(type: .system); button.configuration = .tinted(); button.configuration?.title = title; button.accessibilityIdentifier = id; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.selectedDay = id == "historyToday" ? WorkoutDate.day(Date()) : id == "historyLatest" ? self.progress?.history.first?.day() : nil
                let components = self.selectedDay.flatMap { WorkoutDate.date($0) }.map { self.calendarView.calendar.dateComponents([.year,.month,.day], from: $0) }
                (self.calendarView.selectionBehavior as? UICalendarSelectionSingleDate)?.setSelected(components, animated: false)
                if let components { self.calendarView.setVisibleDateComponents(components, animated: true) }
                self.reload()
            }, for: .touchUpInside); actions.addArrangedSubview(button)
        }
        header.addArrangedSubview(actions)
        filters.accessibilityIdentifier = "historyFilter"; filters.selectedSegmentIndex = 0
        filters.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
        header.addArrangedSubview(filters); header.addArrangedSubview(dayLabel)
        tableView.tableHeaderView = header
        refreshControl = UIRefreshControl(); refreshControl?.addAction(UIAction { [weak self] _ in
            guard let self else { return }; Task { await self.store.refresh(); self.refreshControl?.endRefreshing() }
        }, for: .valueChanged)
    }
    private func reload() {
        guard isViewLoaded else { return }
        progress = document.map { WorkoutProgress(document: $0) }
        var sessions = progress?.history ?? []
        if let selectedDay { sessions = progress?.sessions(on: selectedDay) ?? [] }
        if filters.selectedSegmentIndex == 1 { sessions = sessions.filter(\.isCompleted) }
        if filters.selectedSegmentIndex == 2 { sessions = sessions.filter { !$0.isCompleted } }
        let discarded = document?.sessions.filter(\.discarded).sorted { $0.date > $1.date } ?? []
        sections = [sessions, recovery || (selectedDay == nil && filters.selectedSegmentIndex == 0) ? discarded : []]
        if !recovery {
            status.text = store.progressStatus
            dayLabel.text = "\(selectedDay.map { WorkoutDate.display($0) } ?? "All dates") · \(sessions.count) \(sessions.count == 1 ? "session" : "sessions")"
            var calendar = WorkoutDate.calendar; calendar.firstWeekday = 2
            if calendarView.calendar != calendar { calendarView.calendar = calendar }
            let days = progress?.days ?? []
            calendarView.reloadDecorations(forDateComponents: Array(days.union(decoratedDays)).compactMap { WorkoutDate.date($0).map { calendarView.calendar.dateComponents([.year,.month,.day], from: $0) } }, animated: false)
            decoratedDays = days
        }
        tableView.reloadData(); view.setNeedsLayout()
    }
    func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        guard let date = calendarView.calendar.date(from: dateComponents) else { return nil }
        let sessions = progress?.sessions(on: WorkoutDate.day(date, calendar: calendarView.calendar)) ?? []
        if sessions.contains(where: \.isCompleted) { return .image(UIImage(systemName: "checkmark.circle.fill"), color: view.tintColor, size: .small) }
        return sessions.isEmpty ? nil : .default(color: .systemOrange, size: .small)
    }
    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
        selectedDay = dateComponents.flatMap { calendarView.calendar.date(from: $0) }.map { WorkoutDate.day($0, calendar: calendarView.calendar) }
        reload()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? (recovery ? "Read-only saved copy" : "Your sessions") : (sections[1].isEmpty ? nil : "Recoverable discarded drafts")
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 && sections[0].isEmpty { return "No sessions match this view. Choose All dates or another filter to review your history." }
        if section == 0 && !recovery { return "Tap an unfinished session to resume it with its original date. Completed workouts open for review." }
        return section == 1 && !sections[1].isEmpty ? "Entered values stay preserved. A draft can only be restored if its date is available." : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "session", for: indexPath)
        let session = sections[indexPath.section][indexPath.row]
        var config = cell.defaultContentConfiguration()
        let day = session.day()
        config.text = WorkoutDate.display(day)
        config.secondaryText = "\(session.discarded ? "Discarded draft" : session.stage.capitalized) · \(session.doneCount) of \(session.totalCount) sets\(day == session.date ? "" : "\nStarted \(WorkoutDate.display(session.date))")"
        config.secondaryTextProperties.numberOfLines = 0
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
