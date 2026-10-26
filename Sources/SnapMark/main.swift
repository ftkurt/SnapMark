import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var captureHotKey: EventHotKeyRef?
    private var screenHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var coordinator: CaptureCoordinator?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusIcon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnapMark")
        statusIcon?.isTemplate = true
        statusItem.button?.image = statusIcon
        let menu = NSMenu()
        let captureItem = menu.addItem(withTitle: "Capture Region    ⌘⇧2", action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        captureItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil)
        let screenItem = menu.addItem(withTitle: "Save Current Screen to Desktop    ⌘⇧1", action: #selector(saveCurrentScreen), keyEquivalent: "")
        screenItem.target = self
        screenItem.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit SnapMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        statusItem.menu = menu
        registerHotKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        capture()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.cancel()
    }

    @objc private func capture() {
        coordinator?.cancel()
        coordinator = CaptureCoordinator { [weak self] in self?.coordinator = nil }
        coordinator?.begin()
    }

    @objc private func saveCurrentScreen() {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            presentScreenPermissionAlert(); return
        }
        guard let savedURL = ScreenSaver.saveCurrentScreenToDesktop() else {
            showAlert("Screenshot failed", "SnapMark could not save the current screen.")
            return
        }
        NSSound(named: "Glass")?.play()
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Screenshot saved")
        statusItem.button?.toolTip = "Saved \(savedURL.lastPathComponent)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnapMark")
            icon?.isTemplate = true
            self?.statusItem.button?.image = icon
            self?.statusItem.button?.toolTip = "SnapMark"
        }
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            if identifier.id == 1 || identifier.id == 2 {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    if identifier.id == 1 { delegate.capture() }
                    else { delegate.saveCurrentScreen() }
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        let identifier = EventHotKeyID(signature: OSType(0x534E4150), id: 1) // SNAP
        RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), identifier,
                            GetApplicationEventTarget(), 0, &captureHotKey)
        let screenIdentifier = EventHotKeyID(signature: OSType(0x534E4150), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_1), UInt32(cmdKey | shiftKey), screenIdentifier,
                            GetApplicationEventTarget(), 0, &screenHotKey)
    }
}

@MainActor
enum ScreenSaver {
    static func saveCurrentScreenToDesktop() -> URL? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let image = CGDisplayCreateImage(displayID) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "SnapMark \(formatter.string(from: Date())).png"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent(name)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try data.write(to: url, options: .atomic); return url }
        catch { return nil }
    }
}

@MainActor
final class CaptureCoordinator {
    private var overlays: [NSWindow] = []
    private var editor: NSWindowController?
    private var selectionSession: SelectionSession?
    private let finished: () -> Void

    init(finished: @escaping () -> Void) { self.finished = finished }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            presentScreenPermissionAlert(); finished(); return
        }
        guard let snapshot = DesktopSnapshot.capture() else {
            showAlert("Capture failed", "SnapMark could not read the displays."); finished(); return
        }
        let session = SelectionSession(snapshot: snapshot) { [weak self] image in
            guard let self else { return }
            self.overlays.forEach { $0.orderOut(nil) }
            self.overlays.removeAll()
            self.selectionSession = nil
            NSApp.deactivate()
            guard let image else { self.finished(); return }
            let editor = EditorWindowController(image: image) { [weak self] in
                self?.editor = nil
                self?.finished()
            }
            self.editor = editor
            editor.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        selectionSession = session
        session.startSafetyControls()
        overlays = NSScreen.screens.map { SelectionWindow(screen: $0, session: session) }
        overlays.forEach { $0.orderFront(nil) }
        overlays.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() {
        selectionSession?.cancel()
        selectionSession = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        editor?.close()
        editor = nil
    }
}

@MainActor
private func presentScreenPermissionAlert() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Screen Recording permission required"
    alert.informativeText = "Enable SnapMark in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen it."
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn,
       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private func showAlert(_ title: String, _ message: String) {
    let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.runModal()
}

