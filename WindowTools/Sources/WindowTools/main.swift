import Cocoa
import Carbon
import ScreenCaptureKit
import AVFoundation

// Window mirroring is adapted from PinWindow by justwy (MIT License).
// See THIRD-PARTY-LICENSES/PinWindow.txt.

// MARK: - Screen Capture Manager

class CaptureManager: NSObject, SCStreamDelegate, SCStreamOutput {
    let videoLayer = AVSampleBufferDisplayLayer()
    private let captureQueue = DispatchQueue(
        label: "ai.vernir.windowtools.capture",
        qos: .userInteractive
    )
    private var stream: SCStream?
    var capturing = false
    var onError: (() -> Void)?

    func startCapture(window: SCWindow) async throws {
        if stream != nil { return }
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 2

        let filter = SCContentFilter(desktopIndependentWindow: window)
        // One captured pixel per screen point is sufficient for a utility
        // mirror and avoids four times the pixel work on Retina displays.
        config.width = max(1, Int(filter.contentRect.width))
        config.height = max(1, Int(filter.contentRect.height))

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream?.startCapture()
        capturing = true
    }

    func stopCapture() {
        guard let s = stream else { return }
        s.stopCapture { _ in }
        stream = nil
        capturing = false
    }

    func updateCaptureSize(width: Int, height: Int) {
        guard let s = stream else { return }
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 2
        config.width = width
        config.height = height
        s.updateConfiguration(config) { err in
            if let err = err { print("[warn] updateConfig: \(err)") }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard
            sampleBuffer.isValid,
            outputType == .screen,
            let attachmentArrays = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentArrays.first,
            let statusRawValue = attachments[.status] as? Int,
            SCFrameStatus(rawValue: statusRawValue) == .complete
        else {
            return
        }

        if #available(macOS 15, *) {
            // AVSampleBufferVideoRenderer supports background-thread enqueueing,
            // keeping live capture work off the app's UI thread.
            videoLayer.sampleBufferRenderer.enqueue(sampleBuffer)
        } else {
            DispatchQueue.main.async {
                self.videoLayer.enqueue(sampleBuffer)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[warn] capture stopped: \(error)")
        DispatchQueue.main.async {
            self.stream = nil
            self.capturing = false
            self.onError?()
        }
    }
}

// MARK: - Coordinate Transform

func cgToNS(_ cgRect: CGRect) -> NSRect {
    guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
        ?? NSScreen.main
        ?? NSScreen.screens.first
    else {
        return cgRect
    }
    return NSRect(x: cgRect.origin.x,
                  y: primary.frame.maxY - cgRect.origin.y - cgRect.height,
                  width: cgRect.width, height: cgRect.height)
}

// MARK: - Private API: _AXUIElementGetWindow

private let _AXUIElementGetWindow: @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError = {
    let handle = dlopen(nil, RTLD_NOW)!
    return unsafeBitCast(dlsym(handle, "_AXUIElementGetWindow"),
                         to: (@convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError).self)
}()

// MARK: - Mirror Panel

final class MirrorPanel: @unchecked Sendable {
    let scWindow: SCWindow
    let capture = CaptureManager()
    var panel: NSPanel!
    private var axObserver: AXObserver?
    private var aliveTimer: Timer?
    private var clickMonitor: Any?

    init(scWindow: SCWindow) {
        self.scWindow = scWindow

        let nsFrame = cgToNS(scWindow.frame)
        panel = NSPanel(contentRect: nsFrame,
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let view = NSView(frame: NSRect(origin: .zero, size: nsFrame.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true

        let videoLayer = capture.videoLayer
        videoLayer.frame = view.bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(videoLayer)

        panel.contentView = view

        capture.onError = { [weak self] in
            guard let self else { return }
            self.stop()
            PinManager.shared.unpinByWindowID(self.scWindow.windowID)
        }
    }

    @MainActor
    func start() async {
        panel.makeKeyAndOrderFront(nil)
        do {
            try await capture.startCapture(window: scWindow)
        } catch {
            print("[error] capture failed: \(error)")
            stop()
            return
        }
        startAXObserver()
        startClickMonitor()
        aliveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAlive()
        }
    }

    func stop() {
        aliveTimer?.invalidate()
        aliveTimer = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(obs),
                                  .defaultMode)
        }
        axObserver = nil
        capture.stopCapture()
        panel.close()
    }

    private func startAXObserver() {
        guard let pid = scWindow.owningApplication?.processID else { return }

        let axApp = AXUIElementCreateApplication(pid_t(pid))
        guard let axWin = findAXWindow(axApp: axApp) else {
            print("[warn] cannot find AX window for observer")
            return
        }

        typealias Callback = @convention(c) (AXObserver, AXUIElement, CFString, UnsafeMutableRawPointer?) -> Void
        let cb: Callback = { _, _, _, ptr in
            guard let ptr else { return }
            let mirror = Unmanaged<MirrorPanel>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { mirror.syncFrame() }
        }

        var obs: AXObserver?
        guard AXObserverCreate(pid_t(pid), cb, &obs) == .success, let observer = obs else { return }

        let ptr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, axWin, kAXWindowMovedNotification as CFString, ptr)
        AXObserverAddNotification(observer, axWin, kAXWindowResizedNotification as CFString, ptr)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
    }

    private func findAXWindow(axApp: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return nil }

        for win in windows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(win, &wid) == .success, wid == scWindow.windowID {
                return win
            }
        }
        return nil
    }

    func syncFrame() {
        guard
            let info = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                scWindow.windowID
            ) as? [[String: Any]],
            let first = info.first,
            let bounds = first[kCGWindowBounds as String] as? [String: Any],
            let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
            cgFrame.width > 1,
            cgFrame.height > 1
        else {
            return
        }
        let nsFrame = cgToNS(cgFrame)

        if panel.frame.size != nsFrame.size {
            capture.updateCaptureSize(
                width: max(1, Int(nsFrame.width)),
                height: max(1, Int(nsFrame.height))
            )
        }
        if panel.frame != nsFrame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(nsFrame, display: true)
            CATransaction.commit()
        }
    }

    private func checkAlive() {
        let exists = CGWindowListCopyWindowInfo([.optionIncludingWindow], scWindow.windowID) as? [[String: Any]]
        if exists?.isEmpty ?? true {
            PinManager.shared.unpinByWindowID(scWindow.windowID)
        }
    }

    private func startClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return }
            let mouseLocation = NSEvent.mouseLocation
            if panel.frame.contains(mouseLocation) {
                self.activateRealWindow()
            }
        }
    }

    private func activateRealWindow() {
        guard let bundleID = scWindow.owningApplication?.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
        // Also raise the specific window via Accessibility
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let axWin = findAXWindow(axApp: axApp) {
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        }
    }
}

