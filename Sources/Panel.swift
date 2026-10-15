import AppKit
import QuartzCore

final class SettingsView: NSView {
    let model: AppModel
    private let headerIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Clamshell")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Asleep")
    private let tabBar = TabBar()
    private let container = NSView()
    private let timePage: TimePage
    private let schedulePage: SchedulePage
    private let agentsPage: AgentsPage
    private var tab = SettingsTab.time
    private var awake = false
    private var appeared = false

    init(model: AppModel) {
        self.model = model
        timePage = TimePage(model: model)
        schedulePage = SchedulePage(model: model)
        agentsPage = AgentsPage(model: model)
        super.init(frame: NSRect(x: 0, y: 0, width: 448, height: 508))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        headerIcon.imageScaling = .scaleProportionallyUpOrDown
        headerIcon.image = Glyph.image(awake: false)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2

        for view in [headerIcon, titleLabel, statusLabel, tabBar, container] {
            addSubview(view)
        }
        for page in [timePage, schedulePage, agentsPage] {
            page.translatesAutoresizingMaskIntoConstraints = true
            container.addSubview(page)
        }
        schedulePage.isHidden = true
        agentsPage.isHidden = true
        tabBar.onSelect = { [weak self] tab in
            self?.show(tab)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func reveal() {
        guard !appeared else { return }
        appeared = true
        alphaValue = 0
        layer?.transform = reduceMotion ? CATransform3DIdentity : CATransform3DMakeTranslation(0, 8, 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.01 : 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
            self.animator().alphaValue = 1
        }
        guard !reduceMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = CATransform3DMakeTranslation(0, 8, 0)
        spring.toValue = CATransform3DIdentity
        spring.mass = 1
        spring.stiffness = 280
        spring.damping = 26
        spring.duration = spring.settlingDuration
        layer?.add(spring, forKey: "reveal")
        layer?.transform = CATransform3DIdentity
    }

    func sync() {
        statusLabel.stringValue = model.status
        let isAwake = model.picture.awake
        headerIcon.image = Glyph.image(awake: isAwake)
        if isAwake != awake {
            awake = isAwake
            popIcon()
        }
        timePage.sync()
        schedulePage.sync()
        agentsPage.sync()
        needsLayout = true
    }

    func updateCountdown() {
        timePage.updateCountdown()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        headerIcon.frame = CGRect(x: 22, y: 40, width: 28, height: 28)
        titleLabel.frame = CGRect(x: 62, y: 34, width: width - 84, height: 24)
        statusLabel.frame = CGRect(x: 62, y: 56, width: width - 84, height: 34)
        tabBar.frame = CGRect(x: 18, y: 100, width: width - 36, height: 32)
        let pagesY: CGFloat = 148
        let pagesH = max(0, bounds.height - pagesY - 22)
        container.frame = CGRect(x: 22, y: pagesY, width: width - 44, height: pagesH)
        for page in [timePage, schedulePage, agentsPage] {
            page.frame = container.bounds
        }
        timePage.layoutContents()
        schedulePage.layoutContents()
        agentsPage.layoutContents()
    }

    private func show(_ next: SettingsTab) {
        guard next != tab else { return }
        let old = page(tab)
        let new = page(next)
        tab = next
        tabBar.setSelected(next, animated: !reduceMotion)
        new.isHidden = false
        new.alphaValue = 0
        if !reduceMotion {
            new.layer?.transform = CATransform3DMakeTranslation(0, 8, 0)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.01 : 0.2
            old.animator().alphaValue = 0
            new.animator().alphaValue = 1
        }
        if !reduceMotion {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = CATransform3DMakeTranslation(0, 8, 0)
            spring.toValue = CATransform3DIdentity
            spring.mass = 0.8
            spring.stiffness = 340
            spring.damping = 26
            spring.duration = spring.settlingDuration
            new.layer?.add(spring, forKey: "slide")
            new.layer?.transform = CATransform3DIdentity
        }
        let previous = old
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            if previous !== self.page(self.tab) {
                previous.isHidden = true
                previous.alphaValue = 1
            }
        }
    }

    private func page(_ tab: SettingsTab) -> NSView {
        switch tab {
        case .time: timePage
        case .schedule: schedulePage
        case .agents: agentsPage
        }
    }

    private func popIcon() {
        guard !reduceMotion, let layer = headerIcon.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.84
        spring.toValue = 1
        spring.mass = 0.6
        spring.stiffness = 420
        spring.damping = 14
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }

    @objc private func appearanceChanged() {
        sync()
    }
}

