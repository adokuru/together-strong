import UIKit
import UserNotifications

@MainActor
final class RestTimerViewController: UIViewController {
    private let store: WorkoutStore
    private var observer: UUID?
    private var ticker: Timer?
    private var foreground: NSObjectProtocol?
    private let name = UILabel()
    private let value = UILabel()
    private let state = UILabel()
    private let alertStatus = UILabel()
    private let toggle = UIButton(type:.system)
    private let add = UIButton(type:.system)
    private let reset = UIButton(type:.system)
    private let end = UIButton(type:.system)
    private let alerts = UIButton(type:.system)
    private let presets = UISegmentedControl(items:["60s","90s","120s"])
    private var wasComplete = false
    private var osAlertsAllowed = false

    init(store: WorkoutStore) { self.store = store; super.init(nibName:nil,bundle:nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Rest timer"; view.backgroundColor = .systemGroupedBackground
        view.tintColor = navigationController?.navigationBar.tintColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(title:"Close",primaryAction:UIAction { [weak self] _ in self?.dismiss(animated:true) })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "closeRestTimer"
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor),scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-24),stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-20),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-40),
        ])
        for (label,style) in [(name,UIFont.TextStyle.headline),(state,.body),(alertStatus,.footnote)] {
            label.font = .preferredFont(forTextStyle:style); label.adjustsFontForContentSizeCategory = true; label.numberOfLines = 0
        }
        value.font = UIFontMetrics(forTextStyle:.largeTitle).scaledFont(for:.monospacedDigitSystemFont(ofSize:64,weight:.medium))
        value.adjustsFontForContentSizeCategory = true; value.textAlignment = .center
        value.adjustsFontSizeToFitWidth = true; value.minimumScaleFactor = 0.25
        value.accessibilityIdentifier = "timerValue"; value.accessibilityTraits = .updatesFrequently
        state.accessibilityIdentifier = "timerState"; alertStatus.accessibilityIdentifier = "timerAlertStatus"
        stack.addArrangedSubview(name); stack.addArrangedSubview(value); stack.addArrangedSubview(state)
        configure(toggle,"Pause","timerToggle") { [weak self] in
            guard let self else { return }
            self.change { timer in if timer.running() { timer.pause() } else { timer.resume() } }
        }
        configure(add,"Add 30 seconds","timerAdd30") { [weak self] in self?.change { $0.addThirty() } }
        configure(reset,"Reset","timerReset") { [weak self] in self?.change { $0.reset() } }
        for button in [toggle,add,reset] { stack.addArrangedSubview(button) }
        presets.accessibilityLabel = "Rest duration"; presets.accessibilityIdentifier = "timerPresets"
        presets.addAction(UIAction { [weak self] _ in
            guard let self, [0,1,2].contains(self.presets.selectedSegmentIndex) else { return }
            let duration = [60,90,120][self.presets.selectedSegmentIndex]
            self.change { $0.reset(duration:duration) }
        },for:.valueChanged); stack.addArrangedSubview(presets)
        configure(end,"End rest","endRest") { [weak self] in
            guard let self else { return }
            if self.store.endRest() { self.dismiss(animated:true) } else { self.failed() }
        }; stack.addArrangedSubview(end)
        configure(alerts,"Enable rest alerts","timerAlerts") { [weak self] in
            guard let self else { return }
            if self.store.record?.restAlertsEnabled == true { if !self.store.disableRestAlerts() { self.failed() } }
            else { Task { _ = await self.store.enableRestAlerts(); await self.refreshPermission(); self.render() } }
        }; stack.addArrangedSubview(alerts); stack.addArrangedSubview(alertStatus)
        let settings = UIButton(type:.system)
        configure(settings,"iPhone notification settings","timerSettings") {
            if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }; stack.addArrangedSubview(settings)
        render()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observer = store.observe { [weak self] in self?.render() }
        ticker = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.render() }
        }
        foreground = NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshPermission(); self?.render() }
        }
        Task { await refreshPermission(); render() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); ticker?.invalidate(); ticker = nil
        if let observer { store.removeObserver(observer) }; observer = nil
        if let foreground { NotificationCenter.default.removeObserver(foreground) }; foreground = nil
    }
    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        osAlertsAllowed = [.authorized,.provisional,.ephemeral].contains(settings.authorizationStatus)
    }
    private func configure(_ button: UIButton, _ title: String, _ id: String, _ action: @escaping () -> Void) {
        var config = UIButton.Configuration.tinted(); config.title = title; config.cornerStyle = .large; config.contentInsets = .init(top:13,leading:16,bottom:13,trailing:16)
        button.configuration = config; button.accessibilityIdentifier = id
        button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addAction(UIAction { _ in action() },for:.touchUpInside)
    }
    private func change(_ action: (inout RestTimerState) -> Void) { if !store.changeRest(action) { failed() } }
    private func failed() {
        let alert = UIAlertController(title:"Timer change not saved",message:store.message ?? "Please retry.",preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"OK",style:.default)); present(alert,animated:true)
    }
    private func render() {
        guard isViewLoaded else { return }
        let timer = store.record?.restTimer
        let remaining = timer?.remaining() ?? 0
        value.text = String(format:"%d:%02d",remaining/60,remaining%60)
        name.text = timer.flatMap { t in Exercise.all.first { $0.id == t.exerciseID }?.name } ?? "Choose Start rest beside an exercise."
        state.text = timer == nil ? "No active rest timer" : timer?.complete() == true ? "Rest complete. Ready for your next set when you are." : timer?.running() == true ? "Rest running. Closing this panel keeps it running." : "Rest paused"
        toggle.configuration?.title = timer?.running() == true ? "Pause" : timer?.complete() == true ? "Start again" : "Resume"
        for control in [toggle,add,reset,end] { control.isEnabled = timer != nil && store.canEdit }
        presets.isEnabled = timer != nil && store.canEdit
        presets.selectedSegmentIndex = [60,90,120].firstIndex(of:timer?.duration ?? 0) ?? UISegmentedControl.noSegment
        let enabled = store.record?.restAlertsEnabled == true
        alerts.configuration?.title = enabled ? "Disable rest alerts" : "Enable rest alerts"
        alertStatus.text = enabled && osAlertsAllowed ? "Rest alerts enabled. iPhone settings may silence or delay them." : enabled ? "Rest alerts are off in iPhone Settings. The timer still works." : "Rest alerts are off. The timer still works."
        let completed = timer?.complete() == true
        if completed && !wasComplete { UIAccessibility.post(notification:.announcement,argument:"Rest complete. Ready for your next set when you are.") }
        wasComplete = completed
    }
}
