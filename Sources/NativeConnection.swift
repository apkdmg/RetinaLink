import AppKit
import Network
import CryptoKit

enum NativeConnectionSettings {
    static let resetKey = "nativePairingReset.v1"
    static let removedDisplayKey = "removedDisplayApproval.v1"
    static var requiresSetup:Bool { DeviceSettings.defaults.bool(forKey:resetKey) }
    static var enabled:Bool { DeviceSettings.defaults.bool(forKey:"nativeConnectionEnabled.v1") }
    static func enable() {
        DeviceSettings.defaults.removeObject(forKey:resetKey)
        DeviceSettings.defaults.set(true,forKey:"nativeConnectionEnabled.v1"); DeviceSettings.defaults.synchronize()
    }
    static var hostAddress:String? {
        let value = LaunchOptions.value("--native-host-address") ?? DeviceSettings.defaults.string(forKey:"nativeHostAddress.v1")
        return value.flatMap { DeviceBinding.validAddress($0) ? $0 : nil }
    }
    static func rememberHost(_ address:String) {
        if DeviceBinding.validAddress(address) { DeviceSettings.defaults.set(address,forKey:"nativeHostAddress.v1") }
    }
    static func record(hostID:String) -> Data {
        NetService.data(fromTXTRecord:["hostID":Data(hostID.utf8),"direct":Data("1".utf8)])
    }
}

enum NativePendingSetup {
    static let key = "nativePendingViewerID.v1"
    static var viewerID:String? {
        guard let id = DeviceSettings.defaults.string(forKey:key), UUID(uuidString:id) != nil else { return nil }
        return id
    }
    static let bindingKey = "nativePendingEnrollmentBinding.v1"
    static var binding:DeviceBinding? {
        guard let data = DeviceSettings.defaults.data(forKey:bindingKey) else { return nil }
        return try? JSONDecoder().decode(DeviceBinding.self,from:data)
    }
    static func begin(viewerID:String, binding:DeviceBinding? = nil) {
        DeviceSettings.defaults.set(viewerID,forKey:key)
        if let binding = binding, let data = try? JSONEncoder().encode(binding) { DeviceSettings.defaults.set(data,forKey:bindingKey) }
        else { DeviceSettings.defaults.removeObject(forKey:bindingKey) }
        DeviceSettings.defaults.synchronize()
    }
    static func complete() {
        DeviceSettings.defaults.removeObject(forKey:key); DeviceSettings.defaults.removeObject(forKey:bindingKey)
        DeviceSettings.defaults.synchronize()
    }
}

// Local recovery never needs the other account to be signed in. Deleting the
// credential must succeed before clearing metadata; otherwise keep the profile.
// Per-account startup, login, FileVault and network settings are not changed.
enum NativeLocalPairing {
    static func forget(removeCredential:() throws -> Void = { try DeviceVault.removeChecked(DeviceVault.credentialAccount) }) throws {
        try removeCredential()
        for key in [DeviceSettings.bindingKey,"nativeConnectionEnabled.v1","nativeHostAddress.v1",
                    NativePendingSetup.key,NativePendingSetup.bindingKey,"viewerShortCode","viewerAddress",
                    "RetinaLink.viewerUpdateRequested","RetinaLink.viewerUpdateTarget","RetinaLink.resumeViewerUpdate",
                    NativeConnectionSettings.removedDisplayKey] {
            DeviceSettings.defaults.removeObject(forKey:key)
        }
        // Host's login item may remain enabled. A reset must never make that
        // background launch fall back to an old saved legacy pairing code.
        DeviceSettings.defaults.set(true,forKey:NativeConnectionSettings.resetKey)
        DeviceSettings.defaults.synchronize()
    }
}

