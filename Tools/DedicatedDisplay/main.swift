// Runs once over authenticated SSH + sudo. No setuid binary or persistent root service.
import Foundation
import OpenDirectory
import Security

let fm = FileManager.default
let account = "retinalinkdisplay"
let home = URL(fileURLWithPath:"/Users/"+account)
let state = URL(fileURLWithPath:"/Library/Application Support/RetinaLink/DedicatedDisplay")
let loginDomain = "com.apple.loginwindow" as CFString
var rollbackArmed = false
var committed = false
struct Failure: Error { let message: String }
func require(_ value: Bool, _ message: String) throws { if !value { throw Failure(message:message) } }
func task(_ path: String, _ args: [String]) throws -> String {
    let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath:path); p.arguments = args
    p.standardOutput = pipe; p.standardError = pipe; try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    try require(p.terminationStatus == 0,"A macOS setup command failed: "+URL(fileURLWithPath:path).lastPathComponent)
    return String(data:data,encoding:.utf8) ?? ""
}
func write(_ data: Data, _ url: URL, owner: Int = 0, mode: Int = 0o600) throws {
    // Refuse symlinks in every existing component, including an account home.
    var parent = url
    while parent.path != "/" {
        let attrs = try? fm.attributesOfItem(atPath:parent.path)
        try require(attrs?[.type] as? FileAttributeType != .typeSymbolicLink,"Setup encountered a symbolic link; no settings were changed.")
        parent.deleteLastPathComponent()
    }
    try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try data.write(to:url,options:.atomic)
    try fm.setAttributes([.posixPermissions:mode,.ownerAccountID:owner,.groupOwnerAccountID:owner == 0 ? 0 : 20],ofItemAtPath:url.path)
}
func plist(_ object: Any) throws -> Data { try PropertyListSerialization.data(fromPropertyList:object,format:.xml,options:0) }
func dictionary(_ url: URL) -> [String:Any] { (try? PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil)) as? [String:Any] ?? [:] }
func setLogin(_ value: Any?, key: String) {
    // loginwindow uses the AnyHost domain (/Library/Preferences), not ByHost.
    CFPreferencesSetValue(key as CFString,value as CFPropertyList?,loginDomain,kCFPreferencesAnyUser,kCFPreferencesAnyHost)
    CFPreferencesSynchronize(loginDomain,kCFPreferencesAnyUser,kCFPreferencesAnyHost)
}
func currentLogin() -> String? { CFPreferencesCopyValue("autoLoginUser" as CFString,loginDomain,kCFPreferencesAnyUser,kCFPreferencesAnyHost) as? String }
func checkPolicy() throws {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    try require((v.majorVersion == 10 && v.minorVersion == 15) || v.majorVersion == 11,"Unattended account setup currently supports Intel Catalina and Big Sur. Standard Viewer setup is still available.")
    var cpu = Int32(0); var size = MemoryLayout<Int32>.size
    sysctlbyname("hw.cputype",&cpu,&size,nil,0)
    try require(cpu == 7 || cpu == 0x01000007,"Dedicated account setup requires an Intel iMac.")
    let vault = try task("/usr/bin/fdesetup",["status"])
    try require(vault.contains("FileVault is Off"),"FileVault must already be off for unattended startup. RetinaLink will not change it.")
    let profiles = try task("/usr/bin/profiles",["status","-type","enrollment"])
    try require(!profiles.contains(": Yes"),"This Mac is managed by an organization. Ask its administrator to configure dedicated display login.")
    let installed = try task("/usr/bin/profiles",["list","-output","stdout-xml"])
    // Do not override configuration-profile policy, including locally installed profiles.
    let xml = Data(installed.utf8)
    let profilesObject = (try? PropertyListSerialization.propertyList(from:xml,format:nil)) as? [String:Any] ?? [:]
    try require(profilesObject.isEmpty,"Configuration profiles are installed. Ask the organization administrator to configure this Mac.")
    let managed = URL(fileURLWithPath:"/Library/Managed Preferences")
    let files = fm.enumerator(at:managed,includingPropertiesForKeys:nil)
    while let file = files?.nextObject() as? URL {
        if ["com.apple.loginwindow.plist","com.apple.screensaver.plist"].contains(file.lastPathComponent) {
            try require(dictionary(file).isEmpty,"Login or lock settings are managed. RetinaLink will not override them.")
        }
    }
}
func main() throws -> [String:Any] {
    try require(geteuid() == 0,"An iMac administrator must authorize dedicated display setup.")
    let input = FileHandle.standardInput.readData(ofLength:65_537)
    try require(input.count <= 65_536,"Invalid setup request.")
    guard let request = try JSONSerialization.jsonObject(with:input) as? [String:Any],
          let operation = request["operation"] as? String,
          let hostID = request["hostID"] as? String, UUID(uuidString:hostID) != nil else { throw Failure(message:"Invalid dedicated display request.") }
    if operation != "restore" { try checkPolicy() }
    let marker = state.appendingPathComponent("state.plist")
    let saved = dictionary(marker)
    var newRecordForRollback: ODRecord? = nil
    defer {
        if rollbackArmed && !committed {
            // A preparation failure must never leave partially configured automatic login enabled.
            let recovery = dictionary(marker)
            if recovery["hostID"] as? String == hostID {
                setLogin(recovery["previousAutoLoginUser"],key:"autoLoginUser")
                let kc = URL(fileURLWithPath:"/private/etc/kcpassword")
                if let old = recovery["previousKCPassword"] as? Data { try? write(old,kc) }
                else { try? fm.removeItem(at:kc) }
                if let created = newRecordForRollback {
                    // This account has never reached automatic login; only setup-created files exist.
                    try? created.delete(); try? fm.removeItem(at:home); try? fm.removeItem(at:marker)
                }
            }
        }
    }
    if operation == "restore" {
        try require(saved["hostID"] as? String == hostID,"Only the Host that configured this account can restore its settings.")
        try require(currentLogin() == account || currentLogin() == nil,"Another account now owns automatic login. Its settings were left untouched.")
        setLogin(saved["previousAutoLoginUser"],key:"autoLoginUser")
        let kc = URL(fileURLWithPath:"/private/etc/kcpassword")
        if let old = saved["previousKCPassword"] as? Data { try write(old,kc) }
        else { try? fm.removeItem(at:kc) }
        _ = try task("/usr/bin/sudo",["-H","-u",account,"/usr/bin/defaults","write","com.apple.screensaver","askForPassword","-bool","true"])
        _ = try task("/usr/bin/sudo",["-H","-u",account,"/usr/bin/defaults","-currentHost","write","com.apple.screensaver","idleTime","-int","1200"])
        _ = try task("/usr/bin/sudo",["-H","-u",account,"/usr/bin/defaults","write","local.retinalink.Viewer","dedicatedKeepAwake","-bool","false"])
        let agent = home.appendingPathComponent("Library/LaunchAgents/local.retinalink.viewer.startup.plist")
        try? fm.removeItem(at:agent)
        // Preserve the account and files; deleting an account is a separate owner action.
        if let oldAgent = saved["previousViewerAgent"] as? Data,
           let originalHome = saved["originalHome"] as? String,
           let originalUID = saved["originalUID"] as? Int {
            try write(oldAgent,URL(fileURLWithPath:originalHome).appendingPathComponent("Library/LaunchAgents/local.retinalink.viewer.startup.plist"),owner:originalUID)
        }
        if let uid = saved["uid"] as? Int {
            _ = try? task("/bin/launchctl",["bootout","gui/\(uid)/local.retinalink.viewer.startup"])
        }
        var restored = saved; restored["phase"] = "restored"; try write(try plist(restored),marker)
        return ["restored":true,"accountPreserved":true,"fileVaultChanged":false]
    }
    try require(operation == "configure","Unknown dedicated display operation.")
    guard let enrollment = request["enrollment"] as? [String:Any], let binding = enrollment["binding"] as? [String:Any],
          binding["hostID"] as? String == hostID, binding["username"] as? String == account,
          binding["viewerStartup"] as? Bool == true, binding["dedicatedDisplay"] as? Bool == true,
          let credential = enrollment["credential"] as? String, credential.count == 32,
          credential.allSatisfy({ "0123456789ABCDEF".contains($0) }),
          let key = enrollment["tunnelPublicKey"] as? String, key.hasPrefix("ssh-ed25519 "), key.hasSuffix(" RetinaLink-tunnel"),
          !key.contains("\n"), !key.contains("\r"),
          let source = request["viewerPath"] as? String, source.hasPrefix("/Users/"), source.hasSuffix("/Applications/RetinaLink Viewer.app"),
          let team = request["team"] as? String, team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { throw Failure(message:"Invalid display installation request.") }
    let requirement = "anchor apple generic and identifier \"local.retinalink.Viewer\" and certificate leaf[subject.OU] = \""+team+"\""
    _ = try task("/usr/bin/codesign",["--verify","--strict","--deep","-R="+requirement,source])
    _ = try task("/usr/sbin/spctl",["--assess","--type","execute",source])
    try require(currentLogin() == nil || currentLogin() == account,"Automatic login is already configured for another account. Its settings were left unchanged.")
    let node = try ODNode(session:ODSession.default(),type:UInt32(kODNodeTypeLocalNodes))
    let existing = try? node.record(withRecordType:kODRecordTypeUsers,name:account,attributes:nil)
    if existing != nil {
        try require(saved["hostID"] as? String == hostID,"An account named retinalinkdisplay already exists and was not created by this Host. It was left unchanged.")
        let phase = saved["phase"] as? String
        try require((currentLogin() == account && phase == "ready-for-restart") || (currentLogin() == nil && phase == "restored" && saved["displayKCPassword"] is Data),"This display account needs administrator recovery before it can be configured again. Its password was not reset.")
        let uid = try existing!.values(forAttribute:kODAttributeTypeUniqueID).first as? String
        try require(uid == (saved["uid"] as? Int).map(String.init),"The display account identity changed; it was left untouched.")
    } else {
        try require(saved.isEmpty && !fm.fileExists(atPath:home.path),"An existing display account folder needs administrator review.")
    }
    // Explicit test runs exercise disabling and re-enabling this NEW display
    // setup without another administrator prompt or any password persistence.
    // Child invocations run as the already-authorized root process, with JSON
    // on pipes and no additional privileges or standing root service.
    // Complete every preflight before the first change. Never write a password to argv/logs.
    if existing == nil {
        var random = [UInt8](repeating:0,count:32)
        try require(SecRandomCopyBytes(kSecRandomDefault,random.count,&random) == errSecSuccess,"Could not create a secure account password.")
        let password = random.map { String(format:"%02x",$0) }.joined()
        let query = try ODQuery(node:node,forRecordTypes:kODRecordTypeUsers,attribute:kODAttributeTypeRecordName,matchType:UInt32(kODMatchAny),queryValues:nil,returnAttributes:kODAttributeTypeUniqueID,maximumResults:0)
        let records = try query.resultsAllowingPartial(false) as? [ODRecord] ?? []
        let used = Set(records.compactMap { (try? $0.values(forAttribute:kODAttributeTypeUniqueID))?.first as? String }.compactMap(Int.init))
        guard let uid = (502...999).first(where:{ !used.contains($0) }) else { throw Failure(message:"No available local display account ID.") }
        let attrs: [String:Any] = [kODAttributeTypeFullName:["RetinaLink Display"],kODAttributeTypeUniqueID:[String(uid)],kODAttributeTypePrimaryGroupID:["20"],kODAttributeTypeNFSHomeDirectory:[home.path],kODAttributeTypeUserShell:["/bin/zsh"]]
        var backup: [String:Any] = ["hostID":hostID,"account":account,"uid":uid,"createdAt":Date(),"phase":"preparing"]
        let originalHome = URL(fileURLWithPath:source).deletingLastPathComponent().deletingLastPathComponent()
        let originalAgent = originalHome.appendingPathComponent("Library/LaunchAgents/local.retinalink.viewer.startup.plist")
        if let originalUID = (try fm.attributesOfItem(atPath:originalHome.path)[.ownerAccountID] as? NSNumber)?.intValue,
           originalUID >= 500, originalHome.path != home.path {
            backup["originalHome"] = originalHome.path; backup["originalUID"] = originalUID
            if fm.fileExists(atPath:originalAgent.path) { backup["previousViewerAgent"] = try Data(contentsOf:originalAgent) }
        }
        if let value = currentLogin() { backup["previousAutoLoginUser"] = value }
        if fm.fileExists(atPath:"/private/etc/kcpassword") { backup["previousKCPassword"] = try Data(contentsOf:URL(fileURLWithPath:"/private/etc/kcpassword")) }
        try write(try plist(backup),marker)
        rollbackArmed = true
        var created: ODRecord?
        do {
            let record = try node.createRecord(withRecordType:kODRecordTypeUsers,name:account,attributes:attrs)
            created = record; newRecordForRollback = record; try record.changePassword(nil,toPassword:password)
            _ = try task("/usr/sbin/createhomedir",["-c","-u",account])
            try fm.setAttributes([.posixPermissions:0o700,.ownerAccountID:uid,.groupOwnerAccountID:20],ofItemAtPath:home.path)
            // Apple's legacy loginwindow credential format on Intel Catalina/Big Sur.
            // This intentionally permits physical access, explained before authorization.
            let xor: [UInt8] = [0x7d,0x89,0x52,0x23,0xd2,0xbc,0xdd,0xea,0xa3,0xb9,0x1f]
            var bytes = Array(password.utf8)+[0]
            while bytes.count % xor.count != 0 { bytes.append(0) }
            for i in bytes.indices { bytes[i] ^= xor[i % xor.count] }
            try write(Data(bytes),URL(fileURLWithPath:"/private/etc/kcpassword"))
            // Retain the account's legacy login material in the root-only recovery
            // record so turning the mode off/on never resets its login Keychain.
            backup["displayKCPassword"] = Data(bytes)
            backup["phase"] = "account-created"; try write(try plist(backup),marker)
        } catch {
            // Only a just-created, never-signed-in account can be cleaned up here.
            try? created?.delete()
            if let old = backup["previousKCPassword"] as? Data { try? write(old,URL(fileURLWithPath:"/private/etc/kcpassword")) }
            else { try? fm.removeItem(atPath:"/private/etc/kcpassword") }
            try? fm.removeItem(at:home); try? fm.removeItem(at:marker)
            throw error
        }
    }
    guard let record = try? node.record(withRecordType:kODRecordTypeUsers,name:account,attributes:nil),
          let uidString = try record.values(forAttribute:kODAttributeTypeUniqueID).first as? String, let uid = Int(uidString) else { throw Failure(message:"Could not verify display account.") }
    let membership = try task("/usr/bin/dsmemberutil",["checkmembership","-U",account,"-G","admin"])
    try require(membership.contains("is not a member"),"The display account is an administrator; setup stopped.")
    rollbackArmed = true
    let app = home.appendingPathComponent("Applications/RetinaLink Viewer.app")
    try fm.createDirectory(at:app.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
    let incoming = home.appendingPathComponent("Applications/.retinalink-incoming-"+UUID().uuidString+".app")
    let previous = home.appendingPathComponent("Applications/.retinalink-previous-"+UUID().uuidString+".app")
    defer { try? fm.removeItem(at:incoming); try? fm.removeItem(at:previous) }
    _ = try task("/usr/bin/ditto",[source,incoming.path])
    _ = try task("/usr/bin/codesign",["--verify","--strict","--deep","-R="+requirement,incoming.path])
    _ = try? task("/bin/launchctl",["bootout","gui/\(uid)/local.retinalink.viewer.startup"])
    if fm.fileExists(atPath:app.path) { try fm.moveItem(at:app,to:previous) }
    do { try fm.moveItem(at:incoming,to:app) }
    catch { if fm.fileExists(atPath:previous.path) { try? fm.moveItem(at:previous,to:app) }; throw error }
    _ = try task("/usr/sbin/chown",["-R",account+":staff",home.appendingPathComponent("Applications").path])
    _ = try task("/usr/bin/codesign",["--verify","--strict","--deep","-R="+requirement,app.path])
    let pending = home.appendingPathComponent("Library/Application Support/RetinaLink/dedicated-enrollment.json")
    try write(try JSONSerialization.data(withJSONObject:enrollment,options:.sortedKeys),pending,owner:uid)
    let agent: [String:Any] = ["Label":"local.retinalink.viewer.startup","ProgramArguments":[app.appendingPathComponent("Contents/MacOS/RetinaLink").path,"--appliance"],"RunAtLoad":true,"KeepAlive":["SuccessfulExit":false],"ThrottleInterval":10,"LimitLoadToSessionType":"Aqua","ProcessType":"Interactive","AssociatedBundleIdentifiers":["local.retinalink.Viewer"]]
    try write(try plist(agent),home.appendingPathComponent("Library/LaunchAgents/local.retinalink.viewer.startup.plist"),owner:uid)
    // Per-account lock/idle policy only. Viewer holds an idle-sleep assertion while running.
    for args in [["write","com.apple.screensaver","askForPassword","-bool","false"], ["write","com.apple.screensaver","askForPasswordDelay","-int","0"], ["-currentHost","write","com.apple.screensaver","idleTime","-int","0"], ["write","com.apple.loginwindow","autoLogOutDelay","-int","0"], ["write","local.retinalink.Viewer","dedicatedKeepAwake","-bool","true"], ["write","com.apple.SetupAssistant","DidSeeCloudSetup","-bool","true"], ["write","com.apple.SetupAssistant","DidSeeSiriSetup","-bool","true"], ["write","com.apple.SetupAssistant","LastSeenCloudProductVersion","-string",try task("/usr/bin/sw_vers",["-productVersion"]).trimmingCharacters(in:.whitespacesAndNewlines)]] {
        _ = try task("/usr/bin/sudo",["-H","-u",account,"/usr/bin/defaults"]+args)
    }
    for key in ["DidSeeSyncSetup","DidSeePrivacy","DidSeeTouchIDSetup","DidSeeTrueTonePrivacy","DidSeeScreenTime","DidSeeAppearanceSetup","DidSeeAccessibility"] {
        _ = try task("/usr/bin/sudo",["-H","-u",account,"/usr/bin/defaults","write","com.apple.SetupAssistant",key,"-bool","true"])
    }
    let ssh = home.appendingPathComponent(".ssh/authorized_keys")
    let restricted = "restrict,port-forwarding,permitlisten=\"127.0.0.1:58473\",permitopen=\"127.0.0.1:58473\",command=\"/usr/bin/false\" "+key+"\n"
    // This new account receives only a tunnel key, never an SSH shell credential.
    let oldKeys = (try? String(contentsOf:ssh,encoding:.utf8)) ?? ""
    let keptKeys = oldKeys.components(separatedBy:.newlines).filter { !$0.isEmpty && !$0.hasSuffix(" RetinaLink-tunnel") }
    try write(Data((keptKeys.joined(separator:"\n")+(keptKeys.isEmpty ? "" : "\n")+restricted).utf8),ssh,owner:uid)
    // Explicit integration-test option only: a temporary, forced-command public key.
    // It can read non-secret diagnostics, restart ONLY Viewer, and delete itself.
    // No shell, forwarding, administrator authorization, or pixels are accessible.
    if let testKey = request["testPublicKey"] as? String {
        let parts = testKey.split(separator:" ")
        try require(parts.count == 3 && parts[0] == "ssh-ed25519" && parts[2] == "RetinaLink-dedicated-test" && Data(base64Encoded:String(parts[1]))?.count == 51 && !testKey.contains("\n"),"Invalid diagnostic test key.")
        let script = home.appendingPathComponent(".retinalink-test.sh")
        let scriptBody = """
        #!/bin/sh
        set -eu
        case "${SSH_ORIGINAL_COMMAND:-status}" in
          status)
            /usr/bin/printf 'RETINALINK_SETUP\\n'
            /bin/cat "$HOME/Library/Logs/RetinaLink/dedicated-setup.json"
            /usr/bin/printf '\\nRETINALINK_UI\\n'
            /bin/cat "$HOME/Library/Logs/RetinaLink/Viewer-ui.json" 2>/dev/null || true
            /usr/bin/printf '\\nRETINALINK_CONSOLE\\n'
            /usr/bin/stat -f '%Su' /dev/console
            /usr/bin/printf 'RETINALINK_FILEVAULT\\n'
            /usr/bin/fdesetup status
            /usr/bin/printf 'RETINALINK_LOCK\\n'
            /usr/bin/defaults read com.apple.screensaver askForPassword
            /usr/sbin/sysadminctl -screenLock status 2>&1
            /usr/bin/printf 'RETINALINK_IDLE\\n'
            /usr/bin/defaults -currentHost read com.apple.screensaver idleTime
            /usr/bin/printf 'RETINALINK_ADMIN\\n'
            /usr/bin/dsmemberutil checkmembership -U retinalinkdisplay -G admin
            /usr/bin/printf 'RETINALINK_PENDING\\n'
            if [ -e "$HOME/Library/Application Support/RetinaLink/dedicated-enrollment.json" ]; then echo pending; else echo consumed; fi
            /usr/bin/printf 'RETINALINK_ASSERTIONS\\n'
            /usr/bin/pmset -g assertions
            ;;
          restart-viewer) /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/local.retinalink.viewer.startup" ;;
          wake) /usr/bin/caffeinate -u -t 2 ;;
          sleep-wake) /usr/bin/pmset displaysleepnow; /bin/sleep 3; /usr/bin/caffeinate -u -t 2 ;;
          cleanup)
            keyfile="$HOME/.ssh/authorized_keys"
            /usr/bin/sed '/ RetinaLink-dedicated-test$/d' "$keyfile" > "$keyfile.next"
            /bin/chmod 600 "$keyfile.next"; /bin/mv "$keyfile.next" "$keyfile"
            /bin/rm -f "$HOME/.retinalink-test.sh"
            ;;
          *) exit 64 ;;
        esac
        """
        try write(Data(scriptBody.utf8),script,owner:uid,mode:0o700)
        let command = "restrict,command=\"/bin/sh /Users/retinalinkdisplay/.retinalink-test.sh\" "+testKey+"\n"
        var keys = try String(contentsOf:ssh,encoding:.utf8)
        keys = keys.components(separatedBy:.newlines).filter { !$0.isEmpty && !$0.hasSuffix(" RetinaLink-dedicated-test") }.joined(separator:"\n")+"\n"+command
        try write(Data(keys.utf8),ssh,owner:uid)
    }
    if let sshGroup = try? node.record(withRecordType:kODRecordTypeGroups,name:"com.apple.access_ssh",attributes:nil) { try sshGroup.addMemberRecord(record) }
    // Correct ownership on parent folders created by root for this NEW account.
    for path in ["Library/LaunchAgents","Library/Application Support/RetinaLink","Library/Application Support","Library/Preferences",".ssh"] {
        let folder = home.appendingPathComponent(path)
        if fm.fileExists(atPath:folder.path) { try fm.setAttributes([.ownerAccountID:uid,.groupOwnerAccountID:20,.posixPermissions:0o700],ofItemAtPath:folder.path) }
    }
    try checkPolicy() // Fail closed if FileVault/policy changed during preparation.
    var completed = dictionary(marker); completed["phase"] = "ready-for-restart"; try write(try plist(completed),marker)
    if let kc = completed["displayKCPassword"] as? Data { try write(kc,URL(fileURLWithPath:"/private/etc/kcpassword")) }
    setLogin(account,key:"autoLoginUser")
    try require(currentLogin() == account,"macOS did not accept automatic login.")
    if let originalHome = completed["originalHome"] as? String {
        let originalAgent = URL(fileURLWithPath:originalHome).appendingPathComponent("Library/LaunchAgents/local.retinalink.viewer.startup.plist")
        try? fm.removeItem(at:originalAgent)
    }
    committed = true
    var proof: [String:Any] = ["configured":true,"account":account,"uid":uid,"administrator":false,"automaticLogin":true,"lockPasswordRequired":false,"viewerStartsAtLogin":true,"restartRequired":true,"fileVaultChanged":false]
    if request["testPublicKey"] != nil && ProcessInfo.processInfo.environment["RETINALINK_RECOVERY_CHILD"] != "1" {
        for operation in ["restore","configure"] {
            var childRequest = request; childRequest["operation"] = operation
            let child = Process(), incoming = Pipe(), output = Pipe()
            child.executableURL = URL(fileURLWithPath:CommandLine.arguments[0])
            var environment = ProcessInfo.processInfo.environment; environment["RETINALINK_RECOVERY_CHILD"] = "1"; child.environment = environment
            child.standardInput = incoming; child.standardOutput = output; child.standardError = FileHandle.nullDevice
            try child.run(); incoming.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject:childRequest)); incoming.fileHandleForWriting.closeFile()
            let data = output.fileHandleForReading.readDataToEndOfFile(); child.waitUntilExit()
            let response = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            try require(child.terminationStatus == 0 && response?[operation == "restore" ? "restored" : "configured"] as? Bool == true,"The dedicated setup recovery test failed. Restore its login settings before continuing.")
        }
        proof["recoveryCycleVerified"] = true
    }
    try write(try JSONSerialization.data(withJSONObject:proof,options:.sortedKeys),home.appendingPathComponent("Library/Logs/RetinaLink/dedicated-setup.json"),owner:uid)
    try fm.setAttributes([.ownerAccountID:uid,.groupOwnerAccountID:20,.posixPermissions:0o700],ofItemAtPath:home.appendingPathComponent("Library/Logs/RetinaLink").path)
    return proof
}
do {
    let result = try main(); FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result,options:.sortedKeys)); print("")
} catch {
    // Never print NSError userInfo/arguments, input payload, account passwords or enrollment.
    let message = (error as? Failure)?.message ?? "Dedicated display setup could not complete. Automatic login may not be enabled. Restore settings from Host before retrying."
    let data = try! JSONSerialization.data(withJSONObject:["configured":false,"error":message],options:.sortedKeys)
    FileHandle.standardOutput.write(data); print(""); exit(1)
}
