import AppKit
import CryptoKit
import Network

// Local integration seam, unavailable without BOTH an explicit launch flag and
// a UUID-isolated preference/Keychain namespace. It never accesses live trust.
final class NativeTestHarness:NSObject,NSApplicationDelegate {
    var timer:Timer?
    var probe = "idle", streamReady = false
    var streamListener:NWListener?, streamPeers:[Link] = []
    func startTestStream() {
        #if HOST
        guard streamListener == nil, let raw = LaunchOptions.value("--native-test-stream-port"),
              let port = UInt16(raw), port >= 58500, let key = try? DeviceVault.credential() else { return }
        do {
            let listener = try NWListener(using:networkParameters(key),on:NWEndpoint.Port(rawValue:port)!)
            streamListener = listener
            listener.stateUpdateHandler = { [weak self] in if case .ready = $0 { self?.streamReady = true } }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }; let link = Link(connection); self.streamPeers.append(link)
                link.onMessage = { [weak link] type,data in
                    guard type == 77, data.count < 128 else { link?.cancel(); return }; link?.send(type,data)
                }
                link.start()
            }
            listener.start(queue:.main)
        } catch { probe = "failed" }
        #endif
    }
    func probeSavedConnection() {
        #if !HOST
        guard let raw = LaunchOptions.value("--native-test-stream-port"), let port = UInt16(raw), port >= 58500 else { return }
        guard let key = try? DeviceVault.credential() else { probe = "not-approved"; return }
        do {
            let host = LaunchOptions.value("--native-test-probe-address") ?? "127.0.0.1"
            let link = Link(NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:try networkParameters(key)))
            streamPeers.append(link); probe = "connecting"
            let token = Data(UUID().uuidString.utf8)
            link.onReady = { [weak link] in link?.send(77,token) }
            link.onMessage = { [weak self,weak link] type,data in
                DispatchQueue.main.async { self?.probe = type == 77 && data == token ? "passed" : "failed"; link?.cancel() }
            }
            link.onClose = { [weak self] _ in DispatchQueue.main.async { if self?.probe == "connecting" { self?.probe = "failed" } } }
            link.start()
        } catch { probe = "failed" }
        #endif
    }
    #if HOST
    let setup = NativeHostSetup()
    #else
    let setup = NativeViewerSetup()
    #endif
    var folder:URL!
    func applicationDidFinishLaunching(_ notification:Notification) {
        guard DeviceSettings.nativeTestScope != nil, let path = LaunchOptions.value("--native-test-directory") else { exit(2) }
        folder = URL(fileURLWithPath:path,isDirectory:true)
        do { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
        catch { exit(2) }
        installMenu()
        #if HOST
        if LaunchOptions.has("--native-test-existing-binding"), DeviceSettings.binding == nil {
            let binding = DeviceBinding(hostID:DeviceSettings.hostID,hostName:NativePeer.current(role:"host").name,
                viewerName:"Previously Paired iMac",address:"127.0.0.1",username:"account_a",dedicatedDisplay:false,
                viewerStartup:false,hostStartup:false,fileVault:.on,automaticLoginConfigured:false,enrolledAt:Date())
            do { try DeviceVault.write(Data(String(repeating:"A",count:32).utf8),account:DeviceVault.credentialAccount); try DeviceSettings.save(binding); NativeConnectionSettings.enable() }
            catch { exit(2) }
        }
        setup.show(); setup.viewerStartup.state = .off; setup.hostStartup.state = .off
        if let address = LaunchOptions.value("--native-test-address") {
            setup.address.stringValue = address
            setup.targetPort = UInt16(LaunchOptions.value("--native-pair-port") ?? "") ?? nativePairingPort
            if setup.stage != "existing" { setup.advance() }
        }
        #else
        if LaunchOptions.has("--native-test-approved-viewer") {
            let binding = DeviceBinding(hostID:UUID().uuidString,hostName:"Studio",viewerName:"Previously Paired iMac",address:"127.0.0.1",username:NSUserName(),dedicatedDisplay:false,viewerStartup:false,hostStartup:false,fileVault:.on,automaticLoginConfigured:false,enrolledAt:Date())
            do { try DeviceVault.write(Data(String(repeating:"A",count:32).utf8),account:DeviceVault.credentialAccount); try DeviceSettings.save(binding) } catch { exit(2) }
        }
        setup.start()
        #endif
        timer = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.asyncAfter(deadline:.now()+300) { NSApp.terminate(nil) }
    }
    func tick() {
        startTestStream()
        #if !HOST
        if DeviceSettings.binding != nil && ["idle","not-approved"].contains(probe) { probeSavedConnection() }
        #endif
        #if HOST
        let code = setup.verificationCode
        let stage = setup.stage
        let localApproved = setup.session?.localApproved == true
        #else
        let code = setup.code
        let stage = DeviceSettings.binding != nil ? "complete" : (code == nil ? "waiting" : "verify")
        let localApproved = setup.session?.localApproved == true
        #endif
        let paired = DeviceSettings.binding != nil
        var state:[String:Any] = ["pid":getpid(),"build":LaunchOptions.build,"stage":stage,
            "paired":paired,"code":code ?? "","localApproved":localApproved,"probe":probe,"tlsReady":streamReady,
            "fileVaultChanged":false,"scope":DeviceSettings.nativeTestScope!,"pending":NativePendingSetup.viewerID != nil,"time":Date().timeIntervalSince1970]
        if let binding = DeviceSettings.binding, let data = try? nativeJSON(binding) {
            state["bindingSHA256"] = Data(SHA256.hash(data:data)).base64EncodedString()
        }
        #if HOST
        state["continueEnabled"] = setup.continueButton.isEnabled
        state["primaryTitle"] = setup.continueButton.title
        state["message"] = setup.result.stringValue
        state["heading"] = setup.heading.stringValue
        #endif
        state["boundUsername"] = DeviceSettings.binding?.username ?? ""
        state["savedDisplayName"] = DeviceSettings.binding?.viewerName ?? ""
        state["savedDisplayDate"] = DeviceSettings.binding?.enrolledAt.timeIntervalSince1970 ?? 0
        state["viewerDeviceID"] = DeviceSettings.binding?.viewerDeviceID ?? ""
        state["physicalDisplayID"] = NativeDisplayIdentity.current ?? ""
        // Fingerprint only the disposable TEST credential, never real trust.
        if let credential = try? DeviceVault.credential() {
            state["testCredentialSHA256"] = Data(SHA256.hash(data:Data(credential.utf8))).base64EncodedString()
        }
        if let data = try? JSONSerialization.data(withJSONObject:state,options:.sortedKeys) {
            try? data.write(to:folder.appendingPathComponent("state.json"),options:.atomic)
        }
        let file = folder.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf:file), data.count <= 1024,
              let item = try? JSONSerialization.jsonObject(with:data) as? [String:String] else { return }
        try? FileManager.default.removeItem(at:file)
        switch item["action"] {
        case "approve":
            guard let code = code, item["code"] == code else { return }
            #if HOST
            setup.advance()
            #else
            setup.approve()
            #endif
        case "cancel":
            #if HOST
            setup.session?.cancel()
            #else
            setup.deny()
            #endif
        case "begin-reconnect", "begin-account-change":
            #if HOST
            setup.beginReconnect()
            #endif
        case "probe": probeSavedConnection()
        case "exit": NSApp.terminate(nil)
        case "reopen":
            #if HOST
            setup.show()
            #endif
        case "connect":
            #if HOST
            if let address = LaunchOptions.value("--native-test-address") {
                setup.address.stringValue = address
                setup.targetPort = UInt16(LaunchOptions.value("--native-pair-port") ?? "") ?? nativePairingPort
            }
            setup.advance()
            #endif
        case "forget-local":
            do { try NativeLocalPairing.forget() } catch { return }
            #if HOST
            setup.cancel(); setup.show()
            #else
            setup.stop(); setup.start()
            #endif
        case "retry":
            #if HOST
            setup.advance()
            #endif
        case "export-ui":
            #if HOST
            if let window = setup.window { Design.export(window,path:folder.appendingPathComponent("interface.png").path) }
            #else
            if let window = setup.approvalWindow { Design.export(window,path:folder.appendingPathComponent("interface.png").path) }
            #endif
        case "cleanup":
            DeviceVault.remove(DeviceVault.credentialAccount)
            if let scope = DeviceSettings.nativeTestScope {
                DeviceSettings.defaults.removePersistentDomain(forName:(Bundle.main.bundleIdentifier ?? "RetinaLink")+".NativeTest."+scope)
                DeviceSettings.defaults.synchronize()
            }
            NSApp.terminate(nil)
        default: break
        }
    }
    func applicationWillTerminate(_ notification:Notification) {
        timer?.invalidate(); streamListener?.cancel(); streamPeers.forEach { $0.cancel() }
        #if HOST
        setup.session?.cancel()
        #else
        setup.stop()
        #endif
    }
}
