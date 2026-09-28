import AppKit
import AVFoundation
import CoreGraphics

private let cellWidth = 192
private let cellHeight = 208

private enum PetState {
    case idle
    case waving
    case looking(Int)
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

@MainActor private final class Companion: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var imageView: NSImageView!
    private var bubble: NSView!
    private var bubbleLabel: NSTextField!
    private var statusItem: NSStatusItem!
    private var speechItem: NSMenuItem!
    private var reminderItem: NSMenuItem!
    private var atlas: SpriteAtlas!
    private let speaker = AVSpeechSynthesizer()
    private var state: PetState = .idle
    private var frameIndex = 0
    private var stateEndsAt = Date.distantPast
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
        remindersEnabled = UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool ?? true
        buildPanel()
        buildMenu()
        panel.orderFrontRegardless()
        showFrame(row: 0, column: 0)
        frameTimer = Timer.scheduledTimer(timeInterval: 0.16, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
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
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        panel.contentView = root

        imageView = NSImageView(frame: NSRect(x: 54, y: 0, width: 192, height: 208))
        imageView.imageScaling = .scaleNone
        imageView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(petTapped)))
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

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌿"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "和小纳西妲说话", action: #selector(sayHello), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "今日小建议", action: #selector(showTip), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "安静一小时", action: #selector(snooze), keyEquivalent: "s"))
        menu.addItem(.separator())
        speechItem = NSMenuItem(title: "语音", action: #selector(toggleSpeech), keyEquivalent: "")
        reminderItem = NSMenuItem(title: "温和提醒", action: #selector(toggleReminders), keyEquivalent: "")
        speechItem.state = speechEnabled ? .on : .off
        reminderItem.state = remindersEnabled ? .on : .off
        menu.addItem(speechItem)
        menu.addItem(reminderItem)
        menu.addItem(NSMenuItem(title: "显示／隐藏", action: #selector(toggleWindow), keyEquivalent: "p"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func showFrame(row: Int, column: Int) {
        if let frame = atlas.frame(row: row, column: column) { imageView.image = frame }
    }

    @objc private func tick() {
        let now = Date()
        if !bubble.isHidden && now >= bubbleEndsAt { bubble.isHidden = true }
        let cursor = NSEvent.mouseLocation
        if hypot(cursor.x - lastCursor.x, cursor.y - lastCursor.y) >= 2 {
            lastCursor = cursor
            lastCursorMoveAt = now
        }

        if case .waving = state, now < stateEndsAt {
            showFrame(row: 3, column: min(frameIndex, 3))
            frameIndex = (frameIndex + 1) % 4
            return
        }

        let head = NSPoint(x: panel.frame.minX + 150, y: panel.frame.minY + 154)
        if now.timeIntervalSince(lastCursorMoveAt) < 2.2 {
            let degrees = (atan2(cursor.x - head.x, cursor.y - head.y) * 180 / .pi + 360)
                .truncatingRemainder(dividingBy: 360)
            let direction = Int((degrees / 22.5).rounded()) % 16
            state = .looking(direction)
            if direction < 8 { showFrame(row: 9, column: direction) }
            else { showFrame(row: 10, column: direction - 8) }
        } else {
            state = .idle
            let hour = Calendar.current.component(.hour, from: now)
            if (hour >= 23 || hour < 8) && now.timeIntervalSince(lastCursorMoveAt) > 300 {
                showFrame(row: 0, column: 2)
            } else {
                showFrame(row: 0, column: (frameIndex / 3) % 6)
                frameIndex = (frameIndex + 1) % 18
            }
        }
    }

    private func say(_ message: String, speak: Bool = true) {
        bubbleLabel.stringValue = message
        bubble.isHidden = false
        bubbleEndsAt = Date().addingTimeInterval(8)
        state = .waving
        stateEndsAt = Date().addingTimeInterval(0.8)
        frameIndex = 0
        panel.orderFrontRegardless()
        if speak && speechEnabled {
            speaker.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: message)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
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
        guard idleSeconds() >= 30, !pending.isEmpty,
              now.timeIntervalSince(lastDeliveredAt) >= 15 * 60 else { return }
        let next = pending.removeFirst()
        pending.removeAll()
        lastDeliveredAt = now
        let quietHours = hour < 9 || hour >= 21
        say(next.text, speak: !quietHours)
    }

    @objc private func petTapped() {
        let comforts = [
            "我在呢。工作累了就休息一下吧。",
            "先松松肩膀，好吗？我会在这里陪你。",
            "你已经很努力啦，停一会儿也没关系。",
            "要不要看一眼窗外？我陪你发会儿呆。"
        ]
        say(comforts.randomElement() ?? comforts[0])
    }
    @objc private func sayHello() { say("你好呀，我会安静陪着你。") }
    @objc private func showTip() {
        let tips = [
            "让屏幕处在舒适高度，肩膀放松，手腕尽量保持自然。",
            "这周可以找两天做力量训练，也别忘了走走路。",
            "成年人通常需要每晚至少七小时睡眠；规律作息也很重要。",
            "屏幕看久了，看看远处、眨眨眼。",
            "写代码时留意坐姿，隔一会儿起身活动。",
            "今天出门走走、晒晒自然光，也许会舒服些。",
            "给自己安排一点离线时间，让大脑休息一下。",
            "如果手腕或腰背持续疼痛，尽早请专业人士评估。"
        ]
        say(tips.randomElement() ?? tips[0])
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
        if !speechEnabled { speaker.stopSpeaking(at: .immediate) }
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
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
private let companion = Companion()
app.delegate = companion
app.run()