private enum SettingsTab: Int {
    case time, schedule, agents
}

private final class TabBar: NSView {
    var onSelect: ((SettingsTab) -> Void)?
    private let pill = NSView()
    private var buttons: [NSButton] = []
    private var selected = SettingsTab.time
    private var animating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        pill.layer?.cornerRadius = 15
        addSubview(pill)
        for (index, title) in ["Time", "Schedule", "Agents"].enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(pressed(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 13, weight: index == 0 ? .semibold : .medium)
            button.contentTintColor = index == 0 ? .labelColor : .secondaryLabelColor
            button.setButtonType(.momentaryChange)
            addSubview(button)
            buttons.append(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func setSelected(_ tab: SettingsTab, animated: Bool) {
        selected = tab
        for (index, button) in buttons.enumerated() {
            let on = index == tab.rawValue
            button.font = .systemFont(ofSize: 13, weight: on ? .semibold : .medium)
            button.contentTintColor = on ? .labelColor : .secondaryLabelColor
        }
        placePill(animated: animated)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for button in buttons {
            button.sizeToFit()
            let width = button.bounds.width + 22
            button.frame = CGRect(x: x, y: 1, width: width, height: 30)
            x += width + 4
        }
        if !animating {
            placePill(animated: false)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        pill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }

    @objc private func pressed(_ sender: NSButton) {
        guard let tab = SettingsTab(rawValue: sender.tag) else { return }
        onSelect?(tab)
    }

    private func placePill(animated: Bool) {
        guard buttons.indices.contains(selected.rawValue) else { return }
        let frame = buttons[selected.rawValue].frame
        if !animated || reduceMotion {
            pill.frame = frame
            return
        }
        animating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.2, 1)
            self.pill.animator().frame = frame
        } completionHandler: {
            self.animating = false
        }
    }
}

private final class TimePage: NSView, NSTextFieldDelegate {
    let model: AppModel
    private let dial: CrownDial
    private let presets = FlippedView()
    private var presetButtons: [PillButton] = []
    private let field = NSTextField()
    private let setButton = PillButton(title: "Set")
    private let fieldRow = NSView()
    private let actionButton = PillButton(title: "Keep awake")
    private var updating = false

    init(model: AppModel) {
        self.model = model
        dial = CrownDial(minutes: model.prefs.dialMinutes)
        super.init(frame: .zero)
        wantsLayer = true
        dial.onCommit = { [weak self] minutes in
            guard let self, !self.updating else { return }
            self.model.setDial(minutes)
            if self.field.currentEditor() == nil {
                self.field.stringValue = DurationText.compact(minutes)
            }
            self.refreshPresets()
        }
        addSubview(dial)

        for minutes in [60, 120, 240] {
            let button = PillButton(title: DurationText.words(minutes))
            button.tag = minutes
            button.target = self
            button.action = #selector(preset(_:))
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            presets.addSubview(button)
            presetButtons.append(button)
        }
        addSubview(presets)

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = roundedFont(14, .medium)
        field.placeholderString = "1h 30m"
        field.delegate = self
        field.stringValue = DurationText.compact(model.prefs.dialMinutes)
        fieldRow.wantsLayer = true
        fieldRow.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        fieldRow.layer?.cornerRadius = 10
        fieldRow.addSubview(field)
        setButton.target = self
        setButton.action = #selector(commitTyped)
        setButton.font = .systemFont(ofSize: 13, weight: .semibold)
        addSubview(fieldRow)
        addSubview(setButton)

        actionButton.target = self
        actionButton.action = #selector(primary)
        actionButton.font = .systemFont(ofSize: 14, weight: .semibold)
        actionButton.filled = true
        actionButton.cornerRadius = 12
        addSubview(actionButton)
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func sync() {
        updating = true
        let running = model.picture.timerEndsAt != nil
        presets.isHidden = running
        fieldRow.isHidden = running
        setButton.isHidden = running
        dial.locked = running
        if running {
            dial.caption = "left"
            updateCountdown()
            actionButton.title = "Stop timer"
        } else {
            dial.caption = "awake"
            dial.show(minutes: model.prefs.dialMinutes)
            if field.currentEditor() == nil {
                field.stringValue = DurationText.compact(model.prefs.dialMinutes)
            }
            actionButton.title = "Keep awake"
        }
        refreshPresets()
        updating = false
        needsLayout = true
    }

    func updateCountdown() {
        guard let end = model.picture.timerEndsAt else { return }
        dial.readout = DurationText.countdown(end.timeIntervalSince(model.now))
        let whole = Double(model.runtime.timerMinutes ?? model.prefs.dialMinutes) * 60
        dial.progress = whole > 0 ? min(1, max(0, end.timeIntervalSince(model.now) / whole)) : 0
    }

    func layoutContents() {
        let width = bounds.width
        dial.frame = CGRect(x: (width - 260) / 2, y: 0, width: 260, height: 184)
        var y: CGFloat = 200
        if !presets.isHidden {
            presets.frame = CGRect(x: 0, y: y, width: width, height: 34)
            let gap: CGFloat = 8
            let chip = (width - gap * CGFloat(presetButtons.count - 1)) / CGFloat(presetButtons.count)
            for (offset, button) in presetButtons.enumerated() {
                button.frame = CGRect(x: CGFloat(offset) * (chip + gap), y: 0, width: chip, height: 34)
            }
            y += 44
        }
        if !fieldRow.isHidden {
            setButton.sizeToFit()
            let setWidth = setButton.bounds.width + 22
            fieldRow.frame = CGRect(x: 0, y: y, width: width - setWidth - 8, height: 36)
            field.frame = CGRect(x: 12, y: 8, width: fieldRow.bounds.width - 20, height: 20)
            setButton.frame = CGRect(x: width - setWidth, y: y, width: setWidth, height: 36)
            y += 46
        }
        actionButton.frame = CGRect(x: 0, y: y, width: width, height: 40)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fieldRow.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTyped()
            return true
        }
        return false
    }