// MARK: - Pin Manager

class PinManager {
    static let shared = PinManager()
    var mirrors: [MirrorPanel] = []
    var onPinChanged: (() -> Void)?

    func resyncAll() {
        for mirror in mirrors {
            mirror.syncFrame()
            mirror.panel.orderFrontRegardless()
        }
    }

    // Pin the frontmost window of the frontmost app
    func pinFrontmost() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            print("[warn] no frontmost app to pin")
            return
        }
        pinApp(pid: frontApp.processIdentifier, name: frontApp.localizedName ?? "?")
    }

    // Pin by app name (for CLI usage)
    func pinByName(_ appName: String) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }
        guard let app = apps.first else {
            print("No running app matching '\(appName)'.")
            return
        }
        pinApp(pid: app.processIdentifier, name: app.localizedName ?? appName)
    }

    func unpinByName(_ appName: String) {
        let matching = mirrors.filter {
            $0.scWindow.owningApplication?.applicationName.localizedCaseInsensitiveContains(appName) == true
        }
        if matching.isEmpty {
            print("No pinned window matching '\(appName)'.")
            return
        }
        for m in matching {
            let name = m.scWindow.owningApplication?.applicationName ?? "?"
            mirrors.removeAll { $0.scWindow.windowID == m.scWindow.windowID }
            m.stop()
            print("Unpinned '\(name)' (window \(m.scWindow.windowID))")
            showHUD("📍 \(name)")
        }
        onPinChanged?()
    }

    func unpinByWindowID(_ windowID: CGWindowID) {
        guard let idx = mirrors.firstIndex(where: { $0.scWindow.windowID == windowID }) else { return }
        let m = mirrors.remove(at: idx)
        let name = m.scWindow.owningApplication?.applicationName ?? "?"
        m.stop()
        print("Auto-unpinned '\(name)'")
        onPinChanged?()
    }

    func unpinLast() {
        guard let m = mirrors.last else {
            print("Nothing pinned.")
            return
        }
        let name = m.scWindow.owningApplication?.applicationName ?? "?"
        mirrors.removeLast()
        m.stop()
        print("Unpinned '\(name)'")
        showHUD("📍 \(name)")
        onPinChanged?()
    }

    func unpinAll() {
        if mirrors.isEmpty {
            print("Nothing pinned.")
            return
        }
        mirrors.forEach { $0.stop() }
        let count = mirrors.count
        mirrors.removeAll()
        print("Unpinned all (\(count) windows)")
        showHUD("📍 All unpinned")
        onPinChanged?()
    }

    func listPinned() {
        if mirrors.isEmpty {
            print("No pinned windows.")
            return
        }
        print("Pinned windows:")
        for m in mirrors {
            let name = m.scWindow.owningApplication?.applicationName ?? "?"
            print("  📌 \(name) (window \(m.scWindow.windowID))")
        }
    }

    // List all visible windows (for discovery)
    func listWindows(filter: String?) {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            print("Cannot get window list.")
            return
        }

        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
        }

        var rows: [(id: Int, owner: String, name: String)] = []
        for w in windowList {
            guard let wid = w[kCGWindowNumber as String] as? Int,
                  let owner = w[kCGWindowOwnerName as String] as? String else { continue }
            if let bounds = w[kCGWindowBounds as String] as? [String: Any] {
                let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
                let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
                if width < 50 || height < 50 { continue }
            }
            let name = w[kCGWindowName as String] as? String ?? "(untitled)"
            if let filter, !owner.localizedCaseInsensitiveContains(filter) { continue }
            rows.append((id: wid, owner: owner, name: name))
        }

        if rows.isEmpty {
            print("No windows found\(filter.map { " for '\($0)'" } ?? "").")
            return
        }

        print("\(pad("ID", 8))  \(pad("App", 22))  Window Title")
        print(String(repeating: "─", count: 65))
        for r in rows {
            print("\(pad("\(r.id)", 8))  \(pad(r.owner, 22))  \(String(r.name.prefix(32)))")
        }
    }

    /// Returns running apps that have visible windows, excluding ourselves and system agents.
    func runningAppsWithWindows() -> [NSRunningApplication] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // Collect PIDs that have at least one visible window of reasonable size
        var pidsWithWindows = Set<pid_t>()
        for w in windowList {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if let bounds = w[kCGWindowBounds as String] as? [String: Any] {
                let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
                let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
                if width < 50 || height < 50 { continue }
            }
            pidsWithWindows.insert(pid)
        }

        return NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != myPID &&
            app.activationPolicy == .regular &&
            pidsWithWindows.contains(app.processIdentifier)
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    func isPinned(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return mirrors.contains { $0.scWindow.owningApplication?.bundleIdentifier == bundleID }
    }

    func pinApp(pid: pid_t, name: String) {
        guard let scWindow = findFrontWindow(pid: pid) else {
            print("[error] cannot find window for '\(name)' (pid \(pid))")
            return
        }

        if mirrors.contains(where: { $0.scWindow.windowID == scWindow.windowID }) {
            print("'\(name)' is already pinned.")
            return
        }

        let m = MirrorPanel(scWindow: scWindow)
        mirrors.append(m)
        Task { await m.start() }

        print("Pinned '\(name)' (window \(scWindow.windowID))")
        showHUD("📌 \(name)")
        onPinChanged?()
    }

    private func findFrontWindow(pid: pid_t) -> SCWindow? {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        var axWindow: AXUIElement?

        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success, let w = ref {
            axWindow = (w as! AXUIElement)
        } else if AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &ref) == .success, let w = ref {
            axWindow = (w as! AXUIElement)
        } else if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let list = ref as? [AXUIElement], let first = list.first {
            axWindow = first
        }

        guard let axWin = axWindow else { return nil }

        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWin, &windowID) == .success, windowID != 0 else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var result: SCShareableContent?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, _ in
            result = content
            semaphore.signal()
        }
        semaphore.wait()

        return result?.windows.first(where: { $0.windowID == windowID })
    }

    private func showHUD(_ text: String) {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        w.isOpaque = false
        w.hasShadow = true
        w.center()
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.cornerRadius = 12

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = w.contentView!.bounds
        label.autoresizingMask = [.width, .height]
        w.contentView?.addSubview(label)
        w.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { w.close() }
    }
}

