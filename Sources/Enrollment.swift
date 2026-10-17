import Foundation
import Security
import AppKit

// Enrollment requires an authenticated legacy SSH session or explicit local
// approval on BOTH displays in NativePairSession. Discovery never grants trust.
enum FileVaultState: String, Codable {
    case on, off, unknown
    init(output: String) {
        if output.contains("FileVault is Off") { self = .off }
        else if output.contains("FileVault is On") { self = .on }
        else { self = .unknown }
    }
    var setupMessage: String {
        switch self {
        case .on: return "FileVault is on. After a shutdown or restart, this Intel iMac needs its disk unlocked before it can become a display. RetinaLink reconnects after sign-in. Your encryption stays unchanged."
        case .off: return "FileVault is off. Viewer will start after sign-in. For unattended restarts, choose Dedicated Display setup for an optional standard account with automatic login. FileVault stays unchanged."
        case .unknown: return "We could not verify FileVault. The iMac may require a password after restarting. Viewer starts after sign-in; encryption and login settings stay unchanged."
        }
    }
    var allowsAutomaticLoginGuide: Bool { self == .off }
}

struct DeviceBinding: Codable, Equatable {
    var hostID: String
    var hostName: String
    var viewerName: String
    var address: String
    var username: String
    var dedicatedDisplay: Bool
    var viewerStartup: Bool
    var hostStartup: Bool
    var fileVault: FileVaultState
    var automaticLoginConfigured: Bool
    var enrolledAt: Date
    var managementUsername: String? = nil
    func validate() throws {
        guard UUID(uuidString:hostID) != nil,
              !hostName.isEmpty, hostName.utf8.count <= 160,
              !viewerName.isEmpty, viewerName.utf8.count <= 160,
              Self.validAddress(address), Self.validUsername(username) else {
            throw LinkError.invalid("The display enrollment is invalid.")
        }
    }
    static func validAddress(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count < 254 && !text.hasPrefix("-") &&
        text.unicodeScalars.allSatisfy { CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:").contains($0) }
    }
    static func validUsername(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 64 && !text.hasPrefix("-") &&
        text.unicodeScalars.allSatisfy { CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }
}

struct EnrollmentRequest: Codable {
    let binding: DeviceBinding
    let credential: String
    let tunnelPublicKey: String
    func validate() throws {
        try binding.validate()
        guard credential.count == 32, credential.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw LinkError.invalid("Enrollment needs a new random device credential.")
        }
        let parts = tunnelPublicKey.split(separator:" ")
        guard parts.count == 3, parts[0] == "ssh-ed25519", parts[2] == "RetinaLink-tunnel",
              Data(base64Encoded:String(parts[1]))?.count == 51,
              !tunnelPublicKey.contains("\n"), !tunnelPublicKey.contains("\r") else {
            throw LinkError.invalid("Invalid restricted connection key.")
        }
    }
}

enum DeviceVault {
    // Developer ID releases keep a stable namespace and signing requirement.
    // Ad-hoc development builds have hash-specific Keychain ACLs, so they must
    // re-enroll instead of silently asking to trust a changed executable.
    static var service: String {
        let base = Bundle.main.object(forInfoDictionaryKey:"RetinaLinkTrustNamespace") as? String ?? "local.retinalink.development.\(LaunchOptions.build)"
        return DeviceSettings.nativeTestScope.map { base+".native-test."+$0 } ?? base
    }
    private static let accessLock = NSLock()
    static func silently<T>(_ operation: () throws -> T) throws -> T {
        accessLock.lock(); defer { accessLock.unlock() }
        // SecItem defaults to the classic Mac keychain. Its shim does not
        // reliably honor the per-query authentication-UI flag. Suppress UI
        // for this operation too, restoring the prior process setting on all
        // exits. Serialize our writes/removals against this scoped setting.
        var previousUI: DarwinBoolean = false
        let previousStatus = SecKeychainGetUserInteractionAllowed(&previousUI)
        guard previousStatus == errSecSuccess else { throw LinkError.invalid("Could not read trusted display silently (\(previousStatus)). Unlock your login Keychain and retry.") }
        defer { _ = SecKeychainSetUserInteractionAllowed(previousUI.boolValue) }
        let suppressStatus = SecKeychainSetUserInteractionAllowed(false)
        guard suppressStatus == errSecSuccess else { throw LinkError.invalid("Could not read trusted display silently (\(suppressStatus)). Unlock your login Keychain and retry.") }
        return try operation()
    }
    static func read(_ account: String) throws -> Data? {
        try silently { try readSilently(account) }
    }
    private static func readSilently(_ account: String) throws -> Data? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,kSecAttrAccount as String:account,
            kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne,
            kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data else {
            throw LinkError.invalid("Unlock your login Keychain to use this trusted display (\(status)).")
        }
        return bytes
    }
    static func write(_ bytes: Data, account: String) throws {
        accessLock.lock(); defer { accessLock.unlock() }
        let key: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,kSecAttrAccount as String:account]
        let status = SecItemUpdate(key as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = key; entry[kSecValueData as String] = bytes
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(entry as CFDictionary,nil)
            guard added == errSecSuccess else { throw LinkError.invalid("Could not save device trust in Keychain (\(added)).") }
        } else if status != errSecSuccess { throw LinkError.invalid("Could not update device trust (\(status)).") }
    }
    static func remove(_ account: String) {
        accessLock.lock(); defer { accessLock.unlock() }
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account] as CFDictionary)
    }
    static var credentialAccount: String {
        #if HOST
        return "host-stream"
        #else
        return "viewer-stream"
        #endif
    }
    static func credential() throws -> String? {
        guard let bytes = try read(credentialAccount) else { return nil }
        guard let value = String(data:bytes,encoding:.utf8), value.count == 32,
              value.allSatisfy({ "0123456789ABCDEF".contains($0) }) else { throw LinkError.invalid("Saved device trust is invalid. Set up this display again from Host.") }
        return value
    }
}