    @objc private func preset(_ sender: NSButton) {
        let minutes = sender.tag
        model.setDial(minutes)
        field.stringValue = DurationText.compact(minutes)
        dial.animate(to: minutes)
        refreshPresets()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    @objc private func commitTyped() {
        guard let minutes = DurationText.parse(field.stringValue) else {
            shake(fieldRow)
            return
        }
        model.setDial(minutes)
        field.stringValue = DurationText.compact(minutes)
        dial.animate(to: minutes)
        window?.makeFirstResponder(nil)
        refreshPresets()
    }

    @objc private func primary() {
        if model.picture.timerEndsAt != nil {
            model.stopTimer()
        } else {
            model.startTimer(minutes: model.prefs.dialMinutes)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        sync()
    }

    private func refreshPresets() {
        for button in presetButtons {
            button.selected = button.tag == model.prefs.dialMinutes
        }
    }
}

private final class CrownDial: NSView {
    var onCommit: ((Int) -> Void)?
    var locked = false
    var progress: Double? { didSet { needsDisplay = true } }
    var caption = "awake" { didSet { captionLabel.stringValue = caption } }
    var readout = "" { didSet { valueLabel.stringValue = readout } }

    private let detents = DurationText.detents
    private let sweep = 248.0
    private var index = 3
    private var knobIndex: CGFloat = 3
    private var velocity: CGFloat = 0
    private var springTimer: Timer?
    private var dragging = false
    private let valueLabel = NSTextField(labelWithString: "1h")
    private let captionLabel = NSTextField(labelWithString: "awake")
    private var lastHapticIndex = 3

    init(minutes: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        valueLabel.font = roundedFont(44, .medium)
        valueLabel.alignment = .center
        valueLabel.textColor = .labelColor
        captionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        captionLabel.alignment = .center
        captionLabel.textColor = .secondaryLabelColor
        addSubview(valueLabel)
        addSubview(captionLabel)
        let nearest = DurationText.nearestDetent(minutes)
        index = detents.firstIndex(of: nearest) ?? 3
        knobIndex = CGFloat(index)
        lastHapticIndex = index
        readout = DurationText.compact(detents[index])
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("How long the lid stays awake")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(minutes: Int) {
        guard !dragging else { return }
        let nearest = DurationText.nearestDetent(minutes)
        guard let found = detents.firstIndex(of: nearest), found != index || abs(knobIndex - CGFloat(found)) > 0.01 else {
            readout = DurationText.compact(minutes)
            needsDisplay = true
            return
        }
        index = found
        knobIndex = CGFloat(found)
        velocity = 0
        readout = DurationText.compact(detents[found])
        needsDisplay = true
    }

    func animate(to minutes: Int) {
        let nearest = DurationText.nearestDetent(minutes)
        guard let found = detents.firstIndex(of: nearest) else { return }
        index = found
        readout = DurationText.compact(detents[found])
        startSpring(hapticAlongTheWay: true)
    }

    override func layout() {
        super.layout()
        valueLabel.frame = CGRect(x: 40, y: dialCenter.y - 18, width: bounds.width - 80, height: 52)
        captionLabel.frame = CGRect(x: 40, y: dialCenter.y - 38, width: bounds.width - 80, height: 18)
    }

    private var dialRadius: CGFloat {
        min(bounds.width / 2 - 12, (bounds.height - 16) / 1.56)
    }

    private var dialCenter: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.height - 8 - dialRadius)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === valueLabel || hit === captionLabel { return self }
        return hit
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = dialCenter
        let radius = dialRadius
        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: CGFloat(90 + sweep / 2),
            endAngle: CGFloat(90 - sweep / 2),
            clockwise: true
        )
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        track.lineWidth = 2
        track.lineCapStyle = .round
        track.stroke()

        let fraction = progress ?? (detents.count > 1 ? Double(knobIndex) / Double(detents.count - 1) : 0)
        let value = NSBezierPath()
        let end = 90 + sweep / 2 - sweep * fraction
        value.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: CGFloat(90 + sweep / 2),
            endAngle: CGFloat(end),
            clockwise: true
        )
        NSColor.labelColor.withAlphaComponent(0.92).setStroke()
        value.lineWidth = 3
        value.lineCapStyle = .round
        value.stroke()

