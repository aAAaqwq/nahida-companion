import AppKit
import AVFoundation
import CoreGraphics

private let cellWidth = 192
private let cellHeight = 208

private struct SpriteStep {
    let row: Int
    let column: Int
    let offsetX: CGFloat

    init(_ row: Int, _ column: Int, _ offsetX: CGFloat = 0) {
        self.row = row
        self.column = column
        self.offsetX = offsetX
    }
}

private enum PetAction: String, CaseIterable {
    case wave, hop, cuddle, curious, stroll, focus, celebrate, nap

    var title: String {
        switch self {
        case .wave: "挥挥手"
        case .hop: "轻轻跳"
        case .cuddle: "撒个娇"
        case .curious: "好奇歪头"
        case .stroll: "散散步"
        case .focus: "专心想想"
        case .celebrate: "开心一下"
        case .nap: "打个盹"
        }
    }

    var steps: [SpriteStep] {
        switch self {
        case .wave:
            [0, 1, 2, 3, 2, 1, 0].map { SpriteStep(3, $0) }
        case .hop:
            [0, 1, 2, 3, 4, 3, 2, 1, 0].map { SpriteStep(4, $0) }
        case .cuddle:
            [SpriteStep(6, 2), SpriteStep(6, 3), SpriteStep(6, 4),
             SpriteStep(3, 1), SpriteStep(3, 2), SpriteStep(3, 3),
             SpriteStep(3, 2), SpriteStep(6, 4), SpriteStep(6, 5)]
        case .curious:
            [SpriteStep(9, 0), SpriteStep(9, 2), SpriteStep(9, 4),
             SpriteStep(9, 2), SpriteStep(9, 0), SpriteStep(10, 6),
             SpriteStep(10, 4), SpriteStep(10, 6), SpriteStep(9, 0)]
        case .stroll:
            (0..<8).map { SpriteStep(1, $0, CGFloat($0) * 6) } +
            (0..<8).map { SpriteStep(2, $0, CGFloat(7 - $0) * 6) }
        case .focus:
            [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0].map { SpriteStep(7, $0) }
        case .celebrate:
            [0, 1, 2, 3, 4, 5, 4, 2, 0].map { SpriteStep(8, $0) }
        case .nap:
            [0, 1].map { SpriteStep(0, $0) } +
            Array(repeating: SpriteStep(0, 2), count: 18) +
            [3, 4, 5].map { SpriteStep(0, $0) }
        }
    }

    var frameDuration: TimeInterval { self == .nap ? 0.25 : 0.17 }
}

private enum Reminder: String, CaseIterable {
    case eyes, move, water, caffeine, sleep

    var text: String {
        switch self {
        case .eyes: "看向远处 20 秒，顺便眨眨眼，好吗？"
        case .move: "我们起身走两分钟吧，我在这里等你。"
        case .water: "休息时记得喝点水，按口渴和自己的需要来。"
        case .caffeine: "已经到下午啦，今晚想睡得安稳的话，留意咖啡因。"
        case .sleep: "今天辛苦了，留一点时间给睡眠吧。"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .eyes: 20 * 60
        case .move: 45 * 60
        case .water: 60 * 60
        case .caffeine, .sleep: nil
        }
    }
}

private enum OriginalClip: String, CaseIterable {
    case greeting, celebrate, birthday

    var title: String {
        switch self {
        case .greeting: "可算找到你了"
        case .celebrate: "花神诞祭"
        case .birthday: "生日快乐"
        }
    }

    var caption: String {
        switch self {
        case .greeting: "神明啊，可算找到你了。大家都期待与你见面。"
        case .celebrate: "花神诞祭开幕了，大家快乐地转着圈。"
        case .birthday: "生日快乐，纳西妲。"
        }
    }

    var action: PetAction {
        switch self {
        case .greeting: .curious
        case .celebrate, .birthday: .celebrate
        }
    }
}

private final class SpriteAtlas {
    private let image: CGImage
    private var cachedFrames: [Int: NSImage] = [:]

    init?(path: String) {
        guard let source = NSImage(contentsOfFile: path),
              let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.width == 1536, image.height == 2288 else { return nil }
        self.image = image
    }

