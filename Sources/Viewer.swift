#if !HOST
import AppKit
import Network
import Metal

final class ApplianceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ViewerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!, display: DisplayView?, link: Link?
    var container: NSView!, standby: NSView!
    let titleText = Design.text("Your iMac is ready.",34,.semibold)
    let subtitle = Design.text("Add this display in RetinaLink on your main Mac.",17,secondary:true)
    let deviceName = Design.text(Host.current().localizedName ?? "iMac",12,.medium,secondary:true)
    var connected = false, automatic = true, terminating = false, receivedFrame = false, paused = false
    var reconnect: DispatchWorkItem?, statsTimer: Timer?, uiTimer: Timer?
    var recentDiagnostics: [String] = []
    var activity: StreamingActivity?
    var phase = "ready"
    var desiredFullscreen = true
    let softwareUpdater = AutomaticUpdater()
    var hostSupportsUpdates = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu(); addMaintenanceMenu()
        do { try DedicatedViewerStartup.applyPendingEnrollment() }
        catch { DiagnosticLog.shared.record("setup",String(describing:error)) }
        DedicatedViewerStartup.keepReady()
        UpdateSettings.applyLaunchOptions()
        if UpdateSettings.returnToStartupAgentIfNeeded() { return }
        desiredFullscreen = !LaunchOptions.has("--windowed-viewer")
        automatic = !LaunchOptions.has("--standby-only")
        makeStandbyWindow()
        DiagnosticLog.shared.record("launch","Viewer appliance ready; fullscreen and automatic reconnection; UI capture helper unused")
        uiTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.publishState() }
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
        if automatic { connect() }
        softwareUpdater.onChange = { [weak self] status in
            guard let self = self, self.hostSupportsUpdates, DeviceSettings.binding != nil, let peer = self.link, self.connected,
                  let data = try? JSONEncoder().encode(status) else { return }
            peer.send(7,data)
        }
        if DeviceSettings.binding != nil { softwareUpdater.start() }
        if let path = LaunchOptions.value("--export-ui") { DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in if let window = self?.window { Design.export(window,path:path) } } }
    }
    func makeStandbyWindow() {
        let screen = NSScreen.main, rect = desiredFullscreen ? (screen?.frame ?? NSRect(x:0,y:0,width:1280,height:720)) : NSRect(x:0,y:0,width:1060,height:680)
        let style: NSWindow.StyleMask = desiredFullscreen ? [.borderless] : [.titled,.closable,.miniaturizable,.resizable]
        window = ApplianceWindow(contentRect:rect,styleMask:style,backing:.buffered,defer:false)
        window.title = "RetinaLink Display"; window.isReleasedWhenClosed = false; window.delegate = self
        window.backgroundColor = .black; window.isOpaque = true
        window.collectionBehavior = [.fullScreenPrimary]
        container = NSView(frame:rect); container.wantsLayer = true; container.layer?.backgroundColor = NSColor.black.cgColor
        container.appearance = NSAppearance(named:.darkAqua); window.contentView = container
        let art = MonitorArtwork(); art.translatesAutoresizingMaskIntoConstraints = false; art.heightAnchor.constraint(equalToConstant:150).isActive = true
        let contents = Design.vertical([art,titleText,subtitle,deviceName],spacing:18)
        let glass = Design.card([contents],padding:40); glass.translatesAutoresizingMaskIntoConstraints = false
        standby = glass; container.addSubview(glass)
        NSLayoutConstraint.activate([glass.centerXAnchor.constraint(equalTo:container.centerXAnchor),glass.centerYAnchor.constraint(equalTo:container.centerYAnchor),glass.widthAnchor.constraint(equalToConstant:620),contents.widthAnchor.constraint(equalToConstant:540),art.widthAnchor.constraint(equalTo:contents.widthAnchor)])
        window.makeKeyAndOrderFront(nil)
        if desiredFullscreen { NSApp.presentationOptions = [.autoHideDock,.autoHideMenuBar] }
        NSApp.activate(ignoringOtherApps:true)
        if !desiredFullscreen { window.center() }
        if DeviceSettings.binding == nil { subtitle.stringValue = "Open RetinaLink on your main Mac and choose Add Display." }
        else { showStandby("Waiting for your Mac…",detail:"Your display will connect automatically. No action is needed here.",phase:"waiting") }
    }
    func showStandby(_ title: String, detail: String, phase: String) {
        self.phase = phase; titleText.stringValue = title; subtitle.stringValue = detail
        // Keep the Metal layer attached and drawable-capable under standby.
        // Hiding it before its first frame can prevent drawable acquisition.
        standby.isHidden = false
        if desiredFullscreen, let frame = window.screen?.frame ?? NSScreen.main?.frame { window.setFrame(frame,display:true) }
        publishState()
    }
    func connect() {
        if DeviceSettings.binding == nil {
            do { try DedicatedViewerStartup.applyPendingEnrollment(); DedicatedViewerStartup.keepReady() }
            catch { DiagnosticLog.shared.record("setup",String(describing:error)) }
        }
        guard automatic, !terminating, link == nil else { return }
        hostSupportsUpdates = false
        reconnect?.cancel(); reconnect = nil
        do {
            let credential: String
            let binding = DeviceSettings.binding
            if binding != nil {
                guard let trusted = try DeviceVault.credential() else { throw LinkError.invalid("Set up this display again from RetinaLink Host.") }; credential = trusted
            } else if let saved = UserDefaults.standard.string(forKey:"viewerShortCode"), !saved.isEmpty {
                credential = try normalizedCode(saved)
            } else { return }
            let address = binding == nil ? (UserDefaults.standard.string(forKey:"viewerAddress") ?? "") : "127.0.0.1"
            guard DeviceBinding.validAddress(address) else { throw LinkError.invalid("Set up this display from your main Mac.") }
            let view = try DisplayView(viewer:true); view.translatesAutoresizingMaskIntoConstraints = false
            display?.removeFromSuperview(); display = view
            container.addSubview(view,positioned:.below,relativeTo:standby)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:container.leadingAnchor),view.trailingAnchor.constraint(equalTo:container.trailingAnchor),view.topAnchor.constraint(equalTo:container.topAnchor),view.bottomAnchor.constraint(equalTo:container.bottomAnchor)])
            view.isHidden = false; receivedFrame = false; paused = false
            let peer = Link(NWConnection(to:.hostPort(host:NWEndpoint.Host(address),port:NWEndpoint.Port(rawValue:defaultPort)!),using:try networkParameters(credential)))
            link = peer; activity = StreamingActivity()
            let credits = DispatchSemaphore(value:3), statistics = ViewerStatistics()
            let announcementLock = NSLock(); var announcedFirstFrame = false
            view.onPresentation = { width,height,time in statistics.presented(width:width,height:height,time:time) }
            view.onActualPresent = { statistics.actualPresentCall($0) }
            peer.onReceiveTiming = { type,ms in if type == 2 { statistics.receivedBody(in:ms) } }
            peer.onReady = { [weak self,weak peer] in
                guard let peer = peer else { return }
                FrameTrace.shared.event("viewer_session",fields:["link":peer.traceID,"view":view.traceID])
                let hello = Hello(version:1,bc7:true,name:Host.current().localizedName ?? "iMac",maxFramesInFlight:3,chunkedPacking:true,appVersion:LaunchOptions.version,appBuild:LaunchOptions.build,automaticUpdates:true)
                if let data = try? JSONEncoder().encode(hello) { peer.send(1,data) }
                DispatchQueue.main.async {
                    guard let self = self, self.link === peer else { return }
                    self.connected = true
                    self.showStandby("Connected to \(binding?.hostName ?? "your Mac")",detail:"Preparing your extended desktop…",phase:"connected")
                    DiagnosticLog.shared.record("state","Connected · encrypted · \(binding == nil ? "legacy pairing" : "trusted device")")
                }
            }
            peer.onMessage = { [weak self,weak peer,weak view] type,data in
                guard let peer = peer else { return }
                if type == 6, binding != nil, data.count < 4096 {
                    guard let command = try? JSONDecoder().decode(SoftwareUpdateCommand.self,from:data) else { return }
                    DispatchQueue.main.async {
                        guard let self = self, self.link === peer else { return }
                        self.hostSupportsUpdates = true
                        switch command.action {
                        case "automatic": if let enabled = command.automatic { self.softwareUpdater.setAutomatic(enabled) }
                        case "check": self.softwareUpdater.check()
                        case "install": self.softwareUpdater.check(installNow:true)
                        case "test-feed": if let value = command.testBaseURL, value.isEmpty || UpdateSettings.validTestBase(value) { self.softwareUpdater.configureTestBase(value) }
                        default: break
                        }
                    }
                } else if type == 2 {
                    guard credits.wait(timeout:.now()) == .success else { peer.cancel(reason:"Viewer frame queue overflow"); return }
                    guard let view = view else { credits.signal(); peer.cancel(); return }
                    statistics.received(data.count); view.receive(data)
                } else if type == 4 {
                    let message = String(data:data.prefix(2048),encoding:.utf8) ?? ""
                    DispatchQueue.main.async {
                        guard let self = self, self.link === peer else { return }
                        if message.contains("permission") { self.showStandby("Ready when your Mac is.",detail:"Allow Screen Recording in RetinaLink Host on your main Mac.",phase:"permission") }
                        DiagnosticLog.shared.record("host-state",message)
                    }
                } else if type == 5, data.count <= 256 {
                    let command = String(data:data,encoding:.utf8) ?? ""
                    DispatchQueue.main.async {
                        guard let self = self, self.link === peer else { return }
                        if command == "paused" { self.paused = true; self.showStandby("Display paused",detail:"Choose Connect in RetinaLink on your main Mac to resume.",phase:"paused") }
                        if command == "resume" { self.paused = false; self.showStandby("Preparing your desktop…",detail:"Your display is connected securely.",phase:"connected") }
                        if command == "identify" {
                            self.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
                            self.titleText.stringValue = binding?.viewerName ?? "Your iMac"; self.subtitle.stringValue = "Your RetinaLink display"
                            self.standby.isHidden = false
                            DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in if self?.receivedFrame == true, self?.paused == false { self?.standby.isHidden = true } }
                        }
                    }
                } else { peer.cancel(reason:"Unknown display message") }
            }
            view.onFrame = { [weak self,weak peer] timing in
                credits.signal(); statistics.completed(timing)
                guard let peer = peer else { return }
                var ack = Data(); ack.put64(timing.sequence); peer.send(3,ack,traceSequence:timing.sequence)
                announcementLock.lock(); let announce = !announcedFirstFrame; announcedFirstFrame = true; announcementLock.unlock()
                guard announce else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.link === peer, !self.paused else { return }
                    if !self.receivedFrame {
                        self.receivedFrame = true; self.phase = "streaming"; self.standby.isHidden = true; self.display?.isHidden = false
                        DiagnosticLog.shared.record("state","Streaming · fullscreen appliance"); self.publishState()
                    }
                }
            }
            view.onError = { [weak peer] text in peer?.cancel(reason:text) }
            peer.onClose = { [weak self,weak peer] reason in DispatchQueue.main.async {
                guard let self = self, self.link === peer else { return }
                self.link = nil; self.connected = false; self.activity = nil; self.statsTimer?.invalidate(); self.statsTimer = nil
                self.receivedFrame = false; self.display?.removeFromSuperview(); self.display = nil
                DiagnosticLog.shared.record("state",reason)
                self.showStandby("Reconnecting to your Mac…",detail:"Your display stays paired. Waiting for the connection to return.",phase:"reconnecting")
                self.scheduleReconnect()
            } }
            statsTimer?.invalidate()
            statsTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self,weak peer] _ in
                guard let self = self, self.link === peer, self.connected else { return }
                let report = statistics.report(); DiagnosticLog.shared.record("viewer",report)
                self.recentDiagnostics.append(report); if self.recentDiagnostics.count > 15 { self.recentDiagnostics.removeFirst() }
            }
            showStandby("Connecting to your Mac…",detail:"Your display connects securely and automatically.",phase:"connecting")
            peer.start()
        } catch {
            showStandby("Waiting for setup",detail:String(describing:error),phase:"setup-needed")
            DiagnosticLog.shared.record("state",String(describing:error)); scheduleReconnect()
        }
    }
    func scheduleReconnect() {
        guard automatic, !terminating else { return }; reconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }; reconnect = work
        DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    @objc func woke() { if link == nil { connect() }; if desiredFullscreen, let frame = NSScreen.main?.frame { window.setFrame(frame,display:true); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) } }
    func publishState() {
        guard let path = LaunchOptions.value("--ui-state-path") ?? Optional(NSHomeDirectory()+"/Library/Logs/RetinaLink/Viewer-ui.json") else { return }
        let full = window.map { window in window.screen.map { abs(window.frame.width-$0.frame.width)<2 && abs(window.frame.height-$0.frame.height)<2 } ?? false } ?? false
        let state: [String:Any] = ["version":LaunchOptions.version,"build":LaunchOptions.build,"pid":ProcessInfo.processInfo.processIdentifier,
            "phase":phase,"connected":connected,"trusted":DeviceSettings.binding != nil,"fullscreen":full,
            "systemUIAutoHidden":NSApp.presentationOptions.contains(.autoHideDock) && NSApp.presentationOptions.contains(.autoHideMenuBar),
            "standbyVisible":standby?.isHidden == false,"automaticReconnect":automatic,"displayWindows":window == nil ? 0 : 1,
            "startupInstalled":FileManager.default.fileExists(atPath:StartupAgent.path(role:"Viewer").path),
            "time":Date().timeIntervalSince1970,"windowFrame":NSStringFromRect(window?.frame ?? .zero)]
        if let data = try? JSONSerialization.data(withJSONObject:state,options:.sortedKeys) { try? data.write(to:URL(fileURLWithPath:path),options:.atomic); try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path) }
    }
    func addMaintenanceMenu() {
        let item = NSMenuItem(), menu = NSMenu(title:"Display")
        menu.addItem(withTitle:"Show Standby Screen",action:#selector(showMaintenance),keyEquivalent:"s").target = self
        menu.addItem(withTitle:"Copy Diagnostics",action:#selector(copyDiagnostics),keyEquivalent:"d").target = self
        menu.addItem(withTitle:"Return to Full Screen",action:#selector(restoreFullscreen),keyEquivalent:"f").target = self
        item.submenu = menu; NSApp.mainMenu?.addItem(item)
    }
    @objc func showMaintenance() { showStandby("Your RetinaLink display",detail:"Manage pairing and connection from your main Mac. Quit RetinaLink from the menu for local maintenance.",phase:"maintenance") }
    @objc func restoreFullscreen() { desiredFullscreen = true; NSApp.presentationOptions = [.autoHideDock,.autoHideMenuBar]; if let frame = NSScreen.main?.frame { window.setFrame(frame,display:true) }; if receivedFrame && !paused { standby.isHidden = true }; window.makeKeyAndOrderFront(nil) }
    @objc func copyDiagnostics() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("RetinaLink Viewer \(LaunchOptions.version) build \(LaunchOptions.build)\n"+recentDiagnostics.joined(separator:"\n\n"),forType:.string)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if automatic { window.orderOut(nil); return false }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { DedicatedViewerStartup.release(); terminating = true; automatic = false; reconnect?.cancel(); statsTimer?.invalidate(); uiTimer?.invalidate(); link?.cancel() }
}
#endif