enum DeviceSettings {
    // Explicit integration-test isolation. Production launch agents never carry
    // these arguments; the test harness cannot access the real pairing vault.
    static var nativeTestScope:String? {
        guard LaunchOptions.has("--native-test-harness"), let value = LaunchOptions.value("--native-test-scope"), UUID(uuidString:value) != nil else { return nil }
        return value
    }
    static var defaults:UserDefaults {
        guard let scope = nativeTestScope else { return .standard }
        return UserDefaults(suiteName:(Bundle.main.bundleIdentifier ?? "RetinaLink")+".NativeTest."+scope)!
    }
    static let bindingKey = "trustedDisplayBinding.v1"
    static var binding: DeviceBinding? {
        guard let data = defaults.data(forKey:bindingKey) else { return nil }
        return try? JSONDecoder().decode(DeviceBinding.self,from:data)
    }
    static func save(_ binding: DeviceBinding) throws {
        try binding.validate()
        defaults.set(try JSONEncoder().encode(binding),forKey:bindingKey)
        defaults.synchronize()
    }
    static var hostID: String {
        if let saved = defaults.string(forKey:"stableHostID"), UUID(uuidString:saved) != nil { return saved }
        let value = UUID().uuidString
        defaults.set(value,forKey:"stableHostID"); return value
    }
    static func folder() throws -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RetinaLink",isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        return url
    }
}

struct ProcessResult {
    let status: Int32
    let output: Data
    let error: Data
    var text: String { String(data:output,encoding:.utf8) ?? "" }
    var errorText: String { String(data:error,encoding:.utf8) ?? "" }
}