// MARK: - Global Hotkeys

private var hotKeyRefs: [EventHotKeyRef?] = []

private func installHotkeys() {
    var sig: OSType = 0
    for c in "PINW".utf8 { sig = (sig << 8) | OSType(c) }

    let keys: [(keyCode: UInt32, modifiers: UInt32, id: UInt32)] = [
        (0x23, UInt32(optionKey), 1),   // Option+P = pin frontmost
        (0x20, UInt32(optionKey), 2),   // Option+U = unpin last
        (0x2E, UInt32(controlKey | optionKey | cmdKey), 3), // Control+Option+Command+M
    ]

    for key in keys {
        let hkID = EventHotKeyID(signature: sig, id: key.id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(key.keyCode, key.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }

    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
        var hkID = EventHotKeyID()
        GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
        DispatchQueue.main.async {
            switch hkID.id {
            case 1: PinManager.shared.pinFrontmost()
            case 2: PinManager.shared.unpinLast()
            case 3: minimizeAllWindows()
            default: break
            }
        }
        return noErr
    }, 1, &spec, nil, nil)
}

@MainActor
private func minimizeAllWindows() {
    guard AXIsProcessTrusted() else { return }

    for application in NSWorkspace.shared.runningApplications where
        application.activationPolicy == .regular && !application.isHidden
    {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &value
            ) == .success,
            let windows = value as? [AXUIElement]
        else {
            continue
        }

        for window in windows {
            AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            )
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var minimizeStatusItem: NSStatusItem?
    let statusMenu = NSMenu()
    let cliArgs: [String]
    var lastFocusedApplication: NSRunningApplication?

    init(cliArgs: [String]) {
        self.cliArgs = cliArgs
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastFocusedApplication = application
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayConfigurationChanged(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Request Accessibility
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        // Request Screen Recording
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { _, _ in }

        // Watch for app termination to auto-unpin
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notif in
            if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let toRemove = PinManager.shared.mirrors.filter {
                    $0.scWindow.owningApplication?.bundleIdentifier == app.bundleIdentifier
                }
                toRemove.forEach { PinManager.shared.unpinByWindowID($0.scWindow.windowID) }
            }
        }

        // Handle CLI args or run as menu bar app
        if !cliArgs.isEmpty {
            handleCLI(cliArgs)
        } else {
            setupMenuBar()
            installHotkeys()
            print("WindowTools running. Option+P = pin, Option+U = unpin.")
        }
    }

    @objc func displayConfigurationChanged(_ notification: Notification) {
        // Displays, Spaces, and application windows settle at different times
        // after wake. Retry so a transient early geometry value cannot strand
        // an overlay at the screen origin.
        for delay in [0.0, 0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                PinManager.shared.resyncAll()
            }
        }
    }

    func handleCLI(_ args: [String]) {
        // For "list" command, no need to keep running
        switch args[0] {
        case "list":
            PinManager.shared.listWindows(filter: args.count > 1 ? args[1] : nil)
            NSApp.terminate(nil)

        case "pin":
            guard args.count > 1 else {
                printUsage()
                NSApp.terminate(nil)
                return
            }
            // Delay slightly to let permissions settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PinManager.shared.pinByName(args[1])
            }

        case "unpin":
            if args.count > 1 {
                PinManager.shared.unpinByName(args[1])
            } else {
                PinManager.shared.unpinAll()
            }
            // Give time for cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }

        case "status":
            PinManager.shared.listPinned()
            NSApp.terminate(nil)

        default:
            printUsage()
            NSApp.terminate(nil)
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.autosaveName = "ai.vernir.windowtools.status-item"
        if let button = statusItem?.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(pinStatusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        minimizeStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        minimizeStatusItem?.autosaveName = "ai.vernir.windowtools.minimize-status-item"
        if let button = minimizeStatusItem?.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.stack.badge.minus",
                accessibilityDescription: "Minimize all windows"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "Minimize all windows (Control-Option-Command-M)"
            button.target = self
            button.action = #selector(doMinimizeAll)
        }

        updateMenuBarTitle()
        statusMenu.delegate = self

        PinManager.shared.onPinChanged = { [weak self] in
            self?.updateMenuBarTitle()
        }
    }

    func updateMenuBarTitle() {
        let count = PinManager.shared.mirrors.count
        let image = NSImage(
            systemSymbolName: count > 0 ? "pin.fill" : "pin",
            accessibilityDescription: "Pin the focused window"
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = count > 0
            ? "\(count) pinned window\(count == 1 ? "" : "s")"
            : "Pin the focused window"
    }

    @objc func pinStatusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
        } else {
            guard let application = lastFocusedApplication else { return }
            PinManager.shared.pinApp(
                pid: application.processIdentifier,
                name: application.localizedName ?? "Unknown"
            )
        }
    }

    @objc func applicationActivated(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.activationPolicy == .regular
        else {
            return
        }
        lastFocusedApplication = application
    }

    @MainActor @objc func doMinimizeAll() {
        minimizeAllWindows()
    }

    @objc func pinAppAction(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication,
              let name = app.localizedName else { return }
        PinManager.shared.pinApp(pid: app.processIdentifier, name: name)
    }

    @objc func unpinAppAction(_ sender: NSMenuItem) {
        guard let windowID = sender.representedObject as? CGWindowID else { return }
        PinManager.shared.unpinByWindowID(windowID)
    }

    @objc func doUnpinAll() {
        PinManager.shared.unpinAll()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let pm = PinManager.shared

        // --- Pinned section ---
        if !pm.mirrors.isEmpty {
            let header = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(
                string: "PINNED",
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                             .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(header)

            for m in pm.mirrors {
                let appName = m.scWindow.owningApplication?.applicationName ?? "Unknown"

                // Get window title to differentiate multiple windows from the same app
                var title = appName
                if let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], m.scWindow.windowID) as? [[String: Any]],
                   let first = info.first,
                   let windowTitle = first[kCGWindowName as String] as? String,
                   !windowTitle.isEmpty {
                    title = "\(appName) — \(windowTitle)"
                }

                let item = NSMenuItem(title: title, action: #selector(unpinAppAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = m.scWindow.windowID

                if let bid = m.scWindow.owningApplication?.bundleIdentifier,
                   let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
                   let icon = runningApp.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }

                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // --- Available apps section ---
        let appsHeader = NSMenuItem(title: "Pin App", action: nil, keyEquivalent: "")
        appsHeader.isEnabled = false
        appsHeader.attributedTitle = NSAttributedString(
            string: "PIN AN APP",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(appsHeader)

        let apps = pm.runningAppsWithWindows()
        for app in apps {
            guard let name = app.localizedName else { continue }

            let item = NSMenuItem(title: name, action: #selector(pinAppAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app

            if let icon = app.icon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }

            menu.addItem(item)
        }

        if apps.isEmpty {
            let noApps = NSMenuItem(title: "No apps with windows", action: nil, keyEquivalent: "")
            noApps.isEnabled = false
            menu.addItem(noApps)
        }

        // --- Footer ---
        menu.addItem(.separator())

        let hotkeys = NSMenuItem(title: "⌥P Pin frontmost  ·  ⌥U Unpin last", action: nil, keyEquivalent: "")
        hotkeys.isEnabled = false
        hotkeys.attributedTitle = NSAttributedString(
            string: "⌥P Pin frontmost  ·  ⌥U Unpin last",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.tertiaryLabelColor])
        menu.addItem(hotkeys)

        let minimize = NSMenuItem(
            title: "Minimize All Windows",
            action: #selector(doMinimizeAll),
            keyEquivalent: "m"
        )
        minimize.target = self
        minimize.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(minimize)

        if !pm.mirrors.isEmpty {
            let unpinAll = NSMenuItem(title: "Unpin All", action: #selector(doUnpinAll), keyEquivalent: "")
            unpinAll.target = self
            menu.addItem(unpinAll)
        }

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit WindowTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

// MARK: - Usage

func printUsage() {
    print("""
    WindowTools - Pin or minimize macOS windows

    Usage:
      WindowTools                     Run as menu bar app (Option+P/U hotkeys)
      WindowTools pin <app>           Pin an app's frontmost window
      WindowTools unpin [app]         Unpin app (or all if no app given)
      WindowTools list [app]          List visible windows
      WindowTools status              Show currently pinned windows

    Hotkeys (when running as menu bar app):
      Option+P    Pin the frontmost window
      Option+U    Unpin the last pinned window

    How it works:
      Uses ScreenCaptureKit to mirror the target window into a floating
      overlay panel. The overlay passes all mouse events through to the
      real window underneath.

    Permissions required:
      - Screen Recording  (System Settings > Privacy & Security > Screen Recording)
      - Accessibility      (System Settings > Privacy & Security > Accessibility)
    """)
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let cliArgs = Array(CommandLine.arguments.dropFirst())
let delegate = AppDelegate(cliArgs: cliArgs)
app.delegate = delegate
app.run()
