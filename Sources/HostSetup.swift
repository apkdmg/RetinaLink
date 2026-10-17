#if HOST
import AppKit

final class DisplayDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    var onChange: (([(name:String,address:String)]) -> Void)?
    private var results: [(name:String,address:String)] = []
    override init() { super.init(); browser.delegate = self }
    func start() { browser.searchForServices(ofType:"_ssh._tcp.",inDomain:"local.") }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service); service.delegate = self; service.resolve(withTimeout:5)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }; results.removeAll { $0.name == service.name }; onChange?(results)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, DeviceBinding.validAddress(host) else { return }
        results.removeAll { $0.name == sender.name }; results.append((sender.name,host))
        onChange?(results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    deinit { browser.stop(); services.forEach { $0.stop() } }
}

final class HostSetupController: NSObject, NSWindowDelegate {
    weak var host: HostApp?
    var window: NSWindow?
    let address = NSTextField(), username = NSTextField(), discovered = NSPopUpButton()
    let heading = Design.text("Your iMac, ready as a display.",28,.bold)
    let descriptionText = Design.text("Set everything up here. Your iMac won’t need its own keyboard or mouse for everyday use.",14,secondary:true)
    let noticeTitle = Design.text("One quick preparation",13,.semibold)
    let notice = Design.text("On a new iMac, turn on Remote Login in System Preferences → Sharing once. RetinaLink then installs Viewer and completes setup from this Mac.",12,secondary:true)
    let result = Design.text("",12,secondary:true)
    let startup = NSButton(checkboxWithTitle:"Open Viewer automatically after iMac sign-in",target:nil,action:nil)
    let hostStartup = NSButton(checkboxWithTitle:"Start RetinaLink automatically when this Mac signs in",target:nil,action:nil)
    let dedicated = NSButton(checkboxWithTitle:"Use this retired iMac as a dedicated display",target:nil,action:nil)
    let replacing = NSButton(checkboxWithTitle:"Replace this account’s previous RetinaLink pairing",target:nil,action:nil)
    var continueButton: NSButton!, backButton: NSButton!, settingsButton: NSButton!
    let spinner = NSProgressIndicator()
    let discovery = DisplayDiscovery()
    var found: [(name:String,address:String)] = []
    var connection: SetupConnection?, preflight: ViewerPreflight?
    var busy = false
    var stage = "address"
    var onCompletion: ((Result<DeviceBinding,Error>) -> Void)?
    init(host: HostApp) { self.host = host; super.init() }
    func show() {
        if let window = window { window.makeKeyAndOrderFront(nil); return }
        address.placeholderString = "Old-iMac.local or IP address"
        username.placeholderString = "iMac account’s short username"
        if let saved = DeviceSettings.binding { address.stringValue = saved.address; username.stringValue = saved.username }
        discovered.addItem(withTitle:"Choose a nearby Mac…")
        discovered.target = self; discovered.action = #selector(selectDiscovered)
        discovered.widthAnchor.constraint(equalToConstant:450).isActive = true
        discovery.onChange = { [weak self] results in
            guard let self = self else { return }; self.found = results
            self.discovered.removeAllItems(); self.discovered.addItem(withTitle:"Choose a nearby Mac…")
            self.discovered.addItems(withTitles:results.map(\.name))
        }; discovery.start()
        startup.state = .on; hostStartup.state = .on
        replacing.isHidden = true
        dedicated.target = self; dedicated.action = #selector(dedicatedChanged)
        continueButton = Design.button("Continue",target:self,action:#selector(advance),primary:true)
        backButton = Design.button("Back",target:self,action:#selector(back)); backButton.isHidden = true
        settingsButton = Design.button("Configure automatic login…",target:self,action:#selector(showLoginGuide)); settingsButton.isHidden = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let titleRow = horizontal([Design.symbol("display.2",size:32),Design.text("Add Display",14,.semibold)])
        let fields = Design.card([
            Design.text("Find your iMac",17,.semibold),discovered,
            Design.formField("iMac address",field:address),
            Design.formField("Account",field:username,hint:"Use the account name shown in the iMac’s Home folder. You’ll enter its password securely if needed.")])
        fields.identifier = NSUserInterfaceItemIdentifier("setupTargetFields")
        let choices = Design.card([Design.text("Make it automatic",17,.semibold),startup,hostStartup,dedicated,
            Design.text("Fullscreen and reconnection are always enabled. Dedicated display mode keeps the iMac ready for its paired Host; it does not change FileVault or enable automatic login.",12,secondary:true),settingsButton,replacing])
        choices.identifier = NSUserInterfaceItemIdentifier("setupChoices"); choices.isHidden = true
        let information = Design.card([horizontal([Design.symbol("lock.shield",size:22),noticeTitle]),notice])
        let body = Design.vertical([titleRow,heading,descriptionText,fields,information,choices,result],spacing:18)
        for card in [fields,choices,information] { card.widthAnchor.constraint(equalTo:body.widthAnchor).isActive = true }
        window = Design.window("Add Display — RetinaLink",content:body,width:720,height:790,footer:horizontal([backButton,spinner,continueButton])); window?.delegate = self
    }
    private func section(_ name: String) -> NSView? {
        func find(_ view: NSView) -> NSView? { if view.identifier?.rawValue == name { return view }; for child in view.subviews { if let found = find(child) { return found } }; return nil }
        return window?.contentView.flatMap(find)
    }
    @objc func selectDiscovered() {
        let index = discovered.indexOfSelectedItem-1
        if index >= 0 && index < found.count { address.stringValue = found[index].address }
    }
    func setBusy(_ value: Bool, message: String) {
        busy = value; result.stringValue = message; continueButton?.isEnabled = !value; backButton?.isEnabled = !value
        for option in [startup,hostStartup,dedicated,replacing] { option.isEnabled = !value && stage != "complete" }
        address.isEnabled = !value && stage == "address"; username.isEnabled = !value && stage == "address"; discovered.isEnabled = !value && stage == "address"
        if value { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
    @objc func advance() {
        guard !busy else { return }
        if stage == "complete" { window?.close(); return }
        if preflight != nil { install(); return }
        let target = SetupTarget(address:address.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),username:username.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),managementSocket:LaunchOptions.value("--ssh-control-path"))
        do { try target.validate() } catch { result.stringValue = String(describing:error); return }
        setBusy(true,message:"Connecting securely and checking restart requirements…")
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let connection = try SetupConnection(target), preflight = try connection.inspect()
                DispatchQueue.main.async { self.connection = connection; self.preflight = preflight; self.showOptions(preflight) }
            } catch { DispatchQueue.main.async { self.setBusy(false,message:String(describing:error)); self.onCompletion?(.failure(error)) } }
        }
    }
    func showOptions(_ preflight: ViewerPreflight) {
        stage = "options"; heading.stringValue = "Meet your new display."
        descriptionText.stringValue = "\(preflight.name) · macOS \(preflight.version). Viewer will be installed in Applications and paired securely with this Mac."
        noticeTitle.stringValue = preflight.fileVault == .on ? "A restart will require FileVault unlock" : "What happens after a restart"
        notice.stringValue = preflight.fileVault.setupMessage
        section("setupChoices")?.isHidden = false; section("setupTargetFields")?.isHidden = true
        continueButton.title = "Set Up Display"; backButton.isHidden = false
        setBusy(false,message:"No disk creation, extra macOS installation or encryption changes are involved.")
        dedicatedChanged()
        if LaunchOptions.has("--setup-viewer") { DispatchQueue.main.async { [weak self] in self?.install() } }
    }
    @objc func dedicatedChanged() {
        settingsButton?.isHidden = dedicated.state != .on
        settingsButton?.title = preflight?.fileVault.allowsAutomaticLoginGuide == true ? "Configure automatic login…" : "About FileVault and restarts…"
    }
    @objc func back() {
        guard !busy else { return }; stage = "address"; preflight = nil; connection = nil
        section("setupChoices")?.isHidden = true; section("setupTargetFields")?.isHidden = false; heading.stringValue = "Your iMac, ready as a display."
        noticeTitle.stringValue = "One quick preparation"; notice.stringValue = "Enable Remote Login on a new iMac once, then complete the rest here."
        continueButton.title = "Continue"; backButton.isHidden = true; setBusy(false,message:"")
    }
    @objc func showLoginGuide() {
        let state = preflight?.fileVault ?? DeviceSettings.binding?.fileVault ?? .unknown
        let alert = NSAlert(); alert.messageText = state.allowsAutomaticLoginGuide ? "Make a retired iMac start unattended" : "FileVault protects this iMac’s startup"
        if state.allowsAutomaticLoginGuide {
            alert.informativeText = "Use a dedicated, non-administrator account without personal files. Anyone with physical access can use an automatically logged-in account.\n\nOn the iMac: System Preferences → Users & Groups → Login Options → Automatic login. Choose the display account and enter its password in macOS. Also review its sleep/lock policy.\n\nYou can do this from this Mac using Screen Sharing. RetinaLink never stores that login password or changes FileVault. Company policy may prevent automatic login."
            alert.addButton(withTitle:"Open Screen Sharing"); alert.addButton(withTitle:"Not Now")
            if alert.runModal() == .alertFirstButtonReturn, let connection = connection {
                DispatchQueue.global(qos:.utility).async {
                    _ = try? connection.execute("/usr/bin/open 'x-apple.systempreferences:com.apple.preferences.users'")
                    DispatchQueue.main.async { if let url = URL(string:"vnc://"+connection.target.address) { NSWorkspace.shared.open(url) } }
                }
            }
        } else {
            alert.informativeText = state.setupMessage+"\n\nRetinaLink cannot bypass the older iMac’s FileVault boot screen. Dedicated display mode still provides fullscreen, automatic startup after sign-in and reconnection. It never disables encryption."
            alert.addButton(withTitle:"Understood"); alert.runModal()
        }
    }
    func install() {
        guard let connection = connection, let preflight = preflight else { return }
        if let existing = DeviceSettings.binding, existing.address != connection.target.address {
            let alert = NSAlert(); alert.messageText = "Use this iMac instead of \(existing.viewerName)?"
            alert.informativeText = "This release supports one iMac display at a time. Continuing switches this Host to the selected iMac."
            alert.addButton(withTitle:"Switch Display"); alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let dedicated = dedicated.state == .on, viewerStartup = startup.state == .on, hostStartup = hostStartup.state == .on, replacing = replacing.state == .on
        setBusy(true,message:"Installing Viewer and creating your private display connection…")
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self = self else { return }
            do {
                try connection.pinServerIdentity()
                let keys = try TunnelIdentity.create(), credential = randomPairingCode().replacingOccurrences(of:"-",with:"")
                let binding = DeviceBinding(hostID:DeviceSettings.hostID,hostName:Host.current().localizedName ?? "Mac Studio",viewerName:preflight.name,address:connection.target.address,username:connection.target.username,dedicatedDisplay:dedicated,viewerStartup:viewerStartup,hostStartup:hostStartup,fileVault:preflight.fileVault,automaticLoginConfigured:preflight.automaticLoginConfigured,enrolledAt:Date())
                try connection.transferViewer()
                try connection.enroll(EnrollmentRequest(binding:binding,credential:credential,tunnelPublicKey:keys.publicKey),replacing:replacing)
                try DeviceVault.write(Data(credential.utf8),account:DeviceVault.credentialAccount)
                try DeviceVault.write(keys.privateKey,account:TunnelIdentity.account)
                try DeviceSettings.save(binding)
                if hostStartup { try StartupAgent.install(executable:Bundle.main.executablePath!,role:"Host",arguments:["--autostart"]) }
                else { try? FileManager.default.removeItem(at:StartupAgent.path(role:"Host")) }
                connection.releaseOldForward()
                DispatchQueue.main.async { self.host?.enrollmentCompleted(binding) }
                try connection.startViewer(startup:viewerStartup)
                DispatchQueue.main.async {
                    self.stage = "complete"; self.heading.stringValue = "Your iMac is ready."
                    self.descriptionText.stringValue = viewerStartup ? "Everything stays paired. Viewer opens fullscreen and reconnects automatically after sign-in." : "Everything stays paired. Viewer opens fullscreen whenever you launch it on the iMac."
                    self.continueButton.title = "Done"; self.backButton.isHidden = true
                    self.notice.stringValue = binding.fileVault.setupMessage
                    self.setBusy(false,message:"Setup complete. FileVault, automatic login and lock settings were left unchanged.")
                    self.host?.refreshHome(); self.onCompletion?(.success(binding))
                }
            } catch {
                DispatchQueue.main.async {
                    if String(describing:error).contains("belongs to another Host") { self.replacing.isHidden = false }
                    self.setBusy(false,message:String(describing:error)); self.onCompletion?(.failure(error))
                }
            }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func windowWillClose(_ notification: Notification) { host?.setupController = nil }
}
#endif