enum SystemTask {
    // Used only on a utility queue or by bounded non-GUI commands, never on the
    // capture, render or main queues. Credentials go through stdin, not argv.
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil,
                    environment: [String:String]? = nil, timeout: TimeInterval = 30, detachedOutput: Bool = false, detachedErrorFile: URL? = nil) throws -> ProcessResult {
        let process = Process(), output = Pipe(), error = Pipe(), incoming = Pipe()
        process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
        // A background SSH master inherits its parent's descriptors. It must
        // not retain our output pipes and leave collectors waiting forever.
        process.standardOutput = detachedOutput ? FileHandle.nullDevice : output
        process.standardError = detachedOutput ? FileHandle.nullDevice : error
        var detachedError: FileHandle?
        if detachedOutput, let url = detachedErrorFile {
            FileManager.default.createFile(atPath:url.path,contents:Data(),attributes:[.posixPermissions:0o600])
            detachedError = try FileHandle(forWritingTo:url); process.standardError = detachedError
        }
        defer { detachedError?.closeFile() }
        process.standardInput = incoming
        if let environment = environment { process.environment = environment }
        try process.run()
        let group = DispatchGroup(), lock = NSLock()
        var out = Data(), err = Data()
        func collect(_ file: FileHandle, _ isOutput: Bool) {
            group.enter(); DispatchQueue.global(qos:.utility).async {
                defer { group.leave() }
                var bytes = Data()
                while true {
                    let chunk = file.readData(ofLength:16_384)
                    if chunk.isEmpty { break }
                    if bytes.count + chunk.count <= 4*1024*1024 { bytes.append(chunk) }
                    else { process.terminate(); break }
                }
                lock.lock(); if isOutput { out = bytes } else { err = bytes }; lock.unlock()
            }
        }
        if !detachedOutput { collect(output.fileHandleForReading,true); collect(error.fileHandleForReading,false) }
        if let input = input { incoming.fileHandleForWriting.write(input) }
        incoming.fileHandleForWriting.closeFile()
        let deadline = Date(timeIntervalSinceNow:timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval:0.03) }
        if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval:0.1); if process.isRunning { kill(process.processIdentifier,SIGKILL) }; process.waitUntilExit(); group.wait(); throw LinkError.invalid("The iMac did not respond in time. Check its power, network and sign-in screen.") }
        process.waitUntilExit(); group.wait()
        if detachedOutput, let url = detachedErrorFile { err = Data((try? Data(contentsOf:url))?.prefix(4096) ?? Data()) }
        return ProcessResult(status:process.terminationStatus,output:out,error:err)
    }
    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of:"'",with:"'\\''") + "'" }
    static func sshOptionPath(_ text: String) -> String { "\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\"" }
}

enum StartupAgent {
    static func document(executable: String, role: String, arguments: [String] = []) -> [String:Any] {
        ["Label":"local.retinalink.\(role.lowercased()).startup",
         "ProgramArguments":[executable]+arguments,"RunAtLoad":true,
         "KeepAlive":["SuccessfulExit":false],"ThrottleInterval":10,
         "LimitLoadToSessionType":"Aqua","ProcessType":"Interactive",
         "AssociatedBundleIdentifiers":["local.retinalink.\(role)"]]
    }
    static func path(role: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.retinalink.\(role.lowercased()).startup.plist")
    }
    static func install(executable: String, role: String, arguments: [String] = []) throws {
        let url = path(role:role)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let data = try PropertyListSerialization.data(fromPropertyList:document(executable:executable,role:role,arguments:arguments),format:.xml,options:0)
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}

#if !HOST
final class EnrollmentApplication: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = LaunchOptions.value("--apply-enrollment"), let resultPath = LaunchOptions.value("--enrollment-result") else { exit(1) }
        let request = URL(fileURLWithPath:path).standardizedFileURL, result = URL(fileURLWithPath:resultPath).standardizedFileURL
        let allowed = NSHomeDirectory()+"/Library/Application Support/RetinaLink/Install/enroll."
        guard request.path.hasPrefix(allowed), request.lastPathComponent == "request.json",
              result.deletingLastPathComponent() == request.deletingLastPathComponent(), result.lastPathComponent == "result.json" else { exit(1) }
        let response: [String:Any]
        do {
            let values = try request.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 16_384 else { throw LinkError.invalid("Invalid enrollment request file.") }
            let data = try Data(contentsOf:request)
            try FileManager.default.removeItem(at:request)
            response = try LaunchOptions.has("--remove-pairing") ? ViewerEnrollment.remove(data) : ViewerEnrollment.enroll(data,replacing:LaunchOptions.has("--replace-pairing"))
        } catch { try? FileManager.default.removeItem(at:request); response = ["enrolled":false,"error":String(describing:error)] }
        if let data = try? JSONSerialization.data(withJSONObject:response,options:.sortedKeys) {
            try? data.write(to:result,options:.atomic)
            try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:result.path)
        }
        exit(response["enrolled"] as? Bool == true || response["removed"] as? Bool == true ? 0 : 1)
    }
}

