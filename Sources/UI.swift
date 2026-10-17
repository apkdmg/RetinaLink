import AppKit

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
    let v = NSTextField(wrappingLabelWithString:text); v.font = .systemFont(ofSize:size,weight:weight)
    v.isSelectable = true; v.maximumNumberOfLines = 0; return v
}
func horizontal(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views:views); s.orientation = .horizontal; s.spacing = 10; s.alignment = .centerY; return s
}
func makeWindow(_ title: String, views: [NSView], height: CGFloat = 600) -> NSWindow {
    let w = NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:height),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
    w.title = title; w.isReleasedWhenClosed = false
    let stack = NSStackView(views:views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = NSView(); content.addSubview(stack); w.contentView = content
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:28)])
    for view in views { view.widthAnchor.constraint(lessThanOrEqualTo:stack.widthAnchor).isActive = true }
    w.center(); w.makeKeyAndOrderFront(nil); return w
}
func installMenu() {
    let menu = NSMenu(), item = NSMenuItem(), app = NSMenu()
    app.addItem(withTitle:"About RetinaLink",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
    app.addItem(.separator()); app.addItem(withTitle:"Quit RetinaLink",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
    item.submenu = app; menu.addItem(item)
    let editItem = NSMenuItem(), edit = NSMenu(title:"Edit")
    edit.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
    edit.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
    edit.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
    editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
}
func localAddresses() -> String {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return "" }; defer { freeifaddrs(list) }
    var result: [String] = [], pointer = list
    while let entry = pointer {
        defer { pointer = entry.pointee.ifa_next }
        guard let addr = entry.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET else { continue }
        let name = String(cString:entry.pointee.ifa_name)
        guard name != "lo0", (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
        var storage = [CChar](repeating:0,count:Int(NI_MAXHOST))
        if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&storage,socklen_t(storage.count),nil,0,NI_NUMERICHOST) == 0 {
            result.append("\(name): \(String(cString:storage))")
        }
    }
    return result.joined(separator:"  •  ")
}

#if !HOST
import Network
import Metal

final class ViewerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!, displayWindow: NSWindow?, display: DisplayView?
    let servers = NSPopUpButton(), preference = NSPopUpButton()
    let pairingMode = NSPopUpButton(), pairingNote = label("",size:11)
    let address = NSTextField(), code = NSTextField()
    let status = label("Searching for Hosts on your local network…")
    let stats = label("No screen is being received.")
    var connectButton: NSButton!, fullscreenButton: NSButton!
    var browser: NWBrowser?, endpoints: [NWEndpoint] = [], link: Link?
    var connected = false
    var activity: StreamingActivity?
    var reconnect: DispatchWorkItem?
    var automatic = LaunchOptions.has("--autoconnect")
    var statsTimer: Timer?
    var recentDiagnostics: [String] = []
    var mode: PairingMode { PairingMode(rawValue:pairingMode.indexOfSelectedItem) ?? .shortCode }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        address.placeholderString = "Optional Host IP address, e.g. 192.168.1.10"
        address.stringValue = UserDefaults.standard.string(forKey:"viewerAddress") ?? ""
        code.stringValue = UserDefaults.standard.string(forKey:"viewerShortCode") ?? ""
        code.font = .monospacedSystemFont(ofSize:13,weight:.regular)
        pairingMode.addItems(withTitles:PairingMode.allCases.map(\.title))
        pairingMode.selectItem(at:(PairingMode(rawValue:UserDefaults.standard.integer(forKey:"pairingMode")) ?? .shortCode).rawValue)
        pairingMode.target = self; pairingMode.action = #selector(pairingModeChanged); pairingModeChanged()
        for f in [address,code] { f.widthAnchor.constraint(equalToConstant:590).isActive = true }
        preference.addItems(withTitles:["Automatic route","Wi-Fi only","Wired network only"])
        preference.selectItem(at:max(0,min(2,UserDefaults.standard.integer(forKey:"viewerRoute"))))
        servers.addItem(withTitle:"Searching…"); servers.widthAnchor.constraint(equalToConstant:400).isActive = true
        connectButton = NSButton(title:"Connect",target:self,action:#selector(toggleConnection))
        fullscreenButton = NSButton(title:"Full screen",target:self,action:#selector(fullscreen)); fullscreenButton.isEnabled = false
        window = makeWindow("RetinaLink Viewer",views:[
            label("RetinaLink",size:30,weight:.bold),label("VIEWER  ·  VERSION \(LaunchOptions.version) · BUILD \(LaunchOptions.build)",size:11,weight:.semibold),
            label("Use this Mac as a second display. Connect both Macs to the same Wi-Fi or wired network."),
            label("Available Hosts",weight:.semibold),servers,address,
            horizontal([label("Pairing",weight:.semibold),pairingMode]),code,pairingNote,preference,
            horizontal([connectButton,fullscreenButton]),status,stats,
            NSButton(title:"Copy diagnostics",target:self,action:#selector(copyDiagnostics)),
            label("Native 5K requires a 5K Host profile and a full-screen viewer on the iMac’s default Retina display mode. Keyboard and mouse stay connected to the Host.",size:11)
        ],height:800)
        window.delegate = self
        let p = NWParameters(); p.includePeerToPeer = true
        browser = NWBrowser(for:.bonjour(type:serviceType,domain:nil),using:p)
        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state { self?.status.stringValue = "Discovery unavailable: \(e). You can still enter the Host IP." }
            if case .waiting = state { self?.status.stringValue = "Allow Local Network access, or enter the Host IP manually." }
        }
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            self.endpoints = results.map(\.endpoint).sorted { String(describing:$0) < String(describing:$1) }
            self.servers.removeAllItems()
            if self.endpoints.isEmpty { self.servers.addItem(withTitle:"No Hosts found — use an IP address below") }
            for endpoint in self.endpoints {
                if case .service(let name,_,_,_) = endpoint { self.servers.addItem(withTitle:name) }
                else { self.servers.addItem(withTitle:String(describing:endpoint)) }
            }
        }
        browser?.start(queue:.main); NSApp.activate(ignoringOtherApps:true)
        DiagnosticLog.shared.record("launch", "Viewer ready; activity \(!LaunchOptions.has("--no-streaming-activity")); drawables \(LaunchOptions.has("--two-drawables") ? 2 : 3)")
        if automatic { DispatchQueue.main.async { [weak self] in self?.toggleConnection() } }
    }
    @objc func pairingModeChanged() {
        UserDefaults.standard.set(mode.rawValue,forKey:"pairingMode")
        code.isEnabled = mode != .noCode
        code.placeholderString = mode == .longCode ? "Paste the Host’s long code" : "Enter the Host’s five-digit code"
        switch mode {
        case .shortCode: pairingNote.stringValue = "The short code is remembered after connecting. Use on a trusted local network."
        case .longCode: pairingNote.stringValue = "Select Long code on Host too, then paste its current code."
        case .noCode: pairingNote.stringValue = "Testing only: unencrypted connection. Select No code on Host too; leave the code field alone."
        }
    }
    @objc func toggleConnection() {
        if let link = link { automatic = false; reconnect?.cancel(); link.cancel(); return }
        do {
            let selectedMode = mode, credential = try mode.credential(from:code.stringValue)
            let selectedRoute = preference.indexOfSelectedItem
            let parameters = try networkParameters(credential,preference:selectedRoute)
            let host = address.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            let endpoint: NWEndpoint
            if !host.isEmpty {
                guard host.count < 256, !host.contains("/"), !host.contains(" ") else { throw LinkError.invalid("Enter an IP address or local hostname, without a URL or port") }
                endpoint = .hostPort(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:defaultPort)!)
            } else {
                guard servers.indexOfSelectedItem >= 0, servers.indexOfSelectedItem < endpoints.count else { throw LinkError.invalid("Start the Host app first, or enter its IP address") }
                endpoint = endpoints[servers.indexOfSelectedItem]
            }
            let display = try DisplayView(viewer:true); self.display = display
            activity = StreamingActivity()
            let dw = NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:540),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            dw.title = "RetinaLink Display"; dw.isReleasedWhenClosed = false; dw.contentView = display
            dw.collectionBehavior = [.fullScreenPrimary]; dw.center(); dw.delegate = self; displayWindow = dw
            let current = Link(NWConnection(to:endpoint,using:parameters)); link = current
            let credits = DispatchSemaphore(value:3)
            let statistics = ViewerStatistics()
            display.onPresentation = { width, height, time in statistics.presented(width:width,height:height,time:time) }
            current.onReceiveTiming = { type, milliseconds in
                if type == 2 { statistics.receivedBody(in:milliseconds) }
            }
            recentDiagnostics.removeAll()
            let timer = Timer(timeInterval:1,repeats:true) { [weak self,weak current] _ in
                guard let self = self, let current = current, self.link === current, self.connected else { return }
                let report = statistics.report(); self.stats.stringValue = report
                DiagnosticLog.shared.record("viewer", report)
                self.recentDiagnostics.append(report)
                if self.recentDiagnostics.count > 15 { self.recentDiagnostics.removeFirst() }
            }
            statsTimer?.invalidate(); statsTimer = timer; RunLoop.main.add(timer,forMode:.common)
            current.onReady = { [weak self,weak current] in
                guard let current = current else { return }
                FrameTrace.shared.event("viewer_session",fields:["link":current.traceID,"view":display.traceID])
                let hello = Hello(version:1,bc7:true,name:Host.current().localizedName ?? "Viewer",maxFramesInFlight:3,chunkedPacking:true)
                if let data = try? JSONEncoder().encode(hello) { current.send(1,data) }
                DispatchQueue.main.async {
                    guard let self = self, self.link === current else { return }
                    self.connected = true; self.status.stringValue = "\(selectedMode.connectionLabel) · \(current.pathLabel)"
                    UserDefaults.standard.set(host,forKey:"viewerAddress")
                    UserDefaults.standard.set(selectedRoute,forKey:"viewerRoute")
                    if selectedMode == .shortCode { UserDefaults.standard.set(credential,forKey:"viewerShortCode") }
                    self.displayWindow?.makeKeyAndOrderFront(nil); self.fullscreenButton.isEnabled = true
                    DiagnosticLog.shared.record("state", "Connected")
                    if LaunchOptions.has("--fullscreen") { self.fullscreen() }
                }
            }
            current.onMessage = { [weak self,weak current,weak display] type, data in
                guard let current = current else { return }
                if type == 2 {
                    guard credits.wait(timeout:.now()) == .success else { current.cancel(reason:"Viewer frame queue overflow"); return }
                    guard let display = display else { credits.signal(); current.cancel(); return }
                    statistics.received(data.count); display.receive(data)
                } else if type == 4 {
                    let text = String(data:data,encoding:.utf8) ?? "Host error"
                    DispatchQueue.main.async { [weak self] in self?.status.stringValue = text }
                } else { current.cancel() }
            }
            display.onFrame = { [weak current] timing in
                credits.signal()
                statistics.completed(timing)
                guard let current = current else { return }
                var ack = Data(); ack.put64(timing.sequence); current.send(3,ack,traceSequence:timing.sequence)
            }
            display.onError = { [weak current] text in current?.cancel(reason:text) }
            current.onClose = { [weak self,weak current] reason in
                DispatchQueue.main.async {
                    guard let self = self, self.link === current else { return }
                    self.link = nil; self.connected = false; self.connectButton.title = "Connect"; self.activity = nil
                    DiagnosticLog.shared.record("state", reason)
                    self.statsTimer?.invalidate(); self.statsTimer = nil
                    self.fullscreenButton.isEnabled = false; self.status.stringValue = reason
                    self.pairingMode.isEnabled = true; self.pairingModeChanged()
                    self.displayWindow?.delegate = nil; self.displayWindow?.close(); self.displayWindow = nil; self.display = nil
                    if self.automatic {
                        let retry = DispatchWorkItem { [weak self] in
                            guard let self = self, self.automatic, self.link == nil else { return }; self.toggleConnection()
                        }
                        self.reconnect = retry; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:retry)
                    }
                }
            }
            pairingMode.isEnabled = false
            connectButton.title = "Disconnect"; status.stringValue = "Connecting · \(selectedMode.connectionLabel)…"; current.start()
        } catch { status.stringValue = String(describing:error); activity = nil; DiagnosticLog.shared.record("state", String(describing:error)) }
    }
    @objc func copyDiagnostics() {
        let samples = recentDiagnostics.isEmpty ? stats.stringValue : recentDiagnostics.joined(separator:"\n\n")
        let text = "RetinaLink Viewer \(LaunchOptions.version) (build \(LaunchOptions.build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)\nTransport: ordered TCP · default priority · whole-message I/O\nGPU: \(display?.device.name ?? "Not connected")\n\(status.stringValue)\nRecent one-second samples, oldest first:\n\(samples)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
    }
    @objc func fullscreen() { displayWindow?.toggleFullScreen(nil) }
    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === displayWindow { automatic = false; reconnect?.cancel(); link?.cancel() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { automatic = false; reconnect?.cancel(); statsTimer?.invalidate(); link?.cancel(); browser?.cancel() }
}
#endif
