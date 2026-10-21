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
    var reconnectPolicy = ViewerReconnectPolicy()
    var recentDiagnostics: [String] = []
    var activity: StreamingActivity?
    var phase = "ready"
    var desiredFullscreen = true
    let softwareUpdater = AutomaticUpdater()
    var hostSupportsUpdates = false
    let nativeDiscovery = NativeDiscovery(), nativeSetup = NativeViewerSetup()
    var nativeHostAddress:String?
    var directConnection = false
    var routeCandidates:[DirectLinkCandidate] = [], activeCandidate:DirectLinkCandidate?
    var routePolicy = DirectLinkRoutePolicy(), probePolicy = DirectLinkRoutePolicy(), routeProbe:Link?
    var verifiedPreferredKey:String?
    var verifiedPreferredUntil:Double = 0
    var intentionalHandoverConnectionID:String?
    var lastProbeResult:[String:Any] = [:]
    var sessionObservers:[NSObjectProtocol] = []
    var sessionActive:Bool {
        var console = stat()
        return stat("/dev/console",&console) == 0 && console.st_uid == getuid()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu(); addMaintenanceMenu()
        deviceName.stringValue = Host.current().localizedName ?? "iMac"
        do { try DedicatedViewerStartup.applyPendingEnrollment() }
        catch { DiagnosticLog.shared.record("setup",String(describing:error)) }
        DedicatedViewerStartup.keepReady()
        UpdateSettings.applyLaunchOptions()
        if UpdateSettings.returnToStartupAgentIfNeeded() { return }
        desiredFullscreen = !LaunchOptions.has("--windowed-viewer")
        automatic = !LaunchOptions.has("--standby-only")
        makeStandbyWindow()
        nativeSetup.onStatus = { [weak self] text in
            guard let self = self, DeviceSettings.binding == nil else { return }
            self.showStandby("Your iMac is ready.",detail:text,phase:"ready")
        }
        nativeSetup.onPaired = { [weak self] in self?.startNativeDiscovery(); self?.connect() }
        let center = NSWorkspace.shared.notificationCenter
        sessionObservers.append(center.addObserver(forName:NSWorkspace.sessionDidResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self = self else { return }
            self.nativeSetup.stop(); self.reconnect?.cancel(); self.reconnect = nil
            self.routeProbe?.cancel(); self.routeProbe = nil
            let previous = self.link; self.link = nil; previous?.cancel()
            self.softwareUpdater.detachRelay(); self.activeCandidate = nil
            self.connected = false; self.receivedFrame = false; self.activity = nil
            self.statsTimer?.invalidate(); self.statsTimer = nil
            self.display?.removeFromSuperview(); self.display = nil
            self.showStandby("Waiting for sign-in…",detail:"Your display stays saved and reconnects automatically.",phase:"waiting")
        })
        sessionObservers.append(center.addObserver(forName:NSWorkspace.sessionDidBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self = self else { return }
            self.reconnectPolicy.resumed()
            if DeviceSettings.binding == nil { self.nativeSetup.start() } else { self.startNativeDiscovery() }
            self.connect()
        })
        if DeviceSettings.binding == nil { nativeSetup.start() } else { startNativeDiscovery() }
        DiagnosticLog.shared.record("launch","Viewer appliance ready; fullscreen and automatic reconnection; UI capture helper unused")
        uiTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            self?.consumeDirectLinkTestCommand(); self?.considerPreferredConnection(); self?.publishState()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
        if automatic { connect() }
        softwareUpdater.onChange = { [weak self] status in
            guard let self = self, self.hostSupportsUpdates, DeviceSettings.binding != nil, let peer = self.link, self.connected,
                  let data = try? JSONEncoder().encode(status) else { return }
            peer.send(7,data)
        }
        // The Host announces relay support before starting the updater, so an
        // offline appliance does not begin a direct internet request on launch.
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
        if DeviceSettings.binding == nil { subtitle.stringValue = "Open Host on your main Mac. Choose Reconnect Display if your iMac is already saved, or Add Display for first setup." }
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
        guard automatic, !terminating, link == nil, sessionActive else { return }
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
            directConnection = binding != nil && !LaunchOptions.has("--legacy-ssh-transport")
            let candidate:DirectLinkCandidate?
            if directConnection, LaunchOptions.value("--native-host-address") == nil {
                let now = ProcessInfo.processInfo.systemUptime
                if let key = verifiedPreferredKey {
                    if let preferred = routeCandidates.first(where:{$0.key == key}), routePolicy.eligible(key,now:now),
                       let selected = routePolicy.select([preferred],now:now) {
                        candidate = selected; verifiedPreferredKey = nil; verifiedPreferredUntil = 0
                    } else if now < verifiedPreferredUntil {
                        // Host briefly republishes Bonjour when the old stream
                        // closes. Retain the authenticated choice until its
                        // fresh scoped record returns, with a bounded fallback.
                        showStandby("Reconnecting over your cable…",detail:"Your display stays paired. Waiting for the preferred connection to return.",phase:"reconnecting")
                        scheduleReconnect(); return
                    } else {
                        verifiedPreferredKey = nil; verifiedPreferredUntil = 0
                        candidate = routePolicy.select(routeCandidates,now:now)
                    }
                } else { candidate = routePolicy.select(routeCandidates,now:now) }
            } else { candidate = nil }
            if directConnection, LaunchOptions.value("--native-host-address") == nil,
               candidate == nil, !routeCandidates.isEmpty {
                // Known routes are cooling down. An unscoped hostname would
                // bypass that policy and might immediately retry a failed port.
                showStandby("Reconnecting to your Mac…",detail:"Your display stays paired. Retrying the available connections automatically.",phase:"reconnecting")
                scheduleReconnect(); return
            }
            let address:String
            if binding == nil { address = UserDefaults.standard.string(forKey:"viewerAddress") ?? "" }
            else if directConnection {
                if let resolved = nativeHostAddress ?? NativeConnectionSettings.hostAddress { address = resolved }
                else if candidate != nil { address = "" } // Typed service endpoint needs no cached IP/hostname.
                else {
                    showStandby("Waiting for your Mac…",detail:"Viewer finds your trusted Mac on the local network. Remote Login is not needed.",phase:"waiting")
                    scheduleReconnect(); return
                }
            } else { address = "127.0.0.1" }
            guard candidate != nil || DeviceBinding.validAddress(address) else { throw LinkError.invalid("Set up this display from your main Mac.") }
            let view = try DisplayView(viewer:true); view.translatesAutoresizingMaskIntoConstraints = false
            display?.removeFromSuperview(); display = view
            container.addSubview(view,positioned:.below,relativeTo:standby)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:container.leadingAnchor),view.trailingAnchor.constraint(equalTo:container.trailingAnchor),view.topAnchor.constraint(equalTo:container.topAnchor),view.bottomAnchor.constraint(equalTo:container.bottomAnchor)])
            view.isHidden = false; receivedFrame = false; paused = false
            let parameters = try networkParameters(credential); candidate?.apply(to:parameters)
            let endpoint = candidate?.endpoint ?? .hostPort(host:NWEndpoint.Host(address),port:NWEndpoint.Port(rawValue:defaultPort)!)
            let peer = Link(NWConnection(to:endpoint,using:parameters))
            activeCandidate = candidate
            link = peer; activity = StreamingActivity()
            let credits = ReceiveCredits(capacity:3), statistics = ViewerStatistics()
            let announcementLock = NSLock(); var announcedFirstFrame = false
            view.onPresentation = { width,height,time in statistics.presented(width:width,height:height,time:time) }
            view.onActualPresent = { statistics.actualPresentCall($0) }
            peer.onReceiveTiming = { type,ms in if type == 2 { statistics.receivedBody(in:ms) } }
            peer.onReady = { [weak self,weak peer] in
                guard let peer = peer else { return }
                FrameTrace.shared.event("viewer_session",fields:["link":peer.traceID,"view":view.traceID])
                DispatchQueue.main.async {
                    guard let self = self, self.link === peer else { return }
                    if let candidate = candidate, !DirectLinkPath.requiredInterfaceVerified(connection:peer.connection,candidate:candidate) {
                        self.routePolicy.failed(candidate.key,now:ProcessInfo.processInfo.systemUptime)
                        peer.cancel(reason:"The selected \(candidate.label) route changed. Trying another connection…",cause:.transportFailure); return
                    }
                    let hello = Hello(version:1,bc7:true,name:Host.current().localizedName ?? "iMac",maxFramesInFlight:3,chunkedPacking:true,appVersion:LaunchOptions.version,appBuild:LaunchOptions.build,automaticUpdates:true,updateRelay:UpdateRelayPolicy.version,directConnection:self.directConnection)
                    if let data = try? JSONEncoder().encode(hello) { peer.send(1,data) }
                    if let candidate = candidate { self.routePolicy.succeeded(candidate.key) }
                    self.connected = true
                    if self.directConnection { NativeConnectionSettings.enable(); NativeConnectionSettings.rememberHost(address) }
                    let path = DirectLinkPath.metadata(connection:peer.connection,candidate:candidate)
                    if let data = try? JSONSerialization.data(withJSONObject:path,options:.sortedKeys), let text = String(data:data,encoding:.utf8) {
                        DiagnosticLog.shared.record("connection-path",text)
                    }
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
                        case "relay": if command.relayVersion == UpdateRelayPolicy.version { self.softwareUpdater.attachRelay(peer) }
                        case "automatic": if let enabled = command.automatic { self.softwareUpdater.setAutomatic(enabled) }
                        case "check": self.softwareUpdater.check()
                        case "install": self.softwareUpdater.check(installNow:true)
                        case "test-feed": if let value = command.testBaseURL, value.isEmpty || UpdateSettings.validTestBase(value) { self.softwareUpdater.configureTestBase(value) }
                        default: break
                        }
                    }
                } else if type == UpdateRelayPolicy.message, binding != nil {
                    DispatchQueue.main.async { [weak self,weak peer] in
                        guard let self = self, self.link === peer else { return }
                        self.softwareUpdater.relay?.receive(data)
                    }
                } else if type == 2 {
                    guard credits.reserve() else { peer.cancel(reason:"Viewer frame queue overflow"); return }
                    guard let view = view else { credits.release(); peer.cancel(); return }
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
                        if command == "removed" {
                            self.paused = true
                            self.display?.isHidden = true
                            self.showStandby("Ready to add again.",detail:"Choose Add Display in RetinaLink on your main Mac. Your approval and login settings are kept.",phase:"removed")
                        }
                        if command == "resume" { self.paused = false; self.display?.isHidden = false; self.showStandby("Preparing your desktop…",detail:"Your display is connected securely.",phase:"connected") }
                        if command == "identify" {
                            self.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
                            self.titleText.stringValue = binding?.viewerName ?? "Your iMac"; self.subtitle.stringValue = "Your RetinaLink display"
                            self.standby.isHidden = false
                            DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in if self?.receivedFrame == true, self?.paused == false { self?.standby.isHidden = true } }
                        }
                    }
                } else if type == 8, binding != nil, data.count <= 64,
                          String(data:data,encoding:.utf8) == binding?.hostID {
                    DispatchQueue.main.async {
                        guard let self = self, self.link === peer, let binding = DeviceSettings.binding else { return }
                        do {
                            _ = try ViewerEnrollment.remove(nativeJSON(["hostID":binding.hostID]))
                            UserDefaults.standard.removeObject(forKey:"nativeConnectionEnabled.v1")
                            UserDefaults.standard.removeObject(forKey:"nativeHostAddress.v1")
                            self.nativeDiscovery.stop()
                            self.routeProbe?.cancel(); self.routeProbe = nil; self.routeCandidates.removeAll(); self.activeCandidate = nil
                            self.verifiedPreferredKey = nil; self.verifiedPreferredUntil = 0
                            self.intentionalHandoverConnectionID = nil
                            peer.send(9,data) { DispatchQueue.main.async {
                                self.link = nil; peer.cancel(); self.connected = false; self.receivedFrame = false
                                self.statsTimer?.invalidate(); self.statsTimer = nil; self.activity = nil
                                self.display?.removeFromSuperview(); self.display = nil
                                self.showStandby("Your iMac is ready.",detail:"Approve a new Host to connect this display.",phase:"ready")
                                self.nativeSetup.start()
                            } }
                        } catch { peer.cancel(reason:"Pairing could not be removed. Check Viewer locally.") }
                    }
                } else { peer.cancel(reason:"Unknown display message",cause:.invalidPacket) }
            }
            view.onFrame = { [weak self,weak peer] timing in
                credits.release(); statistics.completed(timing)
                guard let peer = peer else { return }
                var ack = Data(); ack.put64(timing.sequence); peer.send(3,ack,traceSequence:timing.sequence)
                announcementLock.lock(); let announce = !announcedFirstFrame; announcedFirstFrame = true; announcementLock.unlock()
                guard announce else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.link === peer, !self.paused else { return }
                    if !self.receivedFrame {
                        self.reconnectPolicy.resumed()
                        self.receivedFrame = true; self.phase = "streaming"; self.standby.isHidden = true; self.display?.isHidden = false
                        DiagnosticLog.shared.record("state","Streaming · fullscreen appliance"); self.publishState()
                        let fullscreen = self.window.screen.map { abs(self.window.frame.width-$0.frame.width)<2 && abs(self.window.frame.height-$0.frame.height)<2 } ?? false
                        self.softwareUpdater.confirmDisplayReconnected(fullscreen:fullscreen)
                    }
                }
            }
            view.onError = { [weak peer] text in peer?.cancel(reason:text) }
            peer.onClose = { [weak self,weak peer] reason in
                let cause = peer?.closeCause ?? .cancelled
                DispatchQueue.main.async {
                    guard let self = self, let peer = peer, self.link === peer else { return }
                    if self.intentionalHandoverConnectionID == peer.traceID {
                        // Moving to an authenticated cable did not make the old
                        // route unhealthy. Keep it ready if the cable is removed.
                        self.intentionalHandoverConnectionID = nil
                    } else if cause.penalizesRoute, let candidate = candidate {
                        self.routePolicy.failed(candidate.key,now:ProcessInfo.processInfo.systemUptime)
                    } else if let candidate = candidate {
                        self.routePolicy.streamEnded(candidate.key,wasStreaming:self.receivedFrame)
                    }
                    self.routeProbe?.cancel(); self.routeProbe = nil; self.activeCandidate = nil
                    self.softwareUpdater.detachRelay()
                    self.link = nil; self.connected = false; self.activity = nil; self.statsTimer?.invalidate(); self.statsTimer = nil
                    self.receivedFrame = false; self.display?.removeFromSuperview(); self.display = nil
                    DiagnosticLog.shared.record("state",reason+" · "+cause.rawValue)
                    self.showStandby("Reconnecting to your Mac…",detail:"Your display stays paired. Waiting for the connection to return.",phase:"reconnecting")
                    self.scheduleReconnect()
                }
            }
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
        let delay = reconnectPolicy.nextDelay()
        let work = DispatchWorkItem { [weak self] in self?.connect() }; reconnect = work
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
    }
    func startNativeDiscovery() {
        guard let binding = DeviceSettings.binding, !LaunchOptions.has("--legacy-ssh-transport") else { return }
        nativeDiscovery.onChange = { [weak self] results in
            guard let self = self, let result = results.first else { return }
            self.nativeHostAddress = result.address
            if self.link == nil, self.reconnect == nil { self.connect() }
        }
        nativeDiscovery.onCandidates = { [weak self] candidates in
            guard let self = self else { return }; self.routeCandidates = candidates
            if let active = self.activeCandidate, active.isUSB, self.connected,
               DirectLinkRoutePolicy.usbRouteUnavailable(recordedIndex:active.interfaceIndex,
                   currentIndex:Int(if_nametoindex(active.interfaceName)),
                   linkActive:USBLinkInterfaces.snapshot()[active.interfaceName]?.linkActive) {
                // Do not wait for a stalled TCP stream when macOS has already
                // reported the actual USB port down. Normal TLS reconnection
                // selects an available fallback and retains the saved pairing.
                self.link?.cancel(reason:"USB disconnected. Reconnecting automatically…",cause:.transportFailure)
                return
            }
            if self.link == nil {
                if self.reconnect == nil { self.connect() }
            } else { self.considerPreferredConnection() }
        }
        nativeDiscovery.start(type:serviceType,hostID:binding.hostID)
    }
    func considerPreferredConnection() {
        guard automatic, !terminating, connected, directConnection, !paused, routeProbe == nil,
              LaunchOptions.value("--native-host-address") == nil, DeviceSettings.binding != nil,
              let current = link else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let currentRank = routeCandidates.first {$0.key == activeCandidate?.key}?.rank ?? activeCandidate?.rank
        let preferred = routeCandidates.filter { routePolicy.mayProbe(key:$0.key,rank:$0.rank,wired:$0.wired,activeKey:activeCandidate?.key,activeRank:currentRank,now:now) }
        guard let candidate = probePolicy.select(preferred,now:now),
              let credential = try? DeviceVault.credential(), !credential.isEmpty,
              let parameters = try? networkParameters(credential) else { return }
        routePolicy.reserveProbe(now:now); candidate.apply(to:parameters)
        let probe = Link(NWConnection(to:candidate.endpoint,using:parameters)); routeProbe = probe
        probe.onReady = { [weak self,weak probe,weak current] in DispatchQueue.main.async {
            guard let self = self, let probe = probe, let current = current, self.routeProbe === probe,
                  self.link === current, self.connected, self.automatic, !self.terminating, !self.paused,
                  self.routeCandidates.contains(where:{$0.key == candidate.key}) else { probe?.cancel(); return }
            guard DirectLinkPath.requiredInterfaceVerified(connection:probe.connection,candidate:candidate) else {
                self.routePolicy.failed(candidate.key,now:ProcessInfo.processInfo.systemUptime); probe.cancel(); self.routeProbe = nil; return
            }
            self.lastProbeResult = ["success":true,"identityMatched":true,"requiredInterfaceVerified":true,
                "selectedInterface":candidate.interfaceName,"connectionPath":DirectLinkPath.metadata(connection:probe.connection,candidate:candidate)]
            self.routePolicy.succeeded(candidate.key); self.probePolicy.succeeded(candidate.key)
            self.verifiedPreferredKey = candidate.key
            self.verifiedPreferredUntil = ProcessInfo.processInfo.systemUptime+15
            self.routeProbe = nil
            probe.cancel() // No Hello: this probe never claims the Host stream.
            // Keep the old stream until the preferred endpoint has passed TLS.
            // Then use normal reconnect, which resets frame/keyframe state.
            self.intentionalHandoverConnectionID = current.traceID
            current.cancel(reason:"Using the preferred \(candidate.label) connection…")
        } }
        probe.onClose = { [weak self,weak probe] _ in DispatchQueue.main.async {
            guard let self = self, let probe = probe, self.routeProbe === probe else { return }
            self.routePolicy.failed(candidate.key,now:ProcessInfo.processInfo.systemUptime)
            self.probePolicy.failed(candidate.key,now:ProcessInfo.processInfo.systemUptime); self.routeProbe = nil
        } }
        probe.start()
    }
    func consumeDirectLinkTestCommand() {
        // Local, explicit test launch only; no network command can invoke this.
        guard let directory = LaunchOptions.value("--direct-link-test-control-directory") else { return }
        let file = URL(fileURLWithPath:directory).appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf:file), data.count <= 1024,
              let item = try? JSONSerialization.jsonObject(with:data) as? [String:String] else { return }
        try? FileManager.default.removeItem(at:file)
        switch item["command"] {
        case "fail-active-route":
            if let candidate = activeCandidate { routePolicy.failed(candidate.key,now:ProcessInfo.processInfo.systemUptime) }
            link?.cancel(reason:"Simulated unavailable interface for the local recovery test")
        case "retry-best-route": routePolicy = DirectLinkRoutePolicy(); probePolicy = DirectLinkRoutePolicy(); considerPreferredConnection()
        default: break
        }
    }
    @objc func woke() { reconnectPolicy.resumed(); if link == nil { connect() }; if desiredFullscreen, let frame = NSScreen.main?.frame { window.setFrame(frame,display:true); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) } }
    func publishState() {
        guard let path = LaunchOptions.value("--ui-state-path") ?? Optional(NSHomeDirectory()+"/Library/Logs/RetinaLink/Viewer-ui.json") else { return }
        let full = window.map { window in window.screen.map { abs(window.frame.width-$0.frame.width)<2 && abs(window.frame.height-$0.frame.height)<2 } ?? false } ?? false
        let state: [String:Any] = ["version":LaunchOptions.version,"build":LaunchOptions.build,"pid":ProcessInfo.processInfo.processIdentifier,
            "phase":phase,"connected":connected,"trusted":DeviceSettings.binding != nil,"fullscreen":full,
            "systemUIAutoHidden":NSApp.presentationOptions.contains(.autoHideDock) && NSApp.presentationOptions.contains(.autoHideMenuBar),
            "standbyVisible":standby?.isHidden == false,"automaticReconnect":automatic,"displayWindows":window == nil ? 0 : 1,
            "startupInstalled":FileManager.default.fileExists(atPath:StartupAgent.path(role:"Viewer").path),
            "transport":directConnection ? "direct-tls" : "legacy", "requiresRemoteLogin":!directConnection,"connectionID":link?.traceID ?? "",
            "connectionPath":link.map { DirectLinkPath.metadata(connection:$0.connection,candidate:activeCandidate) } ?? [:],
            "discoveredRoutes":routeCandidates.map(\.metadata),"lastPreferredRouteProbe":lastProbeResult,
            "time":Date().timeIntervalSince1970,"windowFrame":NSStringFromRect(window?.frame ?? .zero)]
        if let data = try? JSONSerialization.data(withJSONObject:state,options:.sortedKeys) { try? data.write(to:URL(fileURLWithPath:path),options:.atomic); try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path) }
    }
    func addMaintenanceMenu() {
        let item = NSMenuItem(), menu = NSMenu(title:"Display")
        menu.addItem(withTitle:"Show Standby Screen",action:#selector(showMaintenance),keyEquivalent:"s").target = self
        menu.addItem(withTitle:"Copy Diagnostics",action:#selector(copyDiagnostics),keyEquivalent:"d").target = self
        menu.addItem(withTitle:"Return to Full Screen",action:#selector(restoreFullscreen),keyEquivalent:"f").target = self
        menu.addItem(withTitle:"Make Discoverable for Setup",action:#selector(makeDiscoverable),keyEquivalent:"").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle:"Reset Connection…",action:#selector(resetLocalPairing),keyEquivalent:"").target = self
        item.submenu = menu; NSApp.mainMenu?.addItem(item)
    }
    @objc func makeDiscoverable() {
        guard DeviceSettings.binding == nil else {
            showStandby("Already paired with \(DeviceSettings.binding!.hostName)",detail:"Your pairing is kept. Viewer reconnects directly without Remote Login. Manage this display from Host.",phase:"maintenance"); return
        }
        nativeSetup.stop(); nativeSetup.start()
    }
    @objc func resetLocalPairing() {
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Reset this Viewer’s connection?"
        alert.informativeText = "This Viewer will disconnect and ask for approval again. Your iMac stays saved on Host; choose Reconnect Display there. FileVault and login settings stay unchanged."
        alert.addButton(withTitle:"Reset Pairing"); alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try NativeLocalPairing.forget() }
        catch { showStandby("Pairing was kept.",detail:String(describing:error),phase:"maintenance"); return }
        nativeSetup.stop(); nativeDiscovery.stop(); reconnect?.cancel(); reconnect = nil
        routeProbe?.cancel(); routeProbe = nil; routeCandidates.removeAll(); activeCandidate = nil
        verifiedPreferredKey = nil; verifiedPreferredUntil = 0; intentionalHandoverConnectionID = nil
        let old = link; link = nil; old?.cancel(); softwareUpdater.detachRelay()
        connected = false; receivedFrame = false; hostSupportsUpdates = false; paused = false
        statsTimer?.invalidate(); statsTimer = nil; activity = nil; display?.removeFromSuperview(); display = nil
        showStandby("Your iMac is ready.",detail:"Choose Reconnect Display on your main Mac, then approve the matching number.",phase:"ready")
        nativeSetup.start()
    }
    @objc func showMaintenance() { showStandby("Your RetinaLink display",detail:"Manage pairing and connection from your main Mac. Quit RetinaLink from the menu for local maintenance.",phase:"maintenance") }
    @objc func restoreFullscreen() { desiredFullscreen = true; NSApp.presentationOptions = [.autoHideDock,.autoHideMenuBar]; if let frame = NSScreen.main?.frame { window.setFrame(frame,display:true) }; if receivedFrame && !paused { standby.isHidden = true }; window.makeKeyAndOrderFront(nil) }
    @objc func copyDiagnostics() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("RetinaLink Viewer \(LaunchOptions.version) build \(LaunchOptions.build)\n"+recentDiagnostics.joined(separator:"\n\n"),forType:.string)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if automatic { window.orderOut(nil); return false }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { nativeSetup.stop(); nativeDiscovery.stop(); DedicatedViewerStartup.release(); terminating = true; automatic = false; reconnect?.cancel(); statsTimer?.invalidate(); uiTimer?.invalidate(); routeProbe?.cancel(); link?.cancel() }
}
#endif
