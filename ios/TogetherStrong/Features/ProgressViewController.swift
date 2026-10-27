import UIKit

@MainActor
final class ProgressViewController: UIViewController {
    private let store: WorkoutStore
    private let content = UIStackView()
    private var observer: UUID?
    private var notifications: [NSObjectProtocol] = []
    private var exerciseID: String
    private var selectedRecord: String?
    private var selectedWeek: String?
    private let recordDetail = UILabel()
    private let weekDetail = UILabel()
    private let openRecord = UIButton(type: .system)

    init(store: WorkoutStore) {
        self.store = store; exerciseID = Exercise.routine(store.account?.profile ?? .david)[0].id
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Your progress"; view.backgroundColor = .systemGroupedBackground
        view.tintColor = navigationController?.navigationBar.tintColor
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.accessibilityIdentifier = "progressScroll"
        content.axis = .vertical; content.spacing = 18; content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28), content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
        openRecord.configuration = .tinted(); openRecord.configuration?.title = "View selected workout"; openRecord.accessibilityIdentifier = "progressOpenWorkout"
        openRecord.addAction(UIAction { [weak self] _ in
            guard let self, let id = self.selectedRecord, self.store.record?.local.session(id)?.isCompleted == true else { return }
            self.navigationController?.pushViewController(WorkoutViewController(store: self.store, sessionID: id), animated: true)
        }, for: .touchUpInside)
        render()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observer = store.observe { [weak self] in self?.render() }
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification, .NSSystemTimeZoneDidChange, UIContentSizeCategory.didChangeNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.render() } })
        }
        render()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let observer { store.removeObserver(observer) }; observer = nil
        notifications.forEach(NotificationCenter.default.removeObserver); notifications = []
    }
    private func label(_ text: String, style: UIFont.TextStyle = .body, id: String? = nil) -> UILabel {
        let label = UILabel(); label.text = text; label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: style); label.adjustsFontForContentSizeCategory = true; label.accessibilityIdentifier = id
        if style == .title2 { label.accessibilityTraits.insert(.header) }
        return label
    }
    private func detail(_ view: UILabel, _ text: String, id: String) {
        view.text = text; view.numberOfLines = 0; view.font = .preferredFont(forTextStyle: .body); view.adjustsFontForContentSizeCategory = true; view.accessibilityIdentifier = id
    }
    private func render() {
        guard isViewLoaded else { return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let document = store.record?.local, let account = store.account else { return }
        let progress = WorkoutProgress(document: document)
        content.addArrangedSubview(label(store.progressStatus, style: .callout, id: "progressSyncStatus"))
        content.addArrangedSubview(label("\(progress.completed.count) workouts completed\n\(progress.totalSets) completed sets\n\(progress.thisWeek)/3 sessions this week", style: .title2, id: "progressSummary"))
        content.addArrangedSubview(label("Only completed workouts count. Weeks run Monday to Sunday in your phone's time zone.", style: .footnote))
        content.addArrangedSubview(label("Weekly consistency", style: .title2))
        let weekly = progress.weekly.map { WorkoutChartEntry(id: $0.date, date: $0.date, value: Double($0.count), detail: "Week beginning this date") }
        let currentWeek = progress.weekly.first { $0.date == selectedWeek } ?? progress.weekly.last!
        selectedWeek = currentWeek.date
        content.addArrangedSubview(WorkoutBarChartView(entries: weekly, unit: "workouts", selectedID: selectedWeek, id: "weeklyChart") { [weak self] id in
            guard let self, let week = progress.weekly.first(where: { $0.date == id }) else { return }
            self.selectedWeek = id; self.detail(self.weekDetail, "Week of \(WorkoutDate.display(id)): \(week.count) completed workouts", id: "weeklyDetail")
        })
        detail(weekDetail, "Week of \(WorkoutDate.display(currentWeek.date)): \(currentWeek.count) completed workouts", id: "weeklyDetail"); content.addArrangedSubview(weekDetail)
        content.addArrangedSubview(label("Exercise progress", style: .title2))
        let exercises = Exercise.routine(account.profile)
        let exercise = exercises.first { $0.id == exerciseID } ?? exercises[0]
        let picker = UIButton(type: .system); picker.configuration = .tinted(); picker.configuration?.title = exercise.name; picker.configuration?.image = UIImage(systemName: "chevron.down"); picker.configuration?.imagePadding = 8
        picker.titleLabel?.numberOfLines = 0; picker.titleLabel?.adjustsFontForContentSizeCategory = true; picker.accessibilityIdentifier = "progressExercise"
        picker.menu = UIMenu(children: exercises.map { item in UIAction(title: item.name, state: exerciseID == item.id ? .on : .off) { [weak self] _ in
            self?.exerciseID = item.id; self?.selectedRecord = nil; self?.render()
        } }); picker.showsMenuAsPrimaryAction = true; content.addArrangedSubview(picker)
        let records = progress.records(for: exercise), unit = exercise.bodyweight ? "reps per side" : "kg total"
        content.addArrangedSubview(label("Best completed set per workout. Highest load, then reps to break ties. Bodyweight uses highest reps per side. Dates are original workout dates.", style: .footnote))
        if records.isEmpty {
            selectedRecord = nil
            content.addArrangedSubview(label("No completed sets for this exercise yet. Finish a workout to start its chart.", id: "progressEmpty"))
        } else {
            let visible = Array(records.suffix(12))
            let selected = visible.first { $0.sessionID == selectedRecord } ?? visible.last!
            selectedRecord = selected.sessionID
            content.addArrangedSubview(label("Last \(visible.count) recorded workouts · swipe the chart to compare", style: .caption1))
            content.addArrangedSubview(WorkoutBarChartView(entries: visible.map { WorkoutChartEntry(id: $0.sessionID, date: $0.date, value: $0.value, detail: "\($0.reps) reps\(exercise.side ? " per side" : "")") }, unit: unit, selectedID: selectedRecord, id: "exerciseChart") { [weak self] id in
                guard let self, let record = visible.first(where: { $0.sessionID == id }) else { return }
                self.selectedRecord = id; self.show(record, exercise: exercise)
            })
            show(selected, exercise: exercise); content.addArrangedSubview(recordDetail); content.addArrangedSubview(openRecord)
        }
        content.addArrangedSubview(label("Pending changes saved on this iPhone are included. Unfinished and discarded sessions stay out of progress totals.", style: .footnote))
    }
    private func show(_ record: ExerciseRecord, exercise: Exercise) {
        let unit = exercise.bodyweight ? "reps per side" : "kg total"
        detail(recordDetail, "\(WorkoutDate.display(record.date))\n\(record.value.formatted()) \(unit) · \(record.reps) reps\(exercise.side ? " per side" : "")", id: "exerciseRecordDetail")
    }
}
