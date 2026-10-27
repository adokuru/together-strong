import UIKit
import QuartzCore
import SafariServices

@MainActor
final class ExerciseGuideViewController: UIViewController {
    private let exercise: Exercise
    private var info: ExerciseGuideInfo? { ExerciseGuideInfo.all[exercise.id] }
    private let canvas: ExerciseCanvasView
    private var playback = GuidePlayback()
    private let position = UISlider()
    private let play = UIButton(type: .system)
    private let phase = UILabel()
    private let motionNote = UILabel()
    private var displayLink: CADisplayLink?
    private var previousTime: CFTimeInterval?
    private var observations: [NSObjectProtocol] = []

    init(exercise: Exercise) {
        self.exercise = exercise; canvas = ExerciseCanvasView(exerciseID:exercise.id,name:exercise.name)
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(exercise:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = exercise.name; view.backgroundColor = .systemGroupedBackground
        view.tintColor = navigationController?.navigationBar.tintColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(title:"Close",primaryAction:UIAction { [weak self] _ in self?.dismiss(animated:true) })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "closeGuide"
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor),scroll.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-24),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-40),
        ])
        stack.addArrangedSubview(label(info?.camera ?? "Exercise positions",style:.caption1))
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.heightAnchor.constraint(equalTo:canvas.widthAnchor,multiplier:142.0/155).isActive = true
        stack.addArrangedSubview(canvas)
        phase.font = .preferredFont(forTextStyle:.headline); phase.adjustsFontForContentSizeCategory = true; phase.numberOfLines = 0
        phase.accessibilityIdentifier = "guidePhase"; stack.addArrangedSubview(phase)
        position.minimumValue = 0; position.maximumValue = 1; position.accessibilityLabel = "Movement position"; position.accessibilityIdentifier = "guidePosition"
        position.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.pause(); self.playback.scrub(Double(self.position.value)); self.update()
        },for:.valueChanged); stack.addArrangedSubview(position)
        let positions = UIStackView(); positions.axis = .horizontal; positions.distribution = .fillEqually; positions.spacing = 8
        for (title,t) in [("Start",0.0),("Middle",0.5),("Finish",1.0)] {
            let column = UIStackView(); column.axis = .vertical; column.spacing = 8
            let thumbnail = ExerciseCanvasView(exerciseID:exercise.id,name:exercise.name,accessible:false); thumbnail.position = t
            thumbnail.heightAnchor.constraint(equalTo:thumbnail.widthAnchor,multiplier:142.0/155).isActive = true
            column.addArrangedSubview(thumbnail)
            column.addArrangedSubview(button(title,id:"pose-\(title.lowercased())") { [weak self] in
                guard let self else { return }; self.pause(); self.playback.scrub(t); self.update()
            }); positions.addArrangedSubview(column)
        }
        stack.addArrangedSubview(positions)
        var config = UIButton.Configuration.tinted(); config.title = "Play"; config.image = UIImage(systemName:"play.fill"); config.imagePadding = 8
        play.configuration = config; play.accessibilityIdentifier = "guidePlay"; play.heightAnchor.constraint(greaterThanOrEqualToConstant:48).isActive = true
        play.addAction(UIAction { [weak self] _ in self?.togglePlayback() },for:.touchUpInside); stack.addArrangedSubview(play)
        let speed = UISegmentedControl(items:["Slow","Normal"]); speed.selectedSegmentIndex = 0; speed.accessibilityLabel = "Demonstration speed"; speed.accessibilityIdentifier = "guideSpeed"
        speed.addAction(UIAction { [weak self,weak speed] _ in self?.playback.speed = speed?.selectedSegmentIndex == 1 ? 1 : 0.5 },for:.valueChanged); stack.addArrangedSubview(speed)
        stack.addArrangedSubview(button("Reset position",id:"guideReset") { [weak self] in
            guard let self else { return }; self.pause(); self.playback.scrub(0); self.update()
        })
        motionNote.font = .preferredFont(forTextStyle:.footnote); motionNote.adjustsFontForContentSizeCategory = true; motionNote.numberOfLines = 0; motionNote.accessibilityIdentifier = "reducedMotionNote"
        stack.addArrangedSubview(motionNote)
        stack.addArrangedSubview(label(info?.cue ?? exercise.cue,style:.headline))
        stack.addArrangedSubview(label(exercise.instructions,style:.body))
        if let info, let url = URL(string:info.reference), url.scheme == "https" {
            stack.addArrangedSubview(button(info.referenceLabel,id:"guideReference") { [weak self] in
                self?.pause(); self?.present(SFSafariViewController(url:url),animated:true)
            })
        }
        update()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification,UIApplication.didBecomeActiveNotification,UIAccessibility.reduceMotionStatusDidChangeNotification] {
            observations.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause(); self?.update() }
            })
        }
        update()
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); pause() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); observations.forEach(NotificationCenter.default.removeObserver); observations = []
    }
    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel(); label.text = text; label.font = .preferredFont(forTextStyle:style); label.adjustsFontForContentSizeCategory = true; label.numberOfLines = 0; return label
    }
    private func button(_ title: String, id: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.tinted(); config.title = title; config.cornerStyle = .large
        config.contentInsets = .init(top:12,leading:12,bottom:12,trailing:12)
        let button = UIButton(configuration:config,primaryAction:UIAction { _ in action() }); button.accessibilityIdentifier = id
        button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true; return button
    }
    private func togglePlayback() {
        if playback.playing { pause() }
        else {
            playback.play(); previousTime = nil
            let proxy = GuideDisplayLinkTarget(owner:self)
            let link = CADisplayLink(target:proxy,selector:#selector(GuideDisplayLinkTarget.frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum:15,maximum:30,preferred:30)
            link.add(to:.main,forMode:.common); displayLink = link
        }
        update()
    }
    fileprivate func frame(_ link: CADisplayLink) {
        if let previousTime { playback.advance(seconds:link.timestamp-previousTime) }
        previousTime = link.timestamp; update()
    }
    private func pause() {
        playback.pause(); displayLink?.invalidate(); displayLink = nil; previousTime = nil
        if isViewLoaded { update() }
    }
    private func update() {
        guard isViewLoaded else { return }
        canvas.position = playback.progress; position.value = Float(playback.progress)
        position.accessibilityValue = "\(Int(playback.progress*100)) percent"
        phase.text = playback.progress < 0.15 ? info?.start ?? "Start position" : playback.progress > 0.85 ? info?.finish ?? "Finish position" : "Move with control"
        play.isSelected = playback.playing; play.configuration?.title = playback.playing ? "Pause" : "Play"
        play.configuration?.image = UIImage(systemName:playback.playing ? "pause.fill" : "play.fill")
        motionNote.text = UIAccessibility.isReduceMotionEnabled ? "Reduced motion is on. Positions stay still until you choose Play." : "Choose Play to watch the movement, or explore the positions at your own pace."
    }
}

@MainActor
private final class GuideDisplayLinkTarget: NSObject {
    weak var owner: ExerciseGuideViewController?
    init(owner: ExerciseGuideViewController) { self.owner = owner }
    @objc func frame(_ link: CADisplayLink) { owner?.frame(link) }
}