@MainActor
struct DesktopSnapshot {
    let image: NSImage
    let frame: NSRect

    static func capture() -> DesktopSnapshot? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let union = screens.reduce(NSRect.null) { $0.union($1.frame) }
        let image = NSImage(size: union.size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else { return nil }
        context.interpolationQuality = .high
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let cgImage = CGDisplayCreateImage(number) else { continue }
            let target = NSRect(x: screen.frame.minX - union.minX, y: screen.frame.minY - union.minY,
                                width: screen.frame.width, height: screen.frame.height)
            // NSImage understands a display CGImage's native top-left pixel
            // orientation. Drawing the CGImage directly into AppKit's y-up
            // context required a manual transform and caused a double flip.
            let displayImage = NSImage(cgImage: cgImage, size: screen.frame.size)
            displayImage.draw(in: target, from: NSRect(origin: .zero, size: screen.frame.size),
                              operation: .copy, fraction: 1,
                              respectFlipped: false,
                              hints: [.interpolation: NSImageInterpolation.high])
        }
        return DesktopSnapshot(image: image, frame: union)
    }
}

final class SelectionWindow: NSWindow {
    private let session: SelectionSession

    init(screen: NSScreen, session: SelectionSession) {
        self.session = session
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Floating stays above normal apps but below the menu bar, leaving the
        // SnapMark status menu reachable as an emergency exit.
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        contentView = SelectionView(screenFrame: screen.frame, session: session)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { session.cancel() }
}

@MainActor
final class SelectionSession {
    let snapshot: DesktopSnapshot
    private let completion: (NSImage?) -> Void
    private(set) var start: NSPoint?
    private(set) var current: NSPoint?
    private var views: [WeakSelectionView] = []
    private var isFinished = false
    private var eventMonitor: Any?
    private var timeoutWorkItem: DispatchWorkItem?

    init(snapshot: DesktopSnapshot, completion: @escaping (NSImage?) -> Void) {
        self.snapshot = snapshot; self.completion = completion
    }

    func register(_ view: SelectionView) { views.append(WeakSelectionView(view)) }

    func startSafetyControls() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            guard let self, !self.isFinished else { return event }
            if event.type == .rightMouseDown {
                self.cancel(); return nil
            }
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if event.keyCode == UInt16(kVK_Escape) || (command && event.charactersIgnoringModifiers == ".") {
                self.cancel(); return nil
            }
            if command && event.charactersIgnoringModifiers?.lowercased() == "q" {
                self.cancel()
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return nil
            }
            return event
        }
        let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
    }

    func begin(at point: NSPoint) { start = point; current = point; refresh() }
    func update(to point: NSPoint) { current = point; refresh() }

    var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        cleanupSafetyControls()
        guard let rect = selection, rect.width >= 2, rect.height >= 2,
              let cg = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil); return
        }
        let local = NSRect(x: rect.minX - snapshot.frame.minX, y: rect.minY - snapshot.frame.minY,
                           width: rect.width, height: rect.height)
        let scaleX = CGFloat(cg.width) / snapshot.frame.width
        let scaleY = CGFloat(cg.height) / snapshot.frame.height
        let crop = CGRect(x: local.minX * scaleX,
                          y: (snapshot.frame.height - local.maxY) * scaleY,
                          width: local.width * scaleX, height: local.height * scaleY).integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !crop.isNull, let cropped = cg.cropping(to: crop) else { completion(nil); return }
        completion(NSImage(cgImage: cropped, size: rect.size))
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanupSafetyControls()
        completion(nil)
    }
    private func cleanupSafetyControls() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        timeoutWorkItem?.cancel(); timeoutWorkItem = nil
    }
    private func refresh() { views = views.filter { $0.value != nil }; views.forEach { $0.value?.needsDisplay = true } }
}