        for (offset, minutes) in detents.enumerated() {
            let tick = angleFor(CGFloat(offset))
            let major = [60, 120, 240].contains(minutes)
            let passed = Double(offset) / Double(max(1, detents.count - 1)) <= fraction + 0.001
            let inner = radius - (major ? 20 : 15)
            let outer = radius - 10
            let mark = NSBezierPath()
            mark.move(to: polar(center, tick, inner))
            mark.line(to: polar(center, tick, outer))
            let alpha: CGFloat = (major ? 0.5 : 0.25) * (passed ? 1.4 : 1)
            NSColor.labelColor.withAlphaComponent(alpha).setStroke()
            mark.lineWidth = major ? 1.6 : 1.15
            mark.lineCapStyle = .round
            mark.stroke()
        }

        guard progress == nil else { return }
        let knobCenter = polar(center, 90 - end, radius)
        let knob = NSBezierPath(ovalIn: CGRect(x: knobCenter.x - 6, y: knobCenter.y - 6, width: 12, height: 12))
        NSColor.labelColor.setFill()
        knob.fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard !locked else { return }
        dragging = true
        springTimer?.invalidate()
        velocity = 0
        track(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        track(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        knobIndex = CGFloat(index)
        onCommit?(detents[index])
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard !locked else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        if abs(delta) < (event.hasPreciseScrollingDeltas ? 6 : 0.4) { return }
        step(delta > 0 ? 1 : -1)
    }

    override func accessibilityValue() -> Any? {
        DurationText.words(detents[index])
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard !locked else { return false }
        step(1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard !locked else { return false }
        step(-1)
        return true
    }

    private func track(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let center = dialCenter
        let dx = location.x - center.x
        let dy = location.y - center.y
        let fromTop = normalize(90 - atan2(dy, dx) * 180 / .pi)
        let next = indexFor(fromTop)
        guard next != index else { return }
        index = next
        knobIndex = CGFloat(next)
        readout = DurationText.compact(detents[next])
        if next != lastHapticIndex {
            lastHapticIndex = next
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        onCommit?(detents[next])
        needsDisplay = true
    }

    private func step(_ delta: Int) {
        let next = min(detents.count - 1, max(0, index + delta))
        guard next != index else { return }
        index = next
        readout = DurationText.compact(detents[next])
        onCommit?(detents[next])
        startSpring(hapticAlongTheWay: true)
    }

    private func startSpring(hapticAlongTheWay: Bool) {
        springTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.stepSpring(haptic: hapticAlongTheWay)
        }
        springTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepSpring(haptic: Bool) {
        if reduceMotion {
            knobIndex = CGFloat(index)
            velocity = 0
            springTimer?.invalidate()
            springTimer = nil
            needsDisplay = true
            return
        }
        let target = CGFloat(index)
        let dt: CGFloat = 1.0 / 120.0
        let force = -320 * (knobIndex - target) - 22 * velocity
        velocity += force * dt
        knobIndex += velocity * dt
        let rounded = Int(knobIndex.rounded())
        if haptic, detents.indices.contains(rounded), rounded != lastHapticIndex {
            lastHapticIndex = rounded
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if abs(knobIndex - target) < 0.004 && abs(velocity) < 0.03 {
            knobIndex = target
            velocity = 0
            springTimer?.invalidate()
            springTimer = nil
            lastHapticIndex = index
        }
        needsDisplay = true
    }

    private func angleFor(_ offset: CGFloat) -> Double {
        let fraction = detents.count > 1 ? Double(offset) / Double(detents.count - 1) : 0
        return -sweep / 2 + sweep * fraction
    }

    private func indexFor(_ fromTop: Double) -> Int {
        let clamped = min(sweep / 2, max(-sweep / 2, fromTop))
        let fraction = (clamped + sweep / 2) / sweep
        let raw = Int((fraction * Double(detents.count - 1)).rounded())
        return min(detents.count - 1, max(0, raw))
    }

    private func normalize(_ degrees: Double) -> Double {
        var value = degrees
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }

    private func polar(_ center: CGPoint, _ degreesFromTop: Double, _ radius: CGFloat) -> CGPoint {
        let radians = (90 - degreesFromTop) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}

private final class SchedulePage: NSView {
    let model: AppModel
    private let toggle = NSSwitch()
    private let titleLabel = NSTextField(labelWithString: "On a schedule")
    private let daysRow = FlippedView()
    private var dayButtons: [PillButton] = []
    private let fromPicker = NSDatePicker()
    private let untilPicker = NSDatePicker()
    private let fromLabel = NSTextField(labelWithString: "From")
    private let untilLabel = NSTextField(labelWithString: "Until")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let paused = NSTextField(wrappingLabelWithString: "Paused until this block ends.")
    private let controls = FlippedView()
    private var updating = false

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        toggle.target = self
        toggle.action = #selector(toggled)
        summary.font = .systemFont(ofSize: 13)
        summary.textColor = .secondaryLabelColor
        paused.font = .systemFont(ofSize: 12)
        paused.textColor = .secondaryLabelColor
        for label in [fromLabel, untilLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
        }
        configure(fromPicker)
        configure(untilPicker)
        fromPicker.target = self
        fromPicker.action = #selector(startChanged)
        untilPicker.target = self
        untilPicker.action = #selector(endChanged)

        for view in [toggle, titleLabel, controls, paused] {
            addSubview(view)
        }
        for view in [daysRow, fromLabel, untilLabel, fromPicker, untilPicker, summary] {
            controls.addSubview(view)
        }
        for day in EngineWeekdays.ordered() {
            let button = PillButton(title: day.symbol)
            button.tag = day.weekday
            button.target = self
            button.action = #selector(dayPressed(_:))
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.circular = true
            button.setAccessibilityLabel(day.name)
            daysRow.addSubview(button)
            dayButtons.append(button)
        }
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func sync() {
        updating = true
        toggle.state = model.prefs.scheduleEnabled ? .on : .off
        for button in dayButtons {
            button.selected = model.prefs.days.contains(button.tag)
        }
        fromPicker.dateValue = Engine.date(minute: model.prefs.startMinute, calendar: .current)
        untilPicker.dateValue = Engine.date(minute: model.prefs.endMinute, calendar: .current)
        summary.stringValue = summaryText()
        controls.alphaValue = model.prefs.scheduleEnabled ? 1 : 0.4
        let enabled = model.prefs.scheduleEnabled
        for case let control as NSControl in controls.subviews {
            control.isEnabled = enabled
        }
        for button in dayButtons {
            button.isEnabled = enabled
        }
        paused.isHidden = !(model.runtime.pausedSchedule && model.prefs.scheduleEnabled)
        updating = false
    }

    func layoutContents() {
        let width = bounds.width
        toggle.frame = CGRect(x: width - 40, y: 0, width: 40, height: 24)
        titleLabel.frame = CGRect(x: 0, y: 3, width: width - 60, height: 18)
        controls.frame = CGRect(x: 0, y: 44, width: width, height: 160)
        daysRow.frame = CGRect(x: 0, y: 0, width: width, height: 32)
        let chip: CGFloat = 32
        let gap = max(6, (width - chip * 7) / 6)
        for (offset, button) in dayButtons.enumerated() {
            button.frame = CGRect(x: CGFloat(offset) * (chip + gap), y: 0, width: chip, height: chip)
        }
        fromLabel.frame = CGRect(x: 0, y: 48, width: 80, height: 16)
        untilLabel.frame = CGRect(x: width / 2, y: 48, width: 80, height: 16)
        fromPicker.frame = CGRect(x: 0, y: 66, width: width / 2 - 12, height: 28)
        untilPicker.frame = CGRect(x: width / 2, y: 66, width: width / 2 - 8, height: 28)
        summary.frame = CGRect(x: 0, y: 110, width: width, height: 36)
        paused.frame = CGRect(x: 0, y: controls.frame.maxY + 8, width: width, height: 18)
    }

    private func summaryText() -> String {
        if model.prefs.days.isEmpty { return "No days selected." }
        let days = EngineWeekdays.phrase(model.prefs.days)
        let start = Engine.clock(model.prefs.startMinute, calendar: .current)
        let end = Engine.clock(model.prefs.endMinute, calendar: .current)
        if model.prefs.startMinute == model.prefs.endMinute {
            return "Start and end are the same."
        }
        if model.prefs.startMinute > model.prefs.endMinute {
            return "\(days), \(start) to \(end) next day."
        }
        return "\(days), \(start) to \(end)."
    }

    private func configure(_ picker: NSDatePicker) {
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.font = .systemFont(ofSize: 13, weight: .medium)
        picker.isBezeled = true
    }

    @objc private func toggled() {
        guard !updating else { return }
        model.setScheduleEnabled(toggle.state == .on)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.01 : 0.22
            self.controls.animator().alphaValue = self.model.prefs.scheduleEnabled ? 1 : 0.4
        }
        sync()
    }

    @objc private func dayPressed(_ sender: NSButton) {
        guard !updating else { return }
        model.toggleDay(sender.tag)
        sync()
    }

    @objc private func startChanged() {
        guard !updating else { return }
        model.setStart(fromPicker.dateValue)
        summary.stringValue = summaryText()
    }

    @objc private func endChanged() {
        guard !updating else { return }
        model.setEnd(untilPicker.dateValue)
        summary.stringValue = summaryText()
    }
}

private final class AgentsPage: NSView, NSTextFieldDelegate {
    let model: AppModel
    private let toggle = NSSwitch()
    private let titleLabel = NSTextField(labelWithString: "While an agent is running")
    private let card = NSView()
    private let cardText = NSTextField(wrappingLabelWithString: "")
    private let rows = NSStackView()
    private let watchLabel = NSTextField(labelWithString: "Also watch")
    private let extra = NSTextField()
    private let extraRow = NSView()
    private let paused = NSTextField(wrappingLabelWithString: "Paused until the next agent starts.")
    private var renderedAgents: [String] = []
    private var updating = false

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        toggle.target = self
        toggle.action = #selector(toggled)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        card.layer?.cornerRadius = 12
        cardText.font = .systemFont(ofSize: 13)
        cardText.textColor = .secondaryLabelColor
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        watchLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        extra.isBordered = false
        extra.drawsBackground = false
        extra.focusRingType = .none
        extra.font = .systemFont(ofSize: 13)
        extra.placeholderString = "Program names, comma separated"
        extra.delegate = self
        extra.stringValue = model.prefs.extraAgents.joined(separator: ", ")
        extraRow.wantsLayer = true
        extraRow.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        extraRow.layer?.cornerRadius = 10
        extraRow.addSubview(extra)
        paused.font = .systemFont(ofSize: 12)
        paused.textColor = .secondaryLabelColor
        for view in [toggle, titleLabel, card, watchLabel, extraRow, paused] {
            addSubview(view)
        }
        card.addSubview(cardText)
        card.addSubview(rows)
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func sync() {
        updating = true
        toggle.state = model.prefs.followAgents ? .on : .off
        if model.agents != renderedAgents {
            renderedAgents = model.agents
            rows.arrangedSubviews.forEach {
                rows.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            for name in model.agents {
                rows.addArrangedSubview(agentRow(name))
            }
        }
        let empty = model.agents.isEmpty
        cardText.isHidden = !empty
        rows.isHidden = empty
        cardText.stringValue = "No agents running"
        paused.isHidden = !(model.runtime.pausedAgents && model.prefs.followAgents && !model.agents.isEmpty)
        if extra.currentEditor() == nil {
            let text = model.prefs.extraAgents.joined(separator: ", ")
            if extra.stringValue != text { extra.stringValue = text }
        }
        updating = false
        needsLayout = true
    }

    func layoutContents() {
        let width = bounds.width
        toggle.frame = CGRect(x: width - 40, y: 0, width: 40, height: 24)
        titleLabel.frame = CGRect(x: 0, y: 3, width: width - 60, height: 18)
        let cardHeight: CGFloat = model.agents.isEmpty ? 44 : CGFloat(max(44, 16 + model.agents.count * 26))
        card.frame = CGRect(x: 0, y: 44, width: width, height: cardHeight)
        cardText.frame = CGRect(x: 12, y: 13, width: width - 24, height: 18)
        rows.frame = CGRect(x: 12, y: 10, width: width - 24, height: cardHeight - 16)
        let watchY = card.frame.maxY + 16
        watchLabel.frame = CGRect(x: 0, y: watchY, width: width, height: 18)
        extraRow.frame = CGRect(x: 0, y: watchY + 22, width: width, height: 36)
        extra.frame = CGRect(x: 12, y: 8, width: width - 24, height: 20)
        paused.frame = CGRect(x: 0, y: extraRow.frame.maxY + 10, width: width, height: 18)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        card.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        extraRow.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !updating else { return }
        model.setExtraAgents(extra.stringValue)
    }

    @objc private func toggled() {
        guard !updating else { return }
        model.setFollowAgents(toggle.state == .on)
    }

    private func agentRow(_ name: String) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 22))
        let dot = NSView(frame: NSRect(x: 0, y: 7, width: 7, height: 7))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 3.5
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: 16, y: 1, width: 220, height: 18)
        let state = NSTextField(labelWithString: "Running")
        state.font = .systemFont(ofSize: 12)
        state.textColor = .secondaryLabelColor
        state.alignment = .right
        state.frame = NSRect(x: 240, y: 2, width: 100, height: 16)
        row.addSubview(dot)
        row.addSubview(label)
        row.addSubview(state)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return row
    }
}

private final class PillButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    var filled = false { didSet { needsDisplay = true } }
    var circular = false { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 17

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        font = .systemFont(ofSize: 13, weight: .semibold)
        title = ""
    }

    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let on = selected || filled
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor = on ? (dark ? .white : .black) : NSColor.labelColor.withAlphaComponent(0.1)
        let ink: NSColor = on ? (dark ? .black : .white) : .labelColor
        let path = circular
            ? NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            : NSBezierPath(roundedRect: bounds, xRadius: min(cornerRadius, bounds.height / 2), yRadius: min(cornerRadius, bounds.height / 2))
        fill.setFill()
        path.fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: ink,
            .paragraphStyle: style,
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        text.draw(in: rect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        animateScale(0.96)
        super.mouseDown(with: event)
        animateScale(1)
    }