#if HOST
// Removing a display from the workspace is distinct from revoking approval.
// Retain the original management metadata, with the existing secret in Keychain,
// so restoring the display never needs an account/login change or Viewer click.
enum NativeSavedDisplay {
    struct Approval:Codable {
        let binding:DeviceBinding
        let credentialDigest:String
    }
    static var removed:Approval? {
        guard let data = DeviceSettings.defaults.data(forKey:NativeConnectionSettings.removedDisplayKey),
              let value = try? JSONDecoder().decode(Approval.self,from:data),
              (try? value.binding.validate()) != nil, value.binding.hostID == DeviceSettings.hostID else { return nil }
        return value
    }
    static var isRemoved:Bool {
        DeviceSettings.defaults.object(forKey:NativeConnectionSettings.removedDisplayKey) != nil
    }
    static var connectionBinding:DeviceBinding? { DeviceSettings.binding ?? removed?.binding }
    static var mayShareDesktop:Bool { !isRemoved && !NativeConnectionSettings.requiresSetup }
    static func digest(_ key:String)->String { Data(SHA256.hash(data:Data(key.utf8))).base64EncodedString() }
    static func remove(readCredential:() throws -> String? = { try DeviceVault.credential() }) throws {
        guard let binding = DeviceSettings.binding, NativeConnectionSettings.enabled else {
            throw LinkError.invalid("Finish this display’s connection setup before removing it.")
        }
        guard let key = try readCredential() else { throw LinkError.invalid("Unlock this Mac’s login Keychain and try again.") }
        let approval = Approval(binding:binding,credentialDigest:digest(key))
        // Write recovery metadata first. A crash cannot lose Dedicated Mode's
        // original account/restore information or silently revoke its consent.
        DeviceSettings.defaults.set(try JSONEncoder().encode(approval),forKey:NativeConnectionSettings.removedDisplayKey)
        DeviceSettings.defaults.removeObject(forKey:DeviceSettings.bindingKey)
        NativePendingSetup.complete()
        DeviceSettings.defaults.synchronize()
    }
    static func restore() throws -> DeviceBinding {
        guard DeviceSettings.binding == nil, let approval = removed,
              let key = try DeviceVault.credential(), digest(key) == approval.credentialDigest else {
            throw LinkError.invalid("The saved approval is unavailable. Unlock this Mac’s login Keychain or pair this iMac again.")
        }
        try DeviceSettings.save(approval.binding)
        discardRemovedMetadata(); NativeConnectionSettings.enable()
        return approval.binding
    }
    static func discardRemovedMetadata() {
        DeviceSettings.defaults.removeObject(forKey:NativeConnectionSettings.removedDisplayKey)
        DeviceSettings.defaults.synchronize()
    }
}

// Discovery/physical IDs only correlate the saved display. The existing key
// is released to another login ONLY after both authenticated local approvals.
enum NativeHostEnrollment {
    static func prepare(peer:NativePeer, identity:NativePeer, address:String,
                        existing:DeviceBinding?, pendingViewerID:String?, credential:String?,
                        replacing:DeviceBinding?, viewerStartup:Bool, hostStartup:Bool,
                        pendingBinding:DeviceBinding? = nil, physicalID:String? = nil) throws -> NativeEnrollment {
        try peer.validate(role:"viewer"); try identity.validate(role:"host")
        func validKey(_ key:String?) -> Bool { key?.count == 32 && key!.allSatisfy({"0123456789ABCDEF".contains($0)}) }
        if let existing = existing {
            if let pending = pendingViewerID {
                let target = pendingBinding ?? existing
                guard pending == peer.id, target.hostID == identity.id,
                      target.viewerName == peer.name, target.username == peer.username,
                      target.viewerDeviceID == nil || target.viewerDeviceID == peer.id,
                      validKey(credential) else {
                    throw LinkError.invalid("Finish approval on the same iMac, or remove this display before starting again.")
                }
                return NativeEnrollment(binding:target,credential:credential!)
            }
            guard replacing == existing else { throw LinkError.invalid("Choose Reconnect Display before approving this connection.") }
            if let saved = existing.viewerDeviceID, let physical = physicalID, saved != physical {
                throw LinkError.invalid("This is a different iMac. Remove the saved display before adding another one.")
            }
            guard validKey(credential) else { throw LinkError.invalid("Unlock this Mac’s login Keychain to reconnect your saved display.") }
        } else if replacing != nil || pendingViewerID != nil {
            throw LinkError.invalid("The saved display changed. Close setup and try again.")
        }
        var binding = DeviceBinding(hostID:identity.id,hostName:identity.name,viewerName:peer.name,
            address:address,username:peer.username,dedicatedDisplay:false,
            viewerStartup:viewerStartup,hostStartup:hostStartup,fileVault:peer.fileVault,
            automaticLoginConfigured:false,enrolledAt:existing?.enrolledAt ?? Date())
        guard physicalID == nil || physicalID == peer.id else { throw LinkError.invalid("The display identity changed during approval.") }
        binding.viewerDeviceID = physicalID
        try binding.validate()
        // Retain the iMac's key: previously approved logins keep reconnecting.
        return NativeEnrollment(binding:binding,credential:existing != nil ? credential! : randomPairingCode().replacingOccurrences(of:"-",with:""))
    }
    static func savedDisplay(_ request:NativeEnrollment, existing:DeviceBinding?) -> DeviceBinding {
        guard var saved = existing else { return request.binding }
        // In particular, NEVER retarget Dedicated Mode's account or auto login.
        saved.viewerDeviceID = request.binding.viewerDeviceID ?? saved.viewerDeviceID
        saved.address = request.binding.address
        return saved
    }
}

#endif