@MainActor
private final class WeakSelectionView {
    weak var value: SelectionView?
    init(_ value: SelectionView) { self.value = value }
}

final class SelectionView: NSView {
    private let screenFrame: NSRect
    private let session: SelectionSession

    init(screenFrame: NSRect, session: SelectionSession) {
        self.screenFrame = screenFrame; self.session = session
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        session.register(self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawScreenImage()
        NSColor.black.withAlphaComponent(0.38).setFill(); bounds.fill()
        drawCancelButton()
        guard let globalSelection = session.selection else {
            drawHint("Drag to select • Esc / ⌘. / right-click to cancel", at: NSPoint(x: bounds.midX, y: bounds.midY)); return
        }
        let localSelection = globalSelection.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: localSelection).addClip()
        drawScreenImage()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: localSelection); border.lineWidth = 1.5; border.stroke()
        let labelPoint = NSPoint(x: globalSelection.midX, y: globalSelection.minY - 24)
        if screenFrame.contains(labelPoint) {
            drawHint("\(Int(globalSelection.width)) × \(Int(globalSelection.height))",
                     at: NSPoint(x: labelPoint.x - screenFrame.minX, y: labelPoint.y - screenFrame.minY))
        }
    }

    private func drawScreenImage() {
        let source = NSRect(x: screenFrame.minX - session.snapshot.frame.minX,
                            y: screenFrame.minY - session.snapshot.frame.minY,
                            width: screenFrame.width, height: screenFrame.height)
        session.snapshot.image.draw(in: bounds, from: source, operation: .copy, fraction: 1)
    }

    private func globalPoint(for event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
    private var cancelRect: NSRect { NSRect(x: bounds.maxX - 132, y: bounds.maxY - 48, width: 116, height: 32) }
    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if cancelRect.contains(local) { session.cancel(); return }
        session.begin(at: globalPoint(for: event))
    }
    override func mouseDragged(with event: NSEvent) { session.update(to: globalPoint(for: event)) }
    override func mouseUp(with event: NSEvent) {
        session.update(to: globalPoint(for: event)); session.finish()
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { session.cancel() } else { super.keyDown(with: event) } }
    override func rightMouseDown(with event: NSEvent) { session.cancel() }

    private func drawCancelButton() {
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: cancelRect, xRadius: 9, yRadius: 9).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
        let value = NSAttributedString(string: "Cancel  Esc", attributes: attrs)
        value.draw(at: NSPoint(x: cancelRect.midX - value.size().width / 2,
                               y: cancelRect.midY - value.size().height / 2))
    }

    private func drawHint(_ text: String, at point: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)]
        let value = NSAttributedString(string: "  \(text)  ", attributes: attrs)
        value.draw(at: NSPoint(x: point.x - value.size().width / 2, y: point.y - value.size().height / 2))
    }
}

enum Tool: Int { case pen, rectangle, ellipse, arrow }
enum Mark {
    case path([NSPoint], NSColor)
    case shape(Tool, NSPoint, NSPoint, NSColor)
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationView
    private let completion: () -> Void

