import UIKit

@MainActor
final class WorkoutViewController: UIViewController {
    private let store: WorkoutStore
    private let sessionID: String
    private let recovery: WorkoutDocument?
    private var observer: UUID?
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let status = UILabel()
    private let progress = UILabel()
    private let warmupStatus = UILabel()
    private let warmupActions = UIStackView()
    private var warmupExpanded = true
    private var lastWarmup: WarmupState?
    private let changeWarmup = UIButton(type: .system)
    private let exercises = UIStackView()
    private var rows: [String: [SetEntryView]] = [:]
    private var exerciseButtons: [UIButton] = []
    private var expanded: String?
    private var layoutKey = ""
    private let save = UIButton(type: .system)
    private let pause = UIButton(type: .system)
    private let finish = UIButton(type: .system)
    private let reopen = UIButton(type: .system)
    private let discard = UIButton(type: .system)
    private var document: WorkoutDocument? { recovery ?? store.record?.local }
    private var session: WorkoutSession? { document?.session(sessionID) }
    private var readOnly: Bool { recovery != nil || session?.isCompleted == true }

    init(store: WorkoutStore, sessionID: String, recovery: WorkoutDocument? = nil) {
        self.store = store; self.sessionID = sessionID; self.recovery = recovery
        self.expanded = Exercise.routine(store.account?.profile ?? .david).first?.id
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:sessionID:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = recovery == nil ? "Your workout" : "Recovery copy"
        view.backgroundColor = .systemGroupedBackground
        view.tintColor = navigationController?.navigationBar.tintColor
        if recovery == nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Rest", primaryAction: UIAction { [weak self] _ in self?.showRest() })
            navigationItem.rightBarButtonItem?.accessibilityIdentifier = "openRestTimer"
        }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        content.axis = .vertical; content.spacing = 18; content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
        configure(progress, style: .title2); progress.accessibilityIdentifier = "sessionProgress"
        configure(status, style: .callout); status.accessibilityIdentifier = "workoutSaveStatus"
        content.addArrangedSubview(progress); content.addArrangedSubview(status)
        configure(warmupStatus, style: .headline); content.addArrangedSubview(warmupStatus)
        warmupActions.axis = .vertical; warmupActions.spacing = 8
        for (title, state) in [("Start warm-up", WarmupState.underway), ("I've warmed up", .done), ("Skip for now", .skipped)] {
            warmupActions.addArrangedSubview(action(title, id: "warmup-\(state.rawValue)") { [weak self] in
                guard let self else { return }
                self.store.edit { try $0.setWarmup(self.sessionID, state: state) }
            })
        }
        content.addArrangedSubview(warmupActions)
        setup(changeWarmup, title: "Change warm-up choice", id: "changeWarmup") { [weak self] in
            guard let self, !self.readOnly else { return }
            self.warmupExpanded.toggle(); self.update()
        }
        content.addArrangedSubview(changeWarmup)
        let conventions = UILabel(); configure(conventions, style: .footnote)
        conventions.text = "Log total kg held. Add both dumbbells when using two. For one-sided moves, complete both sides and log the lower reps per side. Warm up, secure collars, leave 2–3 good reps in reserve, and stop with pain."
        conventions.textColor = .secondaryLabel; content.addArrangedSubview(conventions)
        exercises.axis = .vertical; exercises.spacing = 12; content.addArrangedSubview(exercises)
        setup(save, title: "Save progress", id: "saveProgress") { [weak self] in
            guard let self else { return }; self.view.endEditing(true); Task { await self.store.sync() }
        }
        setup(pause, title: "Save & pause", id: "pauseWorkout") { [weak self] in
            guard let self else { return }; self.view.endEditing(true)
            if self.store.edit({ try $0.pause(self.sessionID) }) {
                self.navigationController?.popToRootViewController(animated: true)
                Task { await self.store.sync() }
            }
        }
        setup(finish, title: "Finish workout", id: "finishWorkout") { [weak self] in self?.confirmFinish() }
        setup(reopen, title: "Undo completion", id: "reopenWorkout") { [weak self] in
            guard let self else { return }
            self.store.edit { try $0.reopen(self.sessionID) }
        }
        setup(discard, title: "Discard empty draft", id: "discardDraft") { [weak self] in self?.confirmDiscard() }
        for button in [save, pause, finish, reopen, discard] { content.addArrangedSubview(button) }
        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observer = store.observe { [weak self] in self?.update() }
        update()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let observer { store.removeObserver(observer) }; observer = nil
    }

    private func configure(_ label: UILabel, style: UIFont.TextStyle) {
        label.font = .preferredFont(forTextStyle: style); label.adjustsFontForContentSizeCategory = true; label.numberOfLines = 0
    }
    private func setup(_ button: UIButton, title: String, id: String, action: @escaping () -> Void) {
        var config = UIButton.Configuration.tinted(); config.title = title; config.cornerStyle = .large
        config.contentInsets = .init(top: 13, leading: 16, bottom: 13, trailing: 16)
        button.configuration = config; button.accessibilityIdentifier = id
        button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    private func action(_ title: String, id: String, callback: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system); setup(button, title: title, id: id, action: callback); return button
    }

    private func update() {
        guard isViewLoaded, store.account != nil, let session, let document else { return }
        progress.text = "\(session.date) · \(session.stage.capitalized)\n\(session.doneCount) of \(session.totalCount) sets completed · Week \(document.weekNumber())"
        status.text = recovery != nil ? "Read-only recovery copy. Your cloud workouts are unchanged." : store.busy ? "Syncing. Your edits are saved on this iPhone." : (store.message ?? (store.dirty ? "Saved on this iPhone. Waiting to sync." : "Synced securely."))
        warmupStatus.text = [WarmupState.pending: "A 5-minute warm-up is recommended", .underway: "Warm-up in progress. Log whenever you're ready.", .done: "Warm-up complete", .skipped: "Warm-up skipped for now"][session.warmup]
        if lastWarmup != session.warmup {
            lastWarmup = session.warmup; warmupExpanded = session.warmup == .pending || session.warmup == .underway
        }
        warmupActions.isHidden = readOnly || !warmupExpanded
        changeWarmup.isHidden = readOnly
        let nextKey = "\(session.id)|\(readOnly)|\(expanded ?? "")|\(session.totalCount)"
        if nextKey != layoutKey {
            layoutKey = nextKey; buildExercises(session: session, document: document)
        }
        for (id, entries) in rows {
            for (index, row) in entries.enumerated() {
                let sets = session.sets(id)
                if sets.indices.contains(index) { row.update(sets[index], readOnly: readOnly) }
            }
        }
        save.isEnabled = !store.busy && recovery == nil
        pause.isHidden = readOnly; finish.isHidden = readOnly
        finish.isEnabled = session.doneCount > 0
        reopen.isHidden = recovery != nil || !session.isCompleted || session.day() != WorkoutDate.day(Date())
        discard.isHidden = readOnly || session.doneCount > 0
        save.isHidden = recovery != nil
        navigationItem.rightBarButtonItem?.isEnabled = !readOnly
    }

    private func buildExercises(session: WorkoutSession, document: WorkoutDocument) {
        exercises.arrangedSubviews.forEach { exercises.removeArrangedSubview($0); $0.removeFromSuperview() }
        rows = [:]; exerciseButtons = []
        for (number, exercise) in Exercise.routine(store.account?.profile ?? .david).enumerated() {
            let card = UIStackView(); card.axis = .vertical; card.spacing = 12
            card.backgroundColor = .secondarySystemGroupedBackground; card.layer.cornerRadius = 16
            card.isLayoutMarginsRelativeArrangement = true; card.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
            let count = session.sets(exercise.id).count
            let header = action("\(number + 1). \(exercise.name)\n\(count) \(count == 1 ? "set" : "sets") × \(exercise.reps) reps\(exercise.side ? " / side" : "") · \(exercise.rest)s rest", id: "exercise-\(exercise.id)") { [weak self] in
                guard let self else { return }; self.view.endEditing(true)
                self.expanded = self.expanded == exercise.id ? nil : exercise.id; self.update()
            }
            header.contentHorizontalAlignment = .leading; exerciseButtons.append(header); card.addArrangedSubview(header)
            if expanded == exercise.id {
                card.addArrangedSubview(action("Movement guide · \(exercise.cue)", id: "guide-\(exercise.id)") { [weak self] in
                    guard let self else { return }; self.view.endEditing(true)
                    let navigation = UINavigationController(rootViewController: ExerciseGuideViewController(exercise: exercise))
                    navigation.navigationBar.tintColor = self.view.tintColor
                    navigation.sheetPresentationController?.detents = [.large()]
                    self.present(navigation, animated: true)
                })
                let previous = document.sessions.last { $0.id != session.id && !$0.discarded && $0.isCompleted }
                var entries: [SetEntryView] = []
                for (index, set) in session.sets(exercise.id).enumerated() {
                    let row = SetEntryView(exercise: exercise, index: index, value: set)
                    row.onEdit = { [weak self] reps, kg in
                        guard let self else { return false }
                        return self.store.edit { try $0.editSet(self.sessionID, exercise: exercise.id, index: index, reps: reps, kg: kg) }
                    }
                    row.onComplete = { [weak self] in
                        guard let self else { return }
                        if !self.store.edit({ try $0.editSet(self.sessionID, exercise: exercise.id, index: index, toggle: true) }) {
                            self.alert(title: "Check this set", message: self.store.message ?? "Enter reps and total kg first.")
                        }
                    }
                    let previousSets = previous?.sets(exercise.id) ?? []
                    if previousSets.indices.contains(index), previousSets[index].done {
                        row.previousReference = "Previously: \(previousSets[index].reps) reps\(exercise.side ? " / side" : "")\(exercise.bodyweight ? " · bodyweight" : " · \(previousSets[index].kg) kg total")"
                    }
                    row.update(set, readOnly: readOnly); card.addArrangedSubview(row); entries.append(row)
                }
                rows[exercise.id] = entries
                if !readOnly {
                    card.addArrangedSubview(action("Start \(exercise.rest)s rest", id: "rest-\(exercise.id)") { [weak self] in
                        guard let self else { return }; self.view.endEditing(true)
                        if self.store.startRest(sessionID: self.sessionID, exercise: exercise) { self.showRest() }
                        else { self.alert(title: "Timer unavailable", message: self.store.message ?? "Resume this session before starting rest.") }
                    })
                }
            }
            exercises.addArrangedSubview(card)
        }
    }

    private func alert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
    private func showRest() {
        view.endEditing(true)
        let navigation = UINavigationController(rootViewController: RestTimerViewController(store: store))
        navigation.navigationBar.tintColor = view.tintColor
        navigation.sheetPresentationController?.detents = [.large()]
        present(navigation, animated: true)
    }
    private func confirmFinish() {
        view.endEditing(true)
        guard let session, session.doneCount > 0 else { return }
        let alert = UIAlertController(title: "Finish this workout?", message: "Save \(session.doneCount) of \(session.totalCount) completed sets. Remaining sets stay unfinished. Your workout is saved on this iPhone before syncing.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep training", style: .cancel))
        alert.addAction(UIAlertAction(title: "Finish and save", style: .default) { [weak self] _ in
            guard let self else { return }
            if self.store.edit({ try $0.finish(self.sessionID) }) { Task { await self.store.sync() } }
        })
        present(alert, animated: true)
    }
    private func confirmDiscard() {
        view.endEditing(true)
        let alert = UIAlertController(title: "Discard this empty draft?", message: "Its entered values stay recoverable in Saved sessions. No completed workout will be recorded.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep draft", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard draft", style: .destructive) { [weak self] _ in
            guard let self else { return }
            if self.store.edit({ try $0.discard(self.sessionID) }) { self.navigationController?.popToRootViewController(animated: true) }
        })
        present(alert, animated: true)
    }
}