// All delegate callbacks are on the main run loop. Names/addresses are hints;
// only the TLS credential or the two-screen approval can authenticate a peer.
final class NativeDiscovery:NSObject,NetServiceBrowserDelegate,NetServiceDelegate {
    struct Result { let name:String; let address:String; let port:UInt16; let id:String; var candidate:DirectLinkCandidate? = nil; var physicalIdentity:Bool = false }
    let browser = NetServiceBrowser()
    let scoped = DirectLinkDiscovery()
    var services:[NetService] = [], results:[Result] = []
    var onChange:(([Result])->Void)?
    var onCandidates:(([DirectLinkCandidate])->Void)?
    private var type = "", hostID:String?
    func start(type:String,hostID:String? = nil) {
        stop(); self.type = type; self.hostID = hostID
        scoped.onChange = { [weak self] candidates in
            guard let self = self else { return }
            for index in self.results.indices { self.results[index].candidate = candidates.first {$0.id == self.results[index].id} }
            self.onCandidates?(candidates); self.onChange?(self.results)
        }
        scoped.start(type:type,identityKey:type == serviceType ? "hostID" : "viewerID",matchingIdentity:hostID)
        browser.delegate = self; browser.searchForServices(ofType:type,inDomain:"local.")
    }
    func stop() { scoped.stop(); browser.stop(); services.forEach {$0.stop()}; services.removeAll(); results.removeAll() }
    func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool) {
        guard services.count < 32 else { return }; services.append(service); service.delegate = self; service.resolve(withTimeout:5)
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didRemove service:NetService,moreComing:Bool) {
        services.removeAll {$0 === service || $0.name == service.name}
        results.removeAll {$0.name == service.name}; onChange?(results)
    }
    func netServiceDidResolveAddress(_ sender:NetService) {
        guard let host = sender.hostName, DeviceBinding.validAddress(host), (1...65535).contains(sender.port) else { return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let key = type == serviceType ? "hostID" : "viewerID"
        guard let data = txt[key], let id = String(data:data,encoding:.utf8), UUID(uuidString:id) != nil,
              hostID == nil || id == hostID else { return }
        results.removeAll {$0.id == id}; results.append(Result(name:String(sender.name.prefix(160)),address:host,port:UInt16(sender.port),id:id,candidate:scoped.candidates.first {$0.id == id},physicalIdentity:txt["displayIdentity"] == Data("1".utf8)))
        onChange?(results.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending})
    }
    deinit { browser.stop(); services.forEach {$0.stop()} }
}

#if !HOST
enum NativeViewerEnrollment {
    static func apply(_ request:NativeEnrollment) throws {
        try request.binding.validate()
        guard request.binding.username == NativePeer.current(role:"viewer").username, DeviceSettings.binding == nil,
              request.credential.count == 32, request.credential.allSatisfy({"0123456789ABCDEF".contains($0)}) else {
            throw LinkError.invalid("An existing display pairing cannot be replaced remotely.")
        }
        guard !Bundle.main.bundlePath.hasPrefix("/Volumes/") else {
            throw LinkError.invalid("Drag Viewer into Applications and open that installed copy before pairing.")
        }
        if DeviceSettings.nativeTestScope != nil, LaunchOptions.has("--native-test-reject-first-enrollment"),
           !DeviceSettings.defaults.bool(forKey:"nativeTestEnrollmentFailedOnce") {
            DeviceSettings.defaults.set(true,forKey:"nativeTestEnrollmentFailedOnce")
            throw LinkError.invalid("Simulated first enrollment persistence failure in isolated test scope.")
        }
        // Never add an SSH key, change an OS account, or inspect personal files.
        // Keychain must save successfully before committing the binding.
        try DeviceVault.write(Data(request.credential.utf8),account:DeviceVault.credentialAccount)
        do {
            if request.binding.viewerStartup && DeviceSettings.nativeTestScope == nil {
                try StartupAgent.install(executable:Bundle.main.executablePath!,role:"Viewer",arguments:["--appliance"])
            }
            try DeviceSettings.save(request.binding); NativeConnectionSettings.enable()
        } catch { DeviceVault.remove(DeviceVault.credentialAccount); throw error }
    }
}

