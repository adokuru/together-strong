import UIKit

struct WorkoutChartEntry {
    let id: String
    let date: String
    let value: Double
    let detail: String
}

@MainActor
final class WorkoutBarChartView: UIView {
    private let scroll = UIScrollView()
    private var positioned = false
    init(entries: [WorkoutChartEntry], unit: String, selectedID: String?, id: String, onSelect: @escaping (String) -> Void) {
        super.init(frame: .zero)
        let maximum = max(1, entries.map(\.value).max() ?? 0)
        let scale = UILabel(); scale.text = "0–\(maximum.formatted()) \(unit)"
        scale.font = .preferredFont(forTextStyle: .caption1); scale.adjustsFontForContentSizeCategory = true
        scale.textColor = .secondaryLabel; scale.accessibilityIdentifier = "\(id)Scale"
        scroll.showsHorizontalScrollIndicator = true; scroll.accessibilityIdentifier = id
        let bars = UIStackView(); bars.axis = .horizontal; bars.spacing = 8; bars.translatesAutoresizingMaskIntoConstraints = false
        for entry in entries {
            let column = UIStackView(); column.axis = .vertical; column.spacing = 4; column.alignment = .fill
            let bar = WorkoutChartBar(value: entry.value, maximum: maximum)
            bar.isSelected = selectedID == entry.id
            bar.accessibilityIdentifier = "\(id)-\(entry.id)"
            bar.accessibilityLabel = "\(WorkoutDate.display(entry.date)), \(entry.value.formatted()) \(unit). \(entry.detail)"
            bar.accessibilityHint = "Shows this record's details"
            bar.addAction(UIAction { [weak bars, weak bar] _ in
                for column in bars?.arrangedSubviews ?? [] {
                    let button = (column as? UIStackView)?.arrangedSubviews.first as? UIButton
                    button?.isSelected = button === bar
                }
                onSelect(entry.id)
            }, for: .touchUpInside)
            bar.heightAnchor.constraint(equalToConstant: 132).isActive = true
            column.addArrangedSubview(bar)
            let date = UILabel(); date.text = WorkoutDate.display(entry.date, short: true)
            date.textAlignment = .center; date.numberOfLines = 2
            date.font = .preferredFont(forTextStyle: .caption2); date.adjustsFontForContentSizeCategory = true; date.accessibilityElementsHidden = true
            column.addArrangedSubview(date); column.widthAnchor.constraint(equalToConstant: 52).isActive = true
            bars.addArrangedSubview(column)
        }
        scroll.addSubview(bars)
        let stack = UIStackView(arrangedSubviews: [scale, scroll]); stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bars.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), bars.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8), bars.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), bars.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            bars.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -8),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: max(188, 148 + UIFont.preferredFont(forTextStyle: .caption2).lineHeight * 2)),
        ])
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !positioned, scroll.bounds.width > 0, scroll.contentSize.width > 0 else { return }
        positioned = true
        scroll.setContentOffset(CGPoint(x: max(0, scroll.contentSize.width-scroll.bounds.width), y: 0), animated: false)
    }
    required init?(coder: NSCoder) { fatalError("Use init(entries:unit:selectedID:id:onSelect:)") }
}

@MainActor
private final class WorkoutChartBar: UIButton {
    private let value: Double
    private let maximum: Double
    override var isSelected: Bool { didSet { setNeedsDisplay() } }
    init(value: Double, maximum: Double) { self.value = value; self.maximum = maximum; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Use init(value:maximum:)") }
    override func draw(_ rect: CGRect) {
        let plot = bounds.insetBy(dx: 6, dy: 8)
        UIColor.separator.setStroke()
        for fraction in [0.0, 0.5, 1.0] {
            let path = UIBezierPath(); let y = plot.maxY - plot.height * fraction
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: bounds.maxX, y: y)); path.lineWidth = 0.5; path.stroke()
        }
        let height = max(2, plot.height * value / maximum)
        let bar = UIBezierPath(roundedRect: CGRect(x: plot.minX, y: plot.maxY-height, width: plot.width, height: height), cornerRadius: 5)
        tintColor.withAlphaComponent(isSelected ? 1 : 0.6).setFill(); bar.fill()
        if isSelected { UIColor.label.setStroke(); bar.lineWidth = 2; bar.stroke() }
    }
}