    init(image: NSImage, completion: @escaping () -> Void) {
        self.canvas = AnnotationView(image: image); self.completion = completion
        let contentSize = NSSize(width: max(520, min(image.size.width, 1200)), height: max(360, min(image.size.height, 800)) + 52)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "SnapMark"; window.center(); window.minSize = NSSize(width: 500, height: 350)
        super.init(window: window); window.delegate = self
        buildUI(in: window.contentView!)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(in root: NSView) {
        let toolbar = NSStackView(); toolbar.orientation = .horizontal; toolbar.spacing = 8; toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        toolbar.translatesAutoresizingMaskIntoConstraints = false; canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar); root.addSubview(canvas)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor), toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 52),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor), canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor), canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        [("scribble", Tool.pen), ("rectangle", .rectangle), ("circle", .ellipse), ("arrow.up.right", .arrow)].forEach { symbol, tool in
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: self, action: #selector(selectTool(_:)))
            button.tag = tool.rawValue; button.toolTip = String(describing: tool).capitalized; toolbar.addArrangedSubview(button)
        }
        let color = NSColorWell(); color.color = .systemRed; color.target = self; color.action = #selector(changeColor(_:)); toolbar.addArrangedSubview(color)
        let undo = NSButton(title: "Undo", target: self, action: #selector(undoMark)); toolbar.addArrangedSubview(undo)
        toolbar.addArrangedSubview(NSView())
        let copy = NSButton(title: "Copy & Close", target: self, action: #selector(copyAndClose)); copy.keyEquivalent = "\r"; copy.bezelStyle = .rounded; toolbar.addArrangedSubview(copy)
    }

    @objc private func selectTool(_ sender: NSButton) { canvas.tool = Tool(rawValue: sender.tag) ?? .pen }
    @objc private func changeColor(_ sender: NSColorWell) { canvas.color = sender.color }
    @objc private func undoMark() { canvas.undo() }
    @objc private func copyAndClose() {
        let result = canvas.render()
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([result])
        window?.close()
    }
    func windowWillClose(_ notification: Notification) { completion() }
}

final class AnnotationView: NSView {
    let image: NSImage
    var tool: Tool = .pen
    var color: NSColor = .systemRed
    private var marks: [Mark] = []
    private var draft: Mark?

    init(image: NSImage) { self.image = image; super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }

    private var imageRect: NSRect {
        let margin: CGFloat = 12, area = bounds.insetBy(dx: margin, dy: margin)
        let scale = min(area.width / image.size.width, area.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        image.draw(in: imageRect)
        for mark in marks { draw(mark) }
        if let draft { draw(draft) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = clamped(convert(event.locationInWindow, from: nil))
        draft = tool == .pen ? .path([p], color) : .shape(tool, p, p, color); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let p = clamped(convert(event.locationInWindow, from: nil))
        switch draft {
        case let .path(points, c): draft = .path(points + [p], c)
        case let .shape(t, start, _, c): draft = .shape(t, start, p, c)
        case nil: break
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); if let draft { marks.append(draft) }; draft = nil; needsDisplay = true }
    func undo() { _ = marks.popLast(); needsDisplay = true }

    private func clamped(_ p: NSPoint) -> NSPoint { NSPoint(x: min(max(p.x, imageRect.minX), imageRect.maxX), y: min(max(p.y, imageRect.minY), imageRect.maxY)) }

    private func draw(_ mark: Mark) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        switch mark {
        case let .path(points, color):
            guard let first = points.first else { return }
            color.setStroke(); let path = NSBezierPath(); path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.move(to: first)
            points.dropFirst().forEach { path.line(to: $0) }; path.stroke()
        case let .shape(tool, start, end, color):
            color.setStroke(); color.setFill(); let path = NSBezierPath(); path.lineWidth = 3
            let rect = NSRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
            if tool == .rectangle { path.appendRect(rect); path.stroke() }
            else if tool == .ellipse { path.appendOval(in: rect); path.stroke() }
            else if tool == .arrow {
                path.move(to: start); path.line(to: end); path.stroke()
                let angle = atan2(end.y-start.y, end.x-start.x), length: CGFloat = 14
                let head = NSBezierPath(); head.move(to: end)
                head.line(to: NSPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
                head.line(to: NSPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
                head.close(); head.fill()
            }
        }
    }

    func render() -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus(); image.draw(in: NSRect(origin: .zero, size: image.size))
        let scale = image.size.width / imageRect.width
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.scale(by: scale); transform.translateX(by: -imageRect.minX, yBy: -imageRect.minY); transform.concat()
        marks.forEach(draw)
        NSGraphicsContext.restoreGraphicsState(); output.unlockFocus(); return output
    }
}
