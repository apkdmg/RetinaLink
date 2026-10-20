import AppKit
import CryptoKit

// Local integration seam, unavailable without BOTH an explicit launch flag and
// a UUID-isolated preference/Keychain namespace. It never accesses live trust.
final class NativeTestHarness:NSObject,NSApplicationDelegate {
    var timer:Timer?
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
        setup.start()
        #endif
        timer = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.asyncAfter(deadline:.now()+300) { NSApp.terminate(nil) }
    }
    func tick() {
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
            "paired":paired,"code":code ?? "","localApproved":localApproved,
            "fileVaultChanged":false,"scope":DeviceSettings.nativeTestScope!,"pending":NativePendingSetup.viewerID != nil,"time":Date().timeIntervalSince1970]
        if let binding = DeviceSettings.binding, let data = try? nativeJSON(binding) {
            state["bindingSHA256"] = Data(SHA256.hash(data:data)).base64EncodedString()
        }
        #if HOST
        state["continueEnabled"] = setup.continueButton.isEnabled
        #endif
        state["boundUsername"] = DeviceSettings.binding?.username ?? ""
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
        case "begin-account-change":
            #if HOST
            setup.beginAccountChange()
            #endif
        case "connect":
            #if HOST
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
        timer?.invalidate()
        #if HOST
        setup.session?.cancel()
        #else
        setup.stop()
        #endif
    }
}