    private func animateScale(_ value: CGFloat) {
        guard !reduceMotion, let layer else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        spring.toValue = value
        spring.mass = 0.55
        spring.stiffness = 460
        spring.damping = 18
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "scale")
        layer.transform = CATransform3DMakeScale(value, value, 1)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded),
          let font = NSFont(descriptor: descriptor, size: size) else { return base }
    return font
}

private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

private func shake(_ view: NSView) {
    guard let layer = view.layer else { return }
    let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
    animation.values = [0, -7, 7, -5, 4, -2, 0]
    animation.duration = reduceMotion ? 0.01 : 0.36
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "shake")
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
}

private enum EngineWeekdays {
    struct Day {
        var weekday: Int
        var symbol: String
        var name: String
    }

    static func ordered(calendar: Calendar = .current) -> [Day] {
        let short = calendar.veryShortWeekdaySymbols
        let full = calendar.weekdaySymbols
        let first = calendar.firstWeekday
        return (0..<7).map { offset in
            let weekday = ((first - 1 + offset) % 7) + 1
            return Day(weekday: weekday, symbol: short[weekday - 1], name: full[weekday - 1])
        }
    }

    static func phrase(_ days: [Int], calendar: Calendar = .current) -> String {
        let set = Set(days)
        if set == [2, 3, 4, 5, 6] { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        if set.count == 7 { return "Every day" }
        let names = ordered(calendar: calendar).filter { set.contains($0.weekday) }.map(\.name)
        return names.joined(separator: ", ")
    }
}
