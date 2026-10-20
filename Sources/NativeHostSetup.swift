#if HOST
import AppKit
import Network

final class NativeHostSetup:NSObject,NSWindowDelegate {
    var window:NSWindow?, session:NativePairSession?
    let address = NSTextField(), discovered = NSPopUpButton()
    let heading = Design.text("Your iMac. Ready for a new role.",28,.bold)
    let detail = Design.text("Install Viewer on your iMac once. Approve this Mac, then reconnect automatically.",14,secondary:true)
    let result = Design.text("",12,secondary:true), codeLabel = Design.text("",38,.semibold)
    let vaultNotice = Design.text("FileVault is checked before pairing. Encryption and login settings stay unchanged.",12,secondary:true)
    let viewerStartup = NSButton(checkboxWithTitle:"Open Viewer automatically after iMac sign-in",target:nil,action:nil)
    let hostStartup = NSButton(checkboxWithTitle:"Start Host automatically when this Mac signs in",target:nil,action:nil)
    var continueButton:NSButton!, cancelButton:NSButton!, codeCard:NSView?
    var installationCard:NSView?, discoveryCard:NSView?, startupCard:NSView?, approvedCard:NSView?
    let discovery = NativeDiscovery()
    var found:[NativeDiscovery.Result] = []
    var targetPort = nativePairingPort
    private(set) var stage = "choose", verificationCode:String?
    var onPrepared:((DeviceBinding)->Void)?, onCompleted:((DeviceBinding)->Void)?
    private var prepared:DeviceBinding?, replacingBinding:DeviceBinding?
    private var differentDisplay = false
    func show() {
        if let window = window {
            differentDisplay = false
            if ["choose","existing","approved","complete"].contains(stage) { configureStart() }
            discovery.start(type:nativePairingType); window.makeKeyAndOrderFront(nil); return
        }
        address.placeholderString = "Old-iMac.local or iMac IP address"
        discovered.addItem(withTitle:"Choose your iMac…"); discovered.target = self; discovered.action = #selector(selectDisplay)
        discovered.widthAnchor.constraint(equalToConstant:450).isActive = true
        viewerStartup.state = .on; hostStartup.state = .on
        continueButton = Design.button("Continue",target:self,action:#selector(advance),primary:true)
        cancelButton = Design.button("Cancel",target:self,action:#selector(cancel))
        let export = Design.button("Save Viewer Installer…",target:self,action:#selector(exportViewer))
        codeLabel.font = .monospacedDigitSystemFont(ofSize:38,weight:.semibold)
        codeCard = Design.card([Design.text("Compare on both Macs",14,.semibold),codeLabel,vaultNotice]); codeCard!.isHidden = true
        installationCard = Design.card([Design.text("One time on your iMac",17,.semibold),
            Design.text("Install RetinaLink Viewer in Applications and open it. You’ll approve this Mac on the iMac once. Remote Login is not required.",13,secondary:true),export])
        discoveryCard = Design.card([Design.text("Find your display",17,.semibold),discovered,Design.formField("Or enter its local address",field:address)])
        startupCard = Design.card([viewerStartup,hostStartup,
            Design.text("Viewer starts after sign-in. FileVault may require a local disk unlock after a restart; it is never disabled.",12,secondary:true)])
        approvedCard = Design.card([Design.message("Already approved on this Mac",detail:"Add your iMac again without a code, password or click on Viewer. Your previous startup and Dedicated Display settings are kept.",symbol:"checkmark.shield"),
            Design.button("Set Up a Different Display…",target:self,action:#selector(chooseDifferentDisplay))])
        let body = Design.vertical([horizontal([Design.symbol("display.2",size:30),Design.text("Add Display",14,.semibold)]),heading,detail,
            installationCard!,discoveryCard!,codeCard!,startupCard!,approvedCard!,result],spacing:18)
        for view in body.arrangedSubviews where view is NSVisualEffectView {
            view.widthAnchor.constraint(equalTo:body.widthAnchor).isActive = true
        }
        window = Design.window("Add Display — RetinaLink",content:body,width:720,height:790,footer:horizontal([cancelButton,continueButton]))
        window?.delegate = self
        discovery.onChange = { [weak self] items in
            guard let self = self else { return }; self.found = items
            self.discovered.removeAllItems(); self.discovered.addItem(withTitle:"Choose your iMac…")
            self.discovered.addItems(withTitles:items.map(\.name))
        }
        discovery.start(type:nativePairingType)
        configureStart()
    }
    private func configureStart() {
        replacingBinding = nil; prepared = nil; verificationCode = nil; codeCard?.isHidden = true
        stage = "choose"; continueButton.title = "Continue"; continueButton.isEnabled = true
        heading.stringValue = "Your iMac. Ready for a new role."
        detail.stringValue = "Open Viewer on your iMac. Your saved display stays with this Mac."
        if let binding = DeviceSettings.binding {
            address.stringValue = binding.address
            if NativePendingSetup.viewerID != nil {
                result.stringValue = "Finish approving \(binding.viewerName). Your saved display is kept."
            } else {
                stage = "existing"; continueButton.title = "Reconnect Display…"
                heading.stringValue = "Reconnect \(binding.viewerName)"
                result.stringValue = "Open Viewer on your iMac. If it needs approval, confirm the matching number on both Macs. Your display stays saved."
            }
        } else if !differentDisplay, let approval = NativeSavedDisplay.removed {
            stage = "approved"; continueButton.title = "Add Display"
            heading.stringValue = "Add \(approval.binding.viewerName) again?"
            detail.stringValue = "This iMac is already approved for your Mac. No action is needed on the iMac."
            result.stringValue = "Choose Add Display. It reconnects when available; Dedicated Display Mode, FileVault and login settings are kept."
            address.stringValue = approval.binding.address
        } else { result.stringValue = differentDisplay ? "Approving a different display replaces the previous display’s approval on this Mac." : "Approve your iMac once. It reconnects automatically; Remote Login is not needed." }
        let approved = stage == "approved"
        for card in [installationCard,discoveryCard,startupCard] { card?.isHidden = approved }
        approvedCard?.isHidden = !approved
    }
    @objc func chooseDifferentDisplay() { differentDisplay = true; configureStart() }
    // Called only after local confirmation (or the UUID-isolated test harness).
    func beginReconnect() {
        guard let binding = DeviceSettings.binding, NativePendingSetup.viewerID == nil else { configureStart(); return }
        replacingBinding = binding; stage = "choose"
        heading.stringValue = "Reconnect \(binding.viewerName)"
        detail.stringValue = "Open Viewer on your iMac, then approve the matching number on both Macs."
        result.stringValue = "Your iMac stays saved. Previously approved connections, FileVault and login settings are kept."
        continueButton.title = "Continue"; continueButton.isEnabled = true
        if let item = found.first(where:{$0.id == binding.viewerDeviceID}) ?? found.first(where:{$0.name == binding.viewerName}) {
            address.stringValue = item.address; targetPort = item.port
        }
    }
    @objc func selectDisplay() {
        let index = discovered.indexOfSelectedItem-1
        if found.indices.contains(index) { address.stringValue = found[index].address; targetPort = found[index].port }
    }
    @objc func advance() {
        if stage == "complete" { window?.close(); return }
        if stage == "approved" {
            do {
                let binding = try NativeSavedDisplay.restore()
                stage = "complete"; heading.stringValue = "Your display is added."
                detail.stringValue = "It reconnects automatically when your iMac is available."
                result.stringValue = "Existing approval, Viewer startup, FileVault and login settings are kept."
                continueButton.title = "Done"; onPrepared?(binding); onCompleted?(binding)
                discovery.stop()
            } catch { result.stringValue = String(describing:error) }
            return
        }
        if stage == "existing" { beginReconnect(); return }
        if stage == "verify" {
            session?.approve(); stage = "approving"; continueButton.isEnabled = false
            result.stringValue = "Approve this Mac on the iMac too. Both screens must show the same number."
            return
        }
        guard stage == "choose", DeviceSettings.binding == nil || NativePendingSetup.viewerID != nil || replacingBinding != nil else { return }
        let target = address.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard DeviceBinding.validAddress(target) else { result.stringValue = "Select your iMac or enter its local address."; return }
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.connectionTimeout = 8
        let parameters = NWParameters(tls:nil,tcp:tcp)
        let candidate = found.first {$0.address == target && $0.port == targetPort}?.candidate
        candidate?.apply(to:parameters)
        let endpoint = candidate?.endpoint ?? .hostPort(host:NWEndpoint.Host(target),port:NWEndpoint.Port(rawValue:targetPort)!)
        let connection = NWConnection(to:endpoint,using:parameters)
        let session = NativePairSession(connection:connection,identity:NativePeer.current(role:"host")); self.session = session
        stage = "connecting"; continueButton.isEnabled = false
        result.stringValue = "Connecting to Viewer. No Remote Login is needed…"
        session.onStatus = { [weak self] in self?.result.stringValue = $0 }
        session.onVerify = { [weak self] peer,code in
            guard let self = self else { return }
            self.verificationCode = code; self.codeLabel.stringValue = code; self.codeCard?.isHidden = false
            self.vaultNotice.stringValue = peer.fileVault.setupMessage
            self.heading.stringValue = "Is this \(peer.name)?"
            self.detail.stringValue = "Check the number on your iMac, then approve on both Macs. Your display stays saved."
            self.stage = "verify"; self.continueButton.title = "Numbers Match — Pair"; self.continueButton.isEnabled = true
            self.result.stringValue = "This number verifies the two Macs. Approve only if both screens match."
        }
        session.onBothApproved = { [weak self,weak session] in
            guard let self = self, let session = session, let peer = session.peer else { return }
            do {
                let previous = DeviceSettings.binding
                let savedCredential = try DeviceVault.credential()
                let request = try NativeHostEnrollment.prepare(peer:peer,identity:session.exchange.identity,address:target,
                    existing:previous,pendingViewerID:NativePendingSetup.viewerID,credential:savedCredential,
                    replacing:self.replacingBinding,viewerStartup:self.viewerStartup.state == .on,hostStartup:self.hostStartup.state == .on,
                    pendingBinding:NativePendingSetup.binding,
                    physicalID:self.found.first(where:{$0.id == peer.id && $0.physicalIdentity})?.id)
                let binding = NativeHostEnrollment.savedDisplay(request,existing:previous), credential = request.credential
                if NativePendingSetup.viewerID == nil {
                    // Both local approvals precede any trust change. Persist before
                    // transmitting so a lost final ACK remains resumable.
                    if binding.hostStartup && DeviceSettings.nativeTestScope == nil {
                        try StartupAgent.install(executable:Bundle.main.executablePath!,role:"Host",arguments:["--autostart"])
                    }
                    try DeviceVault.write(Data(credential.utf8),account:DeviceVault.credentialAccount)
                    do { try DeviceSettings.save(binding) }
                    catch {
                        if let old = savedCredential { try? DeviceVault.write(Data(old.utf8),account:DeviceVault.credentialAccount) }
                        else { DeviceVault.remove(DeviceVault.credentialAccount) }
                        throw error
                    }
                    NativeSavedDisplay.discardRemovedMetadata()
                    NativePendingSetup.begin(viewerID:peer.id,binding:request.binding)
                }
                NativeConnectionSettings.enable()
                self.prepared = binding; self.stage = "enrolling"; self.continueButton.isEnabled = false
                self.result.stringValue = "Saving your approved pairing securely in Keychain…"
                self.onPrepared?(binding)
                session.enroll(request)
            } catch {
                if self.prepared == nil && DeviceSettings.binding == nil { DeviceVault.remove(DeviceVault.credentialAccount); NativePendingSetup.complete() }
                self.result.stringValue = String(describing:error); session.cancel()
            }
        }
        session.onCommitted = { [weak self] in
            guard let self = self, let binding = self.prepared else { return }
            NativePendingSetup.complete()
            self.stage = "complete"; self.heading.stringValue = "Your display is paired."
            self.detail.stringValue = "Viewer will reconnect automatically. Remote Login is not needed."
            self.result.stringValue = "FileVault, automatic login and screen-lock settings are unchanged."
            self.continueButton.title = "Done"; self.continueButton.isEnabled = true
            self.codeCard?.isHidden = true; self.onCompleted?(binding)
            self.discovery.stop()
        }
        session.onClose = { [weak self] reason in
            guard let self = self, self.stage != "complete" else { return }
            if self.prepared != nil {
                if NativePendingSetup.viewerID != nil {
                    self.stage = "choose"; self.verificationCode = nil; self.codeCard?.isHidden = true
                    self.continueButton.title = "Try Again"; self.continueButton.isEnabled = true
                    self.result.stringValue = "Setup was interrupted. If Viewer is still waiting for setup, try again with the same iMac. Your approved credential is kept. If Viewer already paired, open it to reconnect automatically."
                } else {
                    self.stage = "complete"; self.continueButton.title = "Done"; self.continueButton.isEnabled = true
                    self.result.stringValue = "Your display connected securely. Your saved pairing is ready."
                }
            } else {
                self.stage = "choose"; self.result.stringValue = reason; self.continueButton.title = "Try Again"; self.continueButton.isEnabled = true
                self.codeCard?.isHidden = true; self.verificationCode = nil
            }
        }
        session.start()
    }
    @objc func exportViewer() {
        guard let archive = Bundle.main.url(forResource:"RetinaLink Viewer",withExtension:"zip") else { result.stringValue = "The complete signed Host app includes the Viewer installer."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "RetinaLink Viewer.zip"; panel.allowedFileTypes = ["zip"]
        panel.message = "Copy this signed Viewer archive to your iMac, unzip it and put Viewer in Applications. Open Viewer there once, then finish pairing here."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(contentsOf:archive).write(to:url,options:.atomic); result.stringValue = "Viewer installer saved. Copy it to your iMac and open Viewer there once." }
        catch { result.stringValue = "The Viewer installer could not be saved. Choose another location." }
    }
    @objc func cancel() { session?.cancel(); window?.close(); discovery.stop(); replacingBinding = nil }
    func windowShouldClose(_ sender:NSWindow)->Bool { session?.cancel(); discovery.stop(); return true }
}
#endif