    func frame(row: Int, column: Int) -> NSImage? {
        guard (0..<11).contains(row), (0..<8).contains(column) else { return nil }
        let key = row * 8 + column
        if let cached = cachedFrames[key] { return cached }
        guard
              let cropped = image.cropping(to: CGRect(
                x: column * cellWidth,
                y: row * cellHeight,
                width: cellWidth,
                height: cellHeight
              )) else { return nil }
        let frame = NSImage(cgImage: cropped, size: NSSize(width: cellWidth, height: cellHeight))
        cachedFrames[key] = frame
        return frame
    }
}

@MainActor private final class DraggablePetView: NSImageView {
    var onTap: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    private var mouseDownAt: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownAt, let origin = windowOriginAtMouseDown else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        if !didDrag && hypot(dx, dy) >= 4 {
            didDrag = true
            onDragStart?()
        }
        if didDrag {
            window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            onDrag?(dx, dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { onDragEnd?() } else { onTap?() }
        mouseDownAt = nil
        windowOriginAtMouseDown = nil
        didDrag = false
    }
}

@MainActor private final class Companion: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var imageView: DraggablePetView!
    private var bubble: NSView!
    private var bubbleLabel: NSTextField!
    private var statusItem: NSStatusItem!
    private var speechItem: NSMenuItem!
    private var systemReadingItem: NSMenuItem!
    private var reminderItem: NSMenuItem!
    private var atlas: SpriteAtlas!
    private let speaker = AVSpeechSynthesizer()
    private var originalPlayer: AVAudioPlayer?
    private var dialogueTimer: Timer?
    private var pendingDialogue: (text: String, action: PetAction)?
    private var lastAutomaticVoiceAt = Date.distantPast
    private var activeAction: PetAction?
    private var actionIsAmbient = false
    private var actionStartedAt = Date.distantPast
    private var nextAmbientAt = Date().addingTimeInterval(60)
    private var frameIndex = 0
    private var isDraggingPet = false
    private var dragDelta = NSPoint.zero
    private var dragFrameIndex = 0
    private var lastDragFrameAt = Date.distantPast
    private var bubbleEndsAt = Date.distantPast
    private var lastCursor = NSEvent.mouseLocation
    private var lastCursorMoveAt = Date.distantPast
    private var lastReminderAt: [Reminder: Date] = [:]
    private var pending: [Reminder] = []
    private var lastDailyKey: [Reminder: String] = [:]
    private var lastDeliveredAt = Date.distantPast
    private var snoozeUntil = Date.distantPast
    private var frameTimer: Timer?
    private var reminderTimer: Timer?
    private var speechEnabled = true
    private var systemReadingEnabled = false
    private var remindersEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let asset = assetPath()
        guard let loaded = SpriteAtlas(path: asset) else {
            let alert = NSAlert()
            alert.messageText = "找不到有效的宠物图集"
            alert.informativeText = "请把 spritesheet.webp 放在小纳西妲宠物目录，或设定 NAHIDA_SPRITESHEET。\n\(asset)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        atlas = loaded
        speechEnabled = UserDefaults.standard.object(forKey: "speechEnabled") as? Bool ?? true
        systemReadingEnabled = UserDefaults.standard.object(forKey: "systemReadingEnabled") as? Bool ?? false
        remindersEnabled = UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool ?? true
        buildPanel()
        buildMenu()
        panel.orderFrontRegardless()
        showFrame(row: 0, column: 0)
        frameTimer = Timer(timeInterval: 0.16, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(frameTimer!, forMode: .common)
        reminderTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(checkReminders), userInfo: nil, repeats: true)
    }

    private func assetPath() -> String {
        if let override = ProcessInfo.processInfo.environment["NAHIDA_SPRITESHEET"], !override.isEmpty {
            return override
        }
        if let bundled = Bundle.main.path(forResource: "spritesheet", ofType: "webp") {
            return bundled
        }
        return NSString(string: "~/.codex/pets/nahida-companion/spritesheet.webp").expandingTildeInPath
    }