@MainActor
private final class SetEntryView: UIStackView, UITextFieldDelegate {
    let reps = UITextField()
    let kg = UITextField()
    let previous = UILabel()
    var previousReference: String? { didSet { previous.text = previousReference } }
    private let done = UIButton(type: .system)
    private let bodyweight: Bool
    private let exerciseName: String
    private var persisted: SetEntry
    var onEdit: ((String?, String?) -> Bool)?
    var onComplete: (() -> Void)?

    init(exercise: Exercise, index: Int, value: SetEntry) {
        bodyweight = exercise.bodyweight; exerciseName = exercise.name; persisted = value
        super.init(frame: .zero)
        axis = .vertical; spacing = 8
        let caption = UILabel(); caption.text = "SET \(index + 1) · REPS\(exercise.side ? " PER SIDE" : "")"
        caption.font = .preferredFont(forTextStyle: .caption1); caption.adjustsFontForContentSizeCategory = true
        addArrangedSubview(caption)
        for (field, name, identifier, type) in [(reps, "reps", "reps-\(exercise.id)-\(index)", UIKeyboardType.numberPad), (kg, "kg total", "kg-\(exercise.id)-\(index)", .decimalPad)] {
            field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
            field.borderStyle = .roundedRect; field.placeholder = name; field.keyboardType = type
            field.accessibilityLabel = "\(exercise.name) set \(index + 1) \(name)"
            field.accessibilityIdentifier = identifier; field.delegate = self
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            field.addAction(UIAction { [weak self, weak field] _ in
                guard let self, let field else { return }
                let canonical = self.canonical(field.text ?? "")
                let accepted = self.onEdit?(field === self.reps ? canonical : nil, field === self.kg ? canonical : nil) ?? false
                if !accepted {
                    field.text = field === self.reps ? self.persisted.reps : self.persisted.kg
                    field.backgroundColor = .systemRed.withAlphaComponent(0.12)
                    self.previous.text = "This edit was not saved. Retry before leaving."
                    UIAccessibility.post(notification: .announcement, argument: "This edit could not be saved. Please retry.")
                }
            }, for: .editingChanged)
            let toolbar = UIToolbar(); toolbar.sizeToFit()
            toolbar.items = [UIBarButtonItem(title: "Next", primaryAction: UIAction { [weak self, weak field] _ in
                guard let self else { return }; if field === self.reps && !self.bodyweight { self.kg.becomeFirstResponder() } else { field?.resignFirstResponder() }
            }), UIBarButtonItem(systemItem: .flexibleSpace), UIBarButtonItem(title: "Done", primaryAction: UIAction { [weak field] _ in field?.resignFirstResponder() })]
            field.inputAccessoryView = toolbar
        }
        addArrangedSubview(reps)
        if bodyweight {
            let label = UILabel(); label.text = "Bodyweight · no kg entry"; label.font = .preferredFont(forTextStyle: .callout); label.adjustsFontForContentSizeCategory = true; addArrangedSubview(label)
        } else {
            let label = UILabel(); label.text = "KG TOTAL"
            label.font = .preferredFont(forTextStyle: .caption1); label.adjustsFontForContentSizeCategory = true
            addArrangedSubview(label); addArrangedSubview(kg)
        }
        var config = UIButton.Configuration.tinted(); config.title = "Complete set"; config.image = UIImage(systemName: "circle")
        config.imagePadding = 8
        done.configuration = config; done.accessibilityIdentifier = "complete-\(exercise.id)-\(index)"
        done.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        done.addAction(UIAction { [weak self] _ in self?.onComplete?() }, for: .touchUpInside)
        addArrangedSubview(done)
        previous.font = .preferredFont(forTextStyle: .footnote); previous.numberOfLines = 0
        previous.adjustsFontForContentSizeCategory = true; previous.textColor = .secondaryLabel; addArrangedSubview(previous)
    }
    required init(coder: NSCoder) { fatalError("Use init(exercise:index:value:)") }
    private func canonical(_ text: String) -> String {
        text.map { character in
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { return String(digit) }
            return String(character)
        }.joined()
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
            .replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "٫", with: ".")
    }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let current = textField.text, let range = Range(range, in: current) else { return false }
        return canonical(current.replacingCharacters(in: range, with: string)).utf16.count <= (textField === reps ? 3 : 6)
    }
    func update(_ value: SetEntry, readOnly: Bool) {
        persisted = value
        reps.backgroundColor = nil; kg.backgroundColor = nil
        previous.text = previousReference
        if !reps.isFirstResponder { reps.text = value.reps }
        if !kg.isFirstResponder { kg.text = value.kg }
        reps.isEnabled = !readOnly; kg.isEnabled = !readOnly; done.isEnabled = !readOnly
        done.isSelected = value.done
        done.configuration?.title = value.done ? "Undo set" : "Complete set"
        done.configuration?.image = UIImage(systemName: value.done ? "checkmark.circle.fill" : "circle")
        done.accessibilityLabel = "\(value.done ? "Undo" : "Complete") \(exerciseName) set"
    }
}