final class NativeViewerSetup:NSObject,NSWindowDelegate {
    var listener:NWListener?, session:NativePairSession?, approvalWindow:NSWindow?
    var identity = NativePeer.current(role:"viewer")
    var onStatus:((String)->Void)?, onPaired:(()->Void)?
    private var attempts:[Date] = [], generation = UUID()
    private(set) var code:String?
    func start() {
        guard DeviceSettings.binding == nil, listener == nil else { return }
        if DeviceSettings.nativeTestScope == nil {
            var console = stat()
            guard stat("/dev/console",&console) == 0, console.st_uid == getuid() else { return }
        }
        let token = UUID(); generation = token
        onStatus?("Preparing secure setup…")
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let output = (try? SystemTask.run("/usr/bin/fdesetup",["status"],timeout:8))?.text ?? ""
            DispatchQueue.main.async {
                guard let self = self, self.generation == token, DeviceSettings.binding == nil else { return }
                self.identity = NativePeer.current(role:"viewer",fileVault:FileVaultState(output:output))
                self.listen(token)
            }
        }
    }
    private func listen(_ token:UUID) {
        do {
            let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
            let parameters = NWParameters(tls:nil,tcp:tcp); parameters.includePeerToPeer = false
            let port = UInt16(LaunchOptions.value("--native-pair-port") ?? "") ?? nativePairingPort
            let listener = try NWListener(using:parameters,on:NWEndpoint.Port(rawValue:port)!)
            listener.service = NWListener.Service(name:identity.name,type:nativePairingType,domain:nil,
                txtRecord:NetService.data(fromTXTRecord:["viewerID":Data(identity.id.utf8),"displayIdentity":Data((NativeDisplayIdentity.current == identity.id ? "1" : "0").utf8)]))
            listener.newConnectionHandler = { [weak self,weak listener] connection in
                guard let self = self, let listener = listener, self.listener === listener else { connection.cancel(); return }
                self.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.onStatus?("Open Host on your main Mac. Choose Reconnect Display for a saved iMac, or Add Display for first setup. Approve the matching number here.") }
                if case .failed = state { self?.onStatus?("Setup could not listen. Check Local Network permission and try Make Discoverable in the Display menu.") }
            }
            self.listener = listener; listener.start(queue:.main)
            // Standby remains discoverable. Each handshake still expires after
            // 120 seconds and attempts remain rate-limited; discovery grants no trust.

        } catch { onStatus?("Setup could not start. Try Make Discoverable in the Display menu.") }
    }
    private func accept(_ connection:NWConnection) {
        attempts.removeAll { Date().timeIntervalSince($0) > 300 }
        guard DeviceSettings.binding == nil, session == nil, attempts.count < 6 else { connection.cancel(); return }
        attempts.append(Date())
        let session = NativePairSession(connection:connection,identity:identity); self.session = session
        session.onVerify = { [weak self] peer,code in self?.showApproval(peer,code:code) }
        session.onEnrollment = { request in
            try NativeViewerEnrollment.apply(request)
            if case .hostPort(let host,_) = connection.endpoint { NativeConnectionSettings.rememberHost(String(describing:host)) }
        }
        session.onCommitted = { [weak self] in
            guard let self = self else { return }
            self.approvalWindow?.close(); self.approvalWindow = nil
            self.listener?.cancel(); self.listener = nil; self.code = nil
            self.onStatus?("Paired. Waiting for your Mac…"); self.onPaired?()
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self,weak session] in
                session?.cancel(); if self?.session === session { self?.session = nil }
            }
        }
        session.onClose = { [weak self,weak session] reason in
            guard let self = self, self.session === session else { return }
            self.session = nil; self.code = nil; self.approvalWindow?.close(); self.approvalWindow = nil
            if DeviceSettings.binding == nil { self.onStatus?(reason+" Choose Add Display on your Mac to retry.") }
        }
        session.start()
    }
    private func showApproval(_ peer:NativePeer,code:String) {
        self.code = code
        let digits = Design.text(code,38,.semibold); digits.font = .monospacedDigitSystemFont(ofSize:38,weight:.semibold)
        let allow = Design.button("Allow This Mac",target:self,action:#selector(approve),primary:true)
        let deny = Design.button("Don’t Allow",target:self,action:#selector(deny))
        let body = Design.vertical([Design.symbol("lock.shield",size:32),
            Design.text("Allow \(peer.name) to use this display?",24,.semibold),
            Design.text("Compare this number with RetinaLink Host on your main Mac. Allow only if both numbers match and you started setup.",14,secondary:true),
            Design.card([digits]),Design.text(identity.fileVault.setupMessage,12,secondary:true),
            Design.text("This approves RetinaLink only. It does not enable Remote Login or change FileVault, automatic login or your screen lock.",12,secondary:true)],spacing:18)
        approvalWindow = Design.window("Approve Host — RetinaLink",content:body,width:660,height:560,footer:horizontal([deny,allow]))
        approvalWindow?.delegate = self
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc func approve() {
        session?.approve()
        if DeviceSettings.nativeTestScope == nil { approvalWindow?.close(); approvalWindow = nil }
        onStatus?("Approved. Complete setup on your main Mac…")
    }
    @objc func deny() { session?.cancel() }
    func windowShouldClose(_ sender:NSWindow)->Bool { deny(); return true }
    func stop() { generation = UUID(); listener?.cancel(); listener = nil; session?.cancel(); session = nil; approvalWindow?.close(); approvalWindow = nil; code = nil }
}
#endif