    private func buildPanel() {
        let size = NSSize(width: 300, height: 300)
        let origin = savedOrigin(for: size) ?? defaultOrigin(for: size)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        panel.contentView = root

        imageView = DraggablePetView(frame: NSRect(x: 54, y: 0, width: 192, height: 208))
        imageView.imageScaling = .scaleNone
        imageView.setAccessibilityLabel("小纳西妲，待机")
        imageView.onTap = { [weak self] in self?.petTapped() }
        imageView.onDragStart = { [weak self] in self?.beginDragging() }
        imageView.onDrag = { [weak self] dx, dy in self?.dragMoved(dx: dx, dy: dy) }
        imageView.onDragEnd = { [weak self] in self?.endDragging() }
        root.addSubview(imageView)

        bubble = NSView(frame: NSRect(x: 8, y: 220, width: 284, height: 72))
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.99, blue: 0.92, alpha: 0.95).cgColor
        bubble.layer?.cornerRadius = 18
        bubble.layer?.borderWidth = 1
        bubble.layer?.borderColor = NSColor(calibratedRed: 0.38, green: 0.50, blue: 0.28, alpha: 0.8).cgColor
        bubbleLabel = NSTextField(labelWithString: "")
        bubbleLabel.frame = NSRect(x: 14, y: 9, width: 256, height: 54)
        bubbleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        bubbleLabel.textColor = NSColor(calibratedRed: 0.17, green: 0.27, blue: 0.14, alpha: 1)
        bubbleLabel.alignment = .center
        bubbleLabel.lineBreakMode = .byWordWrapping
        bubbleLabel.maximumNumberOfLines = 3
        bubble.addSubview(bubbleLabel)
        bubble.isHidden = true
        root.addSubview(bubble)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
    }

    private func savedOrigin(for size: NSSize) -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "windowX") != nil,
              defaults.object(forKey: "windowY") != nil else { return nil }
        let origin = NSPoint(x: defaults.double(forKey: "windowX"), y: defaults.double(forKey: "windowY"))
        let savedFrame = NSRect(origin: origin, size: size)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(savedFrame) }) else { return nil }
        return originClampedToScreen(origin, size: size, screen: screen)
    }

    private func originClampedToScreen(_ origin: NSPoint, size: NSSize, screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
    }

    private func savePanelOrigin() {
        UserDefaults.standard.set(Double(panel.frame.minX), forKey: "windowX")
        UserDefaults.standard.set(Double(panel.frame.minY), forKey: "windowY")
    }

    private func beginDragging() {
        isDraggingPet = true
        activeAction = nil
        actionIsAmbient = false
        dragFrameIndex = 0
        lastDragFrameAt = .distantPast
        imageView.frame.origin.x = 54
    }

    private func dragMoved(dx: CGFloat, dy: CGFloat) {
        dragDelta = NSPoint(x: dx, y: dy)
        showDragFrame(at: Date())
    }

    private func showDragFrame(at now: Date) {
        guard now.timeIntervalSince(lastDragFrameAt) >= 0.12 else { return }
        let vertical = abs(dragDelta.y) > abs(dragDelta.x) * 1.2
        let row = vertical ? 4 : (dragDelta.x < 0 ? 2 : 1)
        let count = vertical ? 5 : 8
        imageView.setAccessibilityLabel(vertical ? "小纳西妲，拖动时轻跳" : (row == 2 ? "小纳西妲，向左跑动" : "小纳西妲，向右跑动"))
        showFrame(row: row, column: dragFrameIndex % count)
        dragFrameIndex += 1
        lastDragFrameAt = now
    }

    private func endDragging() {
        isDraggingPet = false
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
        if let screen {
            panel.setFrameOrigin(originClampedToScreen(panel.frame.origin, size: panel.frame.size, screen: screen))
        }
        savePanelOrigin()
        imageView.setAccessibilityLabel("小纳西妲，拖动完成后轻跳")
        startAction(.hop)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌿"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "和小纳西妲说话", action: #selector(sayHello), keyEquivalent: "h"))
        let originalItem = NSMenuItem(title: "听听原声片段", action: nil, keyEquivalent: "")
        let originalMenu = NSMenu()
        for clip in OriginalClip.allCases {
            let item = NSMenuItem(title: clip.title, action: #selector(playOriginalClipMenu(_:)), keyEquivalent: "")
            item.representedObject = clip.rawValue
            item.target = self
            originalMenu.addItem(item)
        }
        originalItem.submenu = originalMenu
        menu.addItem(originalItem)
        menu.addItem(NSMenuItem(title: "试听系统朗读", action: #selector(previewVoice), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "今日小建议", action: #selector(showTip), keyEquivalent: "t"))
        let actionItem = NSMenuItem(title: "看看小动作", action: nil, keyEquivalent: "")
        let actionMenu = NSMenu()
        for action in PetAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(playMenuAction(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.target = self
            actionMenu.addItem(item)
        }
        actionItem.submenu = actionMenu
        menu.addItem(actionItem)
        menu.addItem(NSMenuItem(title: "安静一小时", action: #selector(snooze), keyEquivalent: "s"))
        menu.addItem(.separator())
        speechItem = NSMenuItem(title: "语音", action: #selector(toggleSpeech), keyEquivalent: "")
        systemReadingItem = NSMenuItem(title: "系统朗读提醒与文字", action: #selector(toggleSystemReading), keyEquivalent: "")
        reminderItem = NSMenuItem(title: "温和提醒", action: #selector(toggleReminders), keyEquivalent: "")
        speechItem.state = speechEnabled ? .on : .off
        systemReadingItem.state = systemReadingEnabled ? .on : .off
        reminderItem.state = remindersEnabled ? .on : .off
        menu.addItem(speechItem)
        menu.addItem(systemReadingItem)
        menu.addItem(reminderItem)
        menu.addItem(NSMenuItem(title: "显示／隐藏", action: #selector(toggleWindow), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "重置宠物位置", action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func showFrame(row: Int, column: Int) {
        if let frame = atlas.frame(row: row, column: column) { imageView.image = frame }
    }

    private func startAction(_ action: PetAction, at now: Date = Date(), ambient: Bool = false) {
        activeAction = action
        actionIsAmbient = ambient
        actionStartedAt = now
        nextAmbientAt = now.addingTimeInterval(Double.random(in: 55...100))
    }

    private func showAction(_ action: PetAction, at now: Date) -> Bool {
        let steps = action.steps
        let index = Int(now.timeIntervalSince(actionStartedAt) / action.frameDuration)
        guard index < steps.count else {
            activeAction = nil
            actionIsAmbient = false
            imageView.frame.origin.x = 54
            imageView.setAccessibilityLabel("小纳西妲，待机")
            return false
        }
        let step = steps[index]
        imageView.frame.origin.x = 54 + step.offsetX
        showFrame(row: step.row, column: step.column)
        return true
    }

    @objc private func tick() {
        let now = Date()
        if !bubble.isHidden && now >= bubbleEndsAt { bubble.isHidden = true }
        if isDraggingPet {
            showDragFrame(at: now)
            return
        }
        let cursor = NSEvent.mouseLocation
        if hypot(cursor.x - lastCursor.x, cursor.y - lastCursor.y) >= 2 {
            lastCursor = cursor
            lastCursorMoveAt = now
        }

        let idle = idleSeconds()
        if let action = activeAction {
            if actionIsAmbient && idle < 2 {
                activeAction = nil
                actionIsAmbient = false
                imageView.frame.origin.x = 54
            } else if showAction(action, at: now) {
                return
            }
        }

        if idle >= 30, now >= nextAmbientAt, now >= snoozeUntil, bubble.isHidden {
            let hour = Calendar.current.component(.hour, from: now)
            let choices: [PetAction] = (hour >= 23 || hour < 8)
                ? [.nap, .curious]
                : [.wave, .hop, .cuddle, .curious, .stroll, .focus, .celebrate, .nap]
            if let action = choices.randomElement() {
                startAction(action, at: now, ambient: true)
                _ = showAction(action, at: now)
                return
            }
        }

        imageView.frame.origin.x = 54
        let head = NSPoint(x: panel.frame.minX + 150, y: panel.frame.minY + 154)
        if now.timeIntervalSince(lastCursorMoveAt) < 2.2 {
            let degrees = (atan2(cursor.x - head.x, cursor.y - head.y) * 180 / .pi + 360)
                .truncatingRemainder(dividingBy: 360)
            let direction = Int((degrees / 22.5).rounded()) % 16
            if direction < 8 { showFrame(row: 9, column: direction) }
            else { showFrame(row: 10, column: direction - 8) }
        } else {
            let hour = Calendar.current.component(.hour, from: now)
            if (hour >= 23 || hour < 8) && idle > 300 {
                showFrame(row: 0, column: 2)
            } else {
                showFrame(row: 0, column: (frameIndex / 3) % 6)
                frameIndex = (frameIndex + 1) % 18
            }
        }
    }

    private func showBubble(_ message: String, action: PetAction) {
        bubbleLabel.stringValue = message
        bubble.isHidden = false
        bubbleEndsAt = Date().addingTimeInterval(8)
        startAction(action)
        panel.orderFrontRegardless()
    }

    private func originalClipURL(_ clip: OriginalClip) -> URL? {
        let environment = ProcessInfo.processInfo.environment["NAHIDA_VOICE_DIR"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Voice", isDirectory: true)
        let personal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets/nahida-companion/voice", isDirectory: true)
        for directory in [environment, bundled, personal].compactMap({ $0 }) {
            let url = directory.appendingPathComponent("\(clip.rawValue).m4a")
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    private func cancelDialogue() {
        dialogueTimer?.invalidate()
        dialogueTimer = nil
        pendingDialogue = nil
    }

    @discardableResult private func playOriginalClip(_ clip: OriginalClip) -> Bool {
        guard let url = originalClipURL(clip) else { return false }
        cancelDialogue()
        speaker.stopSpeaking(at: .immediate)
        originalPlayer?.stop()
        showBubble(clip.caption, action: clip.action)
        guard speechEnabled else { return true }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            originalPlayer = player
            return player.play()
        } catch {
            showBubble("原声片段暂时无法播放。", action: .curious)
            return false
        }
    }

    @discardableResult private func playDialogue(
        clip: OriginalClip, then text: String, action: PetAction = .cuddle
    ) -> Bool {
        guard playOriginalClip(clip) else { return false }
        guard speechEnabled, let duration = originalPlayer?.duration else {
            say(text, speak: false, action: action)
            return true
        }
        pendingDialogue = (text, action)
        let timer = Timer(timeInterval: duration + 0.15, target: self,
                          selector: #selector(finishDialogue), userInfo: nil, repeats: false)
        dialogueTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    @objc private func finishDialogue() {
        guard let next = pendingDialogue else { return }
        cancelDialogue()
        say(next.text, action: next.action)
    }

    private func say(_ message: String, speak: Bool = true, action: PetAction = .wave, preview: Bool = false) {
        cancelDialogue()
        originalPlayer?.stop()
        showBubble(message, action: action)
        if speak && speechEnabled && (systemReadingEnabled || preview) {
            speaker.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: message)
            let preferred = AVSpeechSynthesisVoice(identifier: "com.apple.siri.natural.Linfei")
            let fallback = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.zh-CN.Tingting")
            utterance.voice = preferred ?? fallback ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.pitchMultiplier = 1.0
            utterance.rate = 0.48
            speaker.speak(utterance)
        }
    }

    private func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    @objc private func checkReminders() {
        guard remindersEnabled, Date() >= snoozeUntil else { return }
        let now = Date()
        for reminder in Reminder.allCases {
            if let interval = reminder.interval {
                let last = lastReminderAt[reminder] ?? now
                if lastReminderAt[reminder] == nil { lastReminderAt[reminder] = now }
                if now.timeIntervalSince(last) >= interval && !pending.contains(reminder) {
                    pending.append(reminder)
                    lastReminderAt[reminder] = now
                }
            }
        }
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        let today = DateFormatter.localizedString(from: now, dateStyle: .short, timeStyle: .none)
        for (reminder, due) in [(Reminder.caffeine, hour >= 14),
                                (Reminder.sleep, hour > 22 || (hour == 22 && minute >= 30))] {
            if due && lastDailyKey[reminder] != today && !pending.contains(reminder) {
                pending.append(reminder)
                lastDailyKey[reminder] = today
            }
        }
        guard idleSeconds() >= 30, pendingDialogue == nil,
              originalPlayer?.isPlaying != true, !pending.isEmpty,
              now.timeIntervalSince(lastDeliveredAt) >= 15 * 60 else { return }
        let next = pending.removeFirst()
        pending.removeAll()
        lastDeliveredAt = now
        let quietHours = hour < 9 || hour >= 21
        let action: PetAction = next == .sleep ? .nap : .wave
        let canUseOriginal = !quietHours && speechEnabled &&
            now.timeIntervalSince(lastAutomaticVoiceAt) >= 60 * 60
        let clip: OriginalClip = next == .move ? .celebrate : .greeting
        if canUseOriginal && playDialogue(clip: clip, then: next.text, action: action) {
            lastAutomaticVoiceAt = now
        } else {
            say(next.text, speak: !quietHours, action: action)
        }
    }

    @objc private func petTapped() {
        let comforts = [
            "我在呢。忙完这一阵，就一起伸个懒腰吧。",
            "先松松肩膀，好吗？我会安静陪着你。",
            "今天的好奇心也辛苦啦，停一会儿也没关系。",
            "要不要看一眼窗外？我陪你发会儿呆。",
            "揉揉眼睛之前，先试着多眨几下眼吧。"
        ]
        let comfort = comforts.randomElement() ?? comforts[0]
        let clip = [OriginalClip.greeting, .celebrate].randomElement() ?? .greeting
        if !playDialogue(clip: clip, then: comfort) {
            say(comfort, action: [.wave, .hop, .cuddle, .curious].randomElement() ?? .wave)
        }
    }
    @objc private func sayHello() {
        if !playDialogue(clip: .greeting, then: "你好呀，我会安静陪着你。") {
            say("你好呀，我会安静陪着你。")
        }
    }
    @objc private func playOriginalClipMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let clip = OriginalClip(rawValue: name) else { return }
        if !playOriginalClip(clip) {
            say("还没有安装本地原声片段。请查看 README 的语音安装说明。", speak: false, action: .curious)
        }
    }
    @objc private func previewVoice() {
        say("嘿嘿，我在这里呀。今天也要好好照顾自己哦。", action: .cuddle, preview: true)
    }
    @objc private func playMenuAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let action = PetAction(rawValue: name) else { return }
        startAction(action)
    }
    @objc private func showTip() {
        let tips = [
            "抬头看看屏幕的位置，肩膀放松，手腕自然地放平。",
            "小纸条：这周找两天练练力量，也留点时间散步。",
            "夜晚也要留给梦。成年人通常需要至少七小时睡眠。",
            "眼睛也会累呀。看看远处，再轻轻眨眨眼。",
            "代码可以慢慢写，我们先起身走动两分钟。",
            "今天若有空，出去走走、晒晒自然光吧。",
            "给脑袋留一点离线时间，灵感也许会悄悄回来。",
            "手腕或腰背一直疼的话，记得找专业人士看看。"
        ]
        let tip = tips.randomElement() ?? tips[0]
        if !playDialogue(clip: .greeting, then: tip, action: .wave) { say(tip) }
    }
    @objc private func snooze() {
        snoozeUntil = Date().addingTimeInterval(60 * 60)
        pending.removeAll()
        say("好，我会安静陪你一小时。", speak: false)
    }
    @objc private func toggleSpeech() {
        speechEnabled.toggle()
        speechItem.state = speechEnabled ? .on : .off
        UserDefaults.standard.set(speechEnabled, forKey: "speechEnabled")
        if !speechEnabled {
            speaker.stopSpeaking(at: .immediate)
            originalPlayer?.stop()
            finishDialogue()
        }
    }
    @objc private func toggleSystemReading() {
        systemReadingEnabled.toggle()
        systemReadingItem.state = systemReadingEnabled ? .on : .off
        UserDefaults.standard.set(systemReadingEnabled, forKey: "systemReadingEnabled")
        if !systemReadingEnabled { speaker.stopSpeaking(at: .immediate) }
    }
    @objc private func toggleReminders() {
        remindersEnabled.toggle()
        reminderItem.state = remindersEnabled ? .on : .off
        UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled")
        if !remindersEnabled { pending.removeAll() }
    }
    @objc private func toggleWindow() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    @objc private func resetPosition() {
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        savePanelOrigin()
        panel.orderFrontRegardless()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
private let companion = Companion()
app.delegate = companion
app.run()
