import UIKit
import SafariServices

@MainActor
final class ConnectionViewController: UIViewController, UITextFieldDelegate {
    private let store: WorkoutStore
    private let content = UIStackView()
    private let email = UITextField()
    private let password = UITextField()
    private var notification: NSObjectProtocol?
    private let green = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.72, green: 0.86, blue: 0.62, alpha: 1)
        : UIColor(red: 0.26, green: 0.35, blue: 0.21, alpha: 1)
    }

    init(store: WorkoutStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemBackground : UIColor(red: 0.973, green: 0.973, blue: 0.961, alpha: 1)
        }
        navigationItem.title = "Together Strong"
        navigationController?.navigationBar.tintColor = green
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical; content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
        ])
        configureField(email, placeholder: "Email address", id: "email")
        email.keyboardType = .emailAddress; email.textContentType = .username
        email.autocapitalizationType = .none; email.autocorrectionType = .no
        email.returnKeyType = .next
        configureField(password, placeholder: "Password", id: "password")
        password.isSecureTextEntry = true; password.textContentType = .password
        password.returnKeyType = .go
        store.onChange = { [weak self] in
            guard let self else { return }
            if self.store.account == nil {
                self.navigationController?.dismiss(animated: false)
                self.navigationController?.popToRootViewController(animated: false)
            }
            self.render()
        }
        render()
        Task { await store.restore() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        notification = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.store.account != nil else { return }
                    await self.store.refresh()
                }
            }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let notification { NotificationCenter.default.removeObserver(notification) }
        notification = nil
    }

    private func configureField(_ field: UITextField, placeholder: String, id: String) {
        field.placeholder = placeholder; field.accessibilityLabel = placeholder; field.accessibilityIdentifier = id
        field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .roundedRect; field.delegate = self
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Done", primaryAction: UIAction { [weak self] _ in self?.view.endEditing(true) })]
        field.inputAccessoryView = toolbar
    }

    private func label(_ text: String, style: UIFont.TextStyle = .body, muted: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = muted ? .secondaryLabel : .label
        return label
    }

    private func button(_ title: String, id: String, primary: Bool = false, action: @escaping () -> Void) -> UIButton {
        var config = primary ? UIButton.Configuration.filled() : .tinted()
        config.title = title; config.cornerStyle = .large
        config.baseBackgroundColor = green
        config.baseForegroundColor = primary ? .systemBackground : green
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.accessibilityIdentifier = id; button.isEnabled = !store.busy
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        return button
    }

    private func render() {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        let symbol = UIImageView(image: UIImage(systemName: "figure.strengthtraining.traditional"))
        symbol.tintColor = green; symbol.contentMode = .scaleAspectFit
        symbol.heightAnchor.constraint(equalToConstant: 56).isActive = true
        symbol.accessibilityElementsHidden = true
        content.addArrangedSubview(symbol)
        content.addArrangedSubview(label("YOUR OWN LITTLE CORNER", style: .caption1, muted: true))
        let heading = label(store.account.map { "Welcome back, \($0.profile.rawValue)." } ?? "A little stronger.\nTogether.", style: .largeTitle)
        heading.accessibilityTraits.insert(.header)
        heading.accessibilityIdentifier = "screenHeading"
        content.addArrangedSubview(heading)
        if let message = store.message {
            let status = label(message, style: .callout)
            status.accessibilityIdentifier = "status"
            content.addArrangedSubview(status)
        }
        if store.busy {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating(); spinner.accessibilityLabel = "Connecting"
            content.addArrangedSubview(spinner)
        }
        if let account = store.account { dashboard(account) }
        else { signInForm() }
    }

    private func signInForm() {
        content.addArrangedSubview(label("Sign in to your private training space. Your workouts stay yours, on every device.", muted: true))
        content.addArrangedSubview(label("Email address", style: .subheadline))
        content.addArrangedSubview(email)
        content.addArrangedSubview(label("Password", style: .subheadline))
        content.addArrangedSubview(password)
        email.isEnabled = !store.busy; password.isEnabled = !store.busy
        content.addArrangedSubview(button("Sign in", id: "signIn", primary: true) { [weak self] in self?.submit() })
        content.addArrangedSubview(button("Private setup or password reset", id: "accountHelp") { [weak self] in
            guard let self else { return }
            let browser = SFSafariViewController(url: self.store.api.origin.url)
            self.present(browser, animated: true)
        })
        content.addArrangedSubview(label("Use the website to verify your invited email or reset your password, then return here to sign in.", style: .footnote, muted: true))
    }

    private func dashboard(_ account: Account) {
        password.text = nil
        content.addArrangedSubview(label("Your workouts, kept together across your devices.", muted: true))
        if let record = store.record {
            let session = record.local.activeSession()
            content.addArrangedSubview(button(session == nil ? "Start workout" : session?.isCompleted == true ? "Review workout" : "Resume workout", id: "openWorkout", primary: true) { [weak self] in
                guard let self, self.navigationController?.topViewController === self else { return }
                var id: String?
                if self.store.edit(autosync: false, { id = try $0.start(profile: account.profile) }), let id {
                    self.navigationController?.pushViewController(WorkoutViewController(store: self.store, sessionID: id), animated: true)
                }
            })
            content.addArrangedSubview(button("Saved sessions", id: "savedSessions") { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(SessionListViewController(store: self.store), animated: true)
            })
            if record.recoveryCopy != nil {
                content.addArrangedSubview(button("View local recovery copy", id: "recoveryCopy") { [weak self] in
                    guard let self else { return }
                    self.navigationController?.pushViewController(SessionListViewController(store: self.store, recovery: true), animated: true)
                })
            }
            let summary = label("\(record.local.completedSessionCount) workouts completed\n\(record.local.sessionCount) sessions saved", style: .title2)
            summary.accessibilityIdentifier = "workoutSummary"
            content.addArrangedSubview(summary)
            let syncState = label(store.dirty ? "Saved on this iPhone · waiting to sync" : "Synced securely", style: .subheadline, muted: true)
            syncState.accessibilityIdentifier = "syncState"
            content.addArrangedSubview(syncState)
            content.addArrangedSubview(label("Beginner training", style: .headline))
            content.addArrangedSubview(label("Sets per exercise for your first two weeks. Changing this preference keeps your existing sessions intact.", style: .callout, muted: true))
            let sets = UISegmentedControl(items: ["1 set", "2 sets"])
            sets.selectedSegmentIndex = record.local.rampSets - 1
            sets.accessibilityIdentifier = "rampSets"
            sets.isEnabled = !store.busy
            sets.addAction(UIAction { [weak self, weak sets] _ in
                guard let self, let sets else { return }
                self.store.changeRampSets(sets.selectedSegmentIndex + 1)
            }, for: .valueChanged)
            content.addArrangedSubview(sets)
            let sync = button("Sync changes", id: "sync", primary: true) { [weak self] in
                guard let self else { return }; Task { await self.store.sync() }
            }
            sync.isEnabled = !store.busy && store.dirty && store.conflict == nil
            content.addArrangedSubview(sync)
        }
        if store.conflict != nil {
            content.addArrangedSubview(button("Review changed cloud copy", id: "resolveConflict") { [weak self] in
                self?.confirmCloudCopy()
            })
        }
        content.addArrangedSubview(button("Refresh workouts", id: "refresh") { [weak self] in
            guard let self else { return }; Task { await self.store.refresh() }
        })
        content.addArrangedSubview(button("Sign out", id: "signOut") { [weak self] in self?.confirmSignOut() })
        content.addArrangedSubview(label("Signed in as \(account.profile.rawValue).", style: .footnote, muted: true))
    }

    private func submit() {
        guard let email = email.text, email.contains("@"), let password = password.text, !password.isEmpty else {
            let alert = UIAlertController(title: "Enter your sign-in details", message: "Use your invited email address and password.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true); return
        }
        view.endEditing(true)
        Task { await store.signIn(email: email, password: password) }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === email { password.becomeFirstResponder() } else { submit() }
        return true
    }

    private func confirmCloudCopy() {
        guard let local = store.record?.local, let remote = store.conflict?.data else { return }
        let alert = UIAlertController(title: "Workout changed on another device",
            message: "This iPhone has \(local.sessionCount) sessions and \(local.completedSessionCount) completed workouts. The cloud has \(remote.sessionCount) sessions and \(remote.completedSessionCount) completed workouts. Using the cloud copy keeps this iPhone's changes in a separate recovery copy for review.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep changes on this iPhone", style: .cancel))
        alert.addAction(UIAlertAction(title: "Use cloud and keep recovery copy", style: .default) { [weak self] _ in self?.store.useCloudCopy() })
        present(alert, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(title: "Sign out?", message: store.dirty
            ? "Your workouts have unsynced changes. Sync first, or explicitly discard those changes and remove this account's local workout and recovery copies."
            : "This removes your sign-in and this account's workout and recovery copies from this iPhone. Your cloud history stays saved.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if store.dirty {
            alert.addAction(UIAlertAction(title: "Sync first", style: .default) { [weak self] _ in
                guard let self else { return }; Task { await self.store.sync() }
            })
        }
        alert.addAction(UIAlertAction(title: store.dirty ? "Discard changes and sign out" : "Sign out", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.store.signOut()
                if self.store.account != nil { self.offerLocalSignOut() }
            }
        })
        present(alert, animated: true)
    }

    private func offerLocalSignOut() {
        let alert = UIAlertController(title: "Could not finish signing out", message: "Retry when connected, or remove the sign-in and local workout copy from this iPhone now. A local sign-out cannot revoke the server session.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Stay signed in", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign out on this iPhone", style: .destructive) { [weak self] _ in
            guard let self else { return }; Task { await self.store.signOut(localOnly: true) }
        })
        present(alert, animated: true)
    }
}
