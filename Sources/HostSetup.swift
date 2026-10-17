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
    let notice = Design.text("This advanced account-management flow uses Remote Login to administer the iMac. Normal Add Display setup and daily streaming do not require it. Account changes need explicit administrator authorization; FileVault is never changed.",12,secondary:true)
    let result = Design.text("",12,secondary:true)
    let startup = NSButton(checkboxWithTitle:"Open Viewer automatically after iMac sign-in",target:nil,action:nil)
    let hostStartup = NSButton(checkboxWithTitle:"Start RetinaLink automatically when this Mac signs in",target:nil,action:nil)
    let dedicated = NSButton(checkboxWithTitle:"Use this retired iMac as a dedicated display",target:nil,action:nil)
    let restoreDedicated = NSButton(title:"Turn Off Dedicated Mode…",target:nil,action:nil)
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
        if let saved = DeviceSettings.binding { address.stringValue = saved.address; username.stringValue = saved.managementUsername ?? saved.username }
        discovered.addItem(withTitle:"Choose a nearby Mac…")
        discovered.target = self; discovered.action = #selector(selectDiscovered)
        discovered.widthAnchor.constraint(equalToConstant:450).isActive = true
        discovery.onChange = { [weak self] results in
            guard let self = self else { return }; self.found = results
            self.discovered.removeAllItems(); self.discovered.addItem(withTitle:"Choose a nearby Mac…")
            self.discovered.addItems(withTitles:results.map(\.name))
        }; discovery.start()
        startup.state = .on; hostStartup.state = .on
        restoreDedicated.target = self; restoreDedicated.action = #selector(restoreDedicatedMode)
        restoreDedicated.isHidden = DeviceSettings.binding?.dedicatedDisplay != true
        replacing.isHidden = true
        dedicated.target = self; dedicated.action = #selector(dedicatedChanged)
        continueButton = Design.button("Continue",target:self,action:#selector(advance),primary:true)
        backButton = Design.button("Back",target:self,action:#selector(back)); backButton.isHidden = true
        settingsButton = Design.button("What will change…",target:self,action:#selector(showLoginGuide)); settingsButton.isHidden = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let titleRow = horizontal([Design.symbol("display.2",size:32),Design.text("Add Display",14,.semibold)])
        let fields = Design.card([
            Design.text("Find your iMac",17,.semibold),discovered,
            Design.formField("iMac address",field:address),
            Design.formField("Account",field:username,hint:"Use the account name shown in the iMac’s Home folder. You’ll enter its password securely if needed.")])
        fields.identifier = NSUserInterfaceItemIdentifier("setupTargetFields")
        let choices = Design.card([Design.text("Make it automatic",17,.semibold),startup,hostStartup,dedicated,
            Design.text("Dedicated mode creates a separate standard account, enables automatic login, and removes its idle lock. It is for retired iMacs with no personal files. FileVault stays unchanged.",12,secondary:true),settingsButton,restoreDedicated,replacing])
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
        for option in [startup,hostStartup,dedicated,replacing,restoreDedicated] { option.isEnabled = !value && stage != "complete" }
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
        settingsButton?.title = preflight?.fileVault.allowsAutomaticLoginGuide == true ? "What will change…" : "About FileVault and restarts…"
        if dedicated.state == .on { startup.state = .on }
        startup.isEnabled = !busy && dedicated.state != .on
    }
    @objc func back() {
        guard !busy else { return }; stage = "address"; preflight = nil; connection = nil
        section("setupChoices")?.isHidden = true; section("setupTargetFields")?.isHidden = false; heading.stringValue = "Your iMac, ready as a display."
        noticeTitle.stringValue = "Advanced account management"; notice.stringValue = "Remote Login is used for this optional administrator operation. Normal pairing and streaming connect directly without it."
        continueButton.title = "Continue"; backButton.isHidden = true; setBusy(false,message:"")
    }
    @objc func showLoginGuide() {
        let state = preflight?.fileVault ?? DeviceSettings.binding?.fileVault ?? .unknown
        let alert = NSAlert(); alert.messageText = state == .off ? "A dedicated account for your display" : "FileVault requires an unlock after restart"
        alert.informativeText = state == .off ? "RetinaLink creates a standard account named RetinaLink Display and enables automatic login. Viewer starts fullscreen and reconnects to this Mac. Its screensaver and idle password lock are disabled; Viewer prevents idle system sleep while running. Manual locking still needs a password.\n\nAnyone with physical access can use this account. macOS stores a recoverable login credential for automatic login. Keep personal files out of it. Your existing account, its lock settings, and FileVault are left unchanged. Organization policies are respected.\n\nYou authorize setup once using this iMac administrator’s password on the Host. A restart is needed to enter the new account." : state.setupMessage
        alert.addButton(withTitle:"Understood"); alert.runModal()
    }
    private func dedicatedAuthorization(restoring: Bool = false) -> String? {
        let alert = NSAlert(); alert.messageText = restoring ? "Turn off unattended display startup?" : "Prepare this iMac for unattended use?"
        alert.informativeText = restoring ? "Turn off RetinaLink automatic login, re-enable the display account’s idle lock, and remove its Viewer startup agent. The account and files are preserved. FileVault and other accounts stay unchanged. Enter the iMac administrator password below." : "Create a non-administrator RetinaLink Display account, enable automatic login, disable its idle password lock and screensaver, and keep it awake while Viewer runs. Anyone with physical access can use it. macOS stores a recoverable login credential. Existing accounts and FileVault stay unchanged.\n\nEnter the iMac administrator password for \(connection?.target.username ?? ""). It is sent over authenticated SSH and is never saved by RetinaLink. A restart will be offered after setup."
        let password = NSSecureTextField(frame:NSRect(x:0,y:0,width:380,height:28)); password.placeholderString = "iMac administrator password"
        alert.accessoryView = password; alert.addButton(withTitle:restoring ? "Turn Off Dedicated Mode" : "Set Up Dedicated Display"); alert.addButton(withTitle:"Cancel")
        alert.window.initialFirstResponder = password
        guard alert.runModal() == .alertFirstButtonReturn, !password.stringValue.isEmpty else { password.stringValue = ""; return nil }
        let value = password.stringValue; password.stringValue = ""; return value
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
        var administratorPassword: String? = nil
        if dedicated {
            guard preflight.fileVault == .off else { result.stringValue = preflight.fileVault.setupMessage; return }
            guard let password = dedicatedAuthorization() else { return }; administratorPassword = password
        }
        setBusy(true,message:dedicated ? "Creating the dedicated display account securely…" : "Installing Viewer and creating your private display connection…")
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self = self else { return }
            do {
                try connection.pinServerIdentity()
                let reuse = DeviceSettings.binding?.address == connection.target.address
                let keys = try TunnelIdentity.existingOrCreate(reuse:reuse)
                let credential = (reuse ? try DeviceVault.credential() : nil) ?? randomPairingCode().replacingOccurrences(of:"-",with:"")
                var binding = DeviceBinding(hostID:DeviceSettings.hostID,hostName:Host.current().localizedName ?? "Mac Studio",viewerName:preflight.name,address:connection.target.address,username:connection.target.username,dedicatedDisplay:dedicated,viewerStartup:viewerStartup,hostStartup:hostStartup,fileVault:preflight.fileVault,automaticLoginConfigured:preflight.automaticLoginConfigured,enrolledAt:Date())
                try connection.transferViewer()
                if dedicated {
                    if let old = DeviceSettings.binding, old.managementUsername == nil {
                        UserDefaults.standard.set(try JSONEncoder().encode(old),forKey:"dedicatedPreviousBinding.v1"); UserDefaults.standard.synchronize()
                    }
                    binding.managementUsername = connection.target.username
                    binding.username = "retinalinkdisplay"; binding.viewerStartup = true; binding.automaticLoginConfigured = true
                    _ = try connection.configureDedicatedDisplay(EnrollmentRequest(binding:binding,credential:credential,tunnelPublicKey:keys.publicKey),administratorPassword:administratorPassword ?? "")
                    administratorPassword = nil
                } else {
                    try connection.enroll(EnrollmentRequest(binding:binding,credential:credential,tunnelPublicKey:keys.publicKey),replacing:replacing)
                }
                try DeviceVault.write(Data(credential.utf8),account:DeviceVault.credentialAccount)
                try DeviceVault.write(keys.privateKey,account:TunnelIdentity.account)
                try DeviceSettings.save(binding)
                if hostStartup { try StartupAgent.install(executable:Bundle.main.executablePath!,role:"Host",arguments:["--autostart"]) }
                else { try? FileManager.default.removeItem(at:StartupAgent.path(role:"Host")) }
                connection.releaseOldForward()
                DispatchQueue.main.async { self.host?.enrollmentCompleted(binding) }
                if !dedicated { try connection.startViewer(startup:viewerStartup) }
                DispatchQueue.main.async {
                    self.stage = "complete"; self.heading.stringValue = dedicated ? "Ready for its first restart." : "Your iMac is ready."
                    self.descriptionText.stringValue = dedicated ? "RetinaLink Display is configured for automatic login. After restarting, Viewer will open fullscreen and pair automatically." : viewerStartup ? "Everything stays paired. Viewer opens fullscreen and reconnects automatically after sign-in." : "Everything stays paired. Viewer opens fullscreen whenever you launch it on the iMac."
                    self.continueButton.title = "Done"; self.backButton.isHidden = true
                    self.notice.stringValue = dedicated ? "Automatic login is enabled only for RetinaLink Display. Manual locking and signing out still require intervention. Keep personal files out of this account." : binding.fileVault.setupMessage
                    self.setBusy(false,message:dedicated ? "Dedicated setup complete. Restart the iMac to activate it. FileVault and existing accounts are unchanged." : "Setup complete. FileVault, automatic login and lock settings were left unchanged.")
                    self.host?.refreshHome(); self.onCompletion?(.success(binding))
                    if dedicated { self.offerRestart(connection) }
                }
            } catch {
                administratorPassword = nil
                try? connection.startViewer(startup:viewerStartup)
                DispatchQueue.main.async {
                    self.restoreDedicated.isHidden = false
                    if String(describing:error).contains("belongs to another Host") { self.replacing.isHidden = false }
                    self.setBusy(false,message:String(describing:error)); self.onCompletion?(.failure(error))
                }
            }
        }
    }
    @objc func restoreDedicatedMode() {
        guard !busy, let connection = connection else { return }
        guard let password = dedicatedAuthorization(restoring:true) else { return }
        setBusy(true,message:"Turning off dedicated automatic login…")
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let keys = try TunnelIdentity.existingOrCreate(reuse:true)
                let credential = try DeviceVault.credential() ?? randomPairingCode().replacingOccurrences(of:"-",with:"")
                let binding = DeviceSettings.binding ?? DeviceBinding(hostID:DeviceSettings.hostID,hostName:"Mac",viewerName:"iMac",address:connection.target.address,username:"retinalinkdisplay",dedicatedDisplay:true,viewerStartup:true,hostStartup:true,fileVault:.off,automaticLoginConfigured:true,enrolledAt:Date())
                _ = try connection.configureDedicatedDisplay(EnrollmentRequest(binding:binding,credential:credential,tunnelPublicKey:keys.publicKey),administratorPassword:password,operation:"restore")
                if let data = UserDefaults.standard.data(forKey:"dedicatedPreviousBinding.v1"), let old = try? JSONDecoder().decode(DeviceBinding.self,from:data) { try DeviceSettings.save(old) }
                else if var current = DeviceSettings.binding { current.dedicatedDisplay = false; current.automaticLoginConfigured = false; current.viewerStartup = false; try DeviceSettings.save(current) }
                DispatchQueue.main.async { self.restoreDedicated.isHidden = true; self.setBusy(false,message:"Automatic login is off. The display account and files were preserved; its idle lock is enabled. Restart and sign into your original account to use it again."); self.host?.refreshHome() }
            } catch { DispatchQueue.main.async { self.setBusy(false,message:String(describing:error)) } }
        }
    }
    func offerRestart(_ connection: SetupConnection) {
        let alert = NSAlert(); alert.messageText = "Restart the iMac to use dedicated display mode"
        alert.informativeText = "Save any work on the iMac first. macOS will request a normal restart and may ask about unsaved documents. RetinaLink will reconnect when the dedicated account signs in."
        alert.addButton(withTitle:"Restart Later"); alert.addButton(withTitle:"Restart iMac")
        if alert.runModal() == .alertSecondButtonReturn {
            DispatchQueue.global(qos:.utility).async {
                _ = try? connection.execute("/usr/bin/osascript -e 'tell application \"System Events\" to restart'")
            }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func windowWillClose(_ notification: Notification) { host?.setupController = nil }
}
#endif