enum ViewerEnrollment {
    static let keyMarker = "RetinaLink-tunnel"
    static let restrictions = "restrict,port-forwarding,permitlisten=\"127.0.0.1:58473\",permitopen=\"127.0.0.1:58473\",command=\"/usr/bin/false\""
    static func remove(_ data: Data) throws -> [String:Any] {
        guard data.count <= 1024, let item = try JSONSerialization.jsonObject(with:data) as? [String:String],
              let hostID = item["hostID"], UUID(uuidString:hostID) != nil,
              let binding = DeviceSettings.binding, binding.hostID == hostID else { throw LinkError.invalid("This display belongs to a different Host.") }
        let authorized = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/authorized_keys")
        guard !((try? authorized.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) ?? false) else { throw LinkError.invalid("An administrator must manage this account’s SSH key file.") }
        if let text = try? String(contentsOf:authorized,encoding:.utf8) {
            let kept = text.components(separatedBy:.newlines).filter { !$0.hasSuffix(" "+keyMarker) && !$0.isEmpty }
            try Data((kept.joined(separator:"\n")+"\n").utf8).write(to:authorized,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:authorized.path)
        }
        DeviceVault.remove(DeviceVault.credentialAccount)
        UserDefaults.standard.removeObject(forKey:DeviceSettings.bindingKey)
        UserDefaults.standard.removeObject(forKey:"viewerShortCode"); UserDefaults.standard.removeObject(forKey:"viewerAddress")
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at:StartupAgent.path(role:"Viewer"))
        return ["removed":true,"fileVaultChanged":false,"automaticLoginChanged":false]
    }
    static func enroll(_ data: Data, replacing: Bool = false) throws -> [String:Any] {
        guard data.count <= 16_384 else { throw LinkError.invalid("Enrollment is too large.") }
        let request = try JSONDecoder().decode(EnrollmentRequest.self,from:data); try request.validate()
        guard request.binding.username == NSUserName() else { throw LinkError.invalid("Set up Viewer in the iMac account you signed into.") }
        if let existing = DeviceSettings.binding, existing.hostID != request.binding.hostID, !replacing {
            throw LinkError.invalid("This iMac belongs to another Host. Confirm Replace pairing on the new Host before continuing.")
        }
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let ssh = home.appendingPathComponent(".ssh",isDirectory:true), authorized = ssh.appendingPathComponent("authorized_keys")
        try fm.createDirectory(at:ssh,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        // Preserve every unrelated key. RetinaLink replaces only its own scoped
        // forwarding key; it cannot open a shell, PTY, agent or X11 session.
        let old = fm.fileExists(atPath:authorized.path) ? try String(contentsOf:authorized,encoding:.utf8) : ""
        guard !((try? authorized.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) ?? false) else { throw LinkError.invalid("An administrator must manage this account’s SSH key file.") }
        let kept = old.components(separatedBy:.newlines).filter { !$0.hasSuffix(" "+keyMarker) && !$0.isEmpty }
        let text = (kept + [restrictions+" "+request.tunnelPublicKey]).joined(separator:"\n")+"\n"
        try text.data(using:.utf8)!.write(to:authorized,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:authorized.path)
        try DeviceVault.write(Data(request.credential.utf8),account:DeviceVault.credentialAccount)
        try DeviceSettings.save(request.binding)
        UserDefaults.standard.set(false,forKey:"displayPaused")
        if request.binding.viewerStartup {
            try StartupAgent.install(executable:Bundle.main.executablePath!,role:"Viewer",arguments:["--appliance"])
        } else { try? fm.removeItem(at:StartupAgent.path(role:"Viewer")) }
        DiagnosticLog.shared.record("setup","Trusted display enrollment saved; fullscreen and reconnect enabled; FileVault unchanged")
        return ["enrolled":true,"fileVault":request.binding.fileVault.rawValue,
                "startupAtLogin":request.binding.viewerStartup,"dedicatedDisplay":request.binding.dedicatedDisplay,
                "fileVaultChanged":false,"automaticLoginChanged":false]
    }
}
#endif
