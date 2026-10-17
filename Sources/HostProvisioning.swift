#if HOST
import AppKit
import CryptoKit

struct SetupTarget {
    var address: String
    var username: String
    var managementSocket: String?
    func validate() throws {
        guard DeviceBinding.validAddress(address), DeviceBinding.validUsername(username) else {
            throw LinkError.invalid("Enter the iMac’s local name or IP address and its account’s short username.")
        }
    }
}

struct ViewerPreflight: Codable {
    var name: String
    var version: String
    var fileVault: FileVaultState
    var automaticLoginConfigured: Bool
}

final class SetupConnection {
    let target: SetupTarget
    let folder: URL
    let socket: String
    let knownHosts: String
    init(_ target: SetupTarget) throws {
        try target.validate(); self.target = target
        folder = try DeviceSettings.folder()
        let suffix = SHA256.hash(data:Data((target.username+"@"+target.address).utf8)).prefix(8).map { String(format:"%02x",$0) }.joined()
        socket = target.managementSocket ?? folder.appendingPathComponent("setup-"+suffix).path
        knownHosts = folder.appendingPathComponent("known_hosts").path
    }
    var base: [String] { ["-S",socket,"-o","BatchMode=yes","-o","ConnectTimeout=8","-o","ForwardAgent=no","-l",target.username,target.address] }
    func ensure() throws {
        let check = try SystemTask.run("/usr/bin/ssh",["-S",socket,"-O","check","-o","BatchMode=yes","-l",target.username,target.address],timeout:10)
        if check.status == 0 { return }
        guard target.managementSocket == nil else { throw LinkError.invalid("The existing setup connection has ended. Reconnect using Add Display.") }
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = Bundle.main.executablePath!
        environment["SSH_ASKPASS_REQUIRE"] = "force"; environment["DISPLAY"] = "RetinaLink"
        environment["RETINALINK_SSH_ASKPASS"] = "1"
        let result = try SystemTask.run("/usr/bin/ssh",["-M","-S",socket,"-fN","-o","ControlPersist=10m","-o","StrictHostKeyChecking=ask","-o","UserKnownHostsFile="+SystemTask.sshOptionPath(knownHosts),"-o","UpdateHostKeys=no","-o","ForwardAgent=no","-o","ConnectTimeout=10","-o","NumberOfPasswordPrompts=2","-l",target.username,target.address],environment:environment,timeout:180,detachedOutput:true,detachedErrorFile:folder.appendingPathComponent("setup-connection.log"))
        guard result.status == 0 else { throw LinkError.invalid("Could not sign in to the iMac. Enable Remote Login on it once, then check its address and account.\n"+String(result.errorText.prefix(500))) }
    }
    func execute(_ command: String, input: Data? = nil, timeout: TimeInterval = 40) throws -> ProcessResult {
        let result = try SystemTask.run("/usr/bin/ssh",base+[command],input:input,timeout:timeout)
        guard result.status == 0 else { throw LinkError.invalid("The iMac could not finish setup.\n"+String(result.errorText.prefix(700))) }
        return result
    }
    func inspect() throws -> ViewerPreflight {
        try ensure()
        let result = try execute("""
        /usr/bin/printf 'RETINALINK_PREFLIGHT\\n'
        LANG=C /usr/bin/fdesetup status
        /usr/bin/printf '\\nRETINALINK_VERSION\\n'
        /usr/bin/sw_vers -productVersion
        /usr/bin/printf 'RETINALINK_NAME\\n'
        /usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname
        /usr/bin/printf 'RETINALINK_AUTOLOGIN\\n'
        /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
        """)
        func field(_ name: String) -> String {
            let parts = result.text.components(separatedBy:name+"\n")
            return parts.count > 1 ? String(parts[1].components(separatedBy:"\n").first ?? "") : ""
        }
        let version = field("RETINALINK_VERSION"), pieces = version.split(separator:".").compactMap { Int($0) }
        guard pieces.count >= 2, pieces[0] > 10 || (pieces[0] == 10 && pieces[1] >= 15) else { throw LinkError.invalid("Viewer needs macOS Catalina 10.15 or later. This iMac reports \(version).") }
        return ViewerPreflight(name:String(field("RETINALINK_NAME").prefix(160)),version:version,fileVault:FileVaultState(output:field("RETINALINK_PREFLIGHT")),automaticLoginConfigured:field("RETINALINK_AUTOLOGIN")==target.username)
    }
    func pinServerIdentity() throws {
        // Fetch public host keys through the already authenticated connection;
        // never trust a fresh network scan to silently enroll a different Mac.
        let result = try execute("/bin/cat /etc/ssh/ssh_host_ed25519_key.pub")
        let parts = result.text.split(whereSeparator:{$0.isWhitespace})
        guard parts.count >= 2, parts[0] == "ssh-ed25519", Data(base64Encoded:String(parts[1])) != nil else { throw LinkError.invalid("Could not verify the iMac’s secure connection identity.") }
        let key = target.address+" "+parts[0]+" "+parts[1]
        let url = URL(fileURLWithPath:knownHosts)
        let old = (try? String(contentsOf:url,encoding:.utf8)) ?? ""
        let entries = old.components(separatedBy:.newlines).filter { !$0.hasPrefix(target.address+" ") && !$0.isEmpty }
        try Data((entries+[key]).joined(separator:"\n").appending("\n").utf8).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:knownHosts)
    }
    func transferViewer() throws {
        guard let archive = Bundle.main.url(forResource:"RetinaLink Viewer",withExtension:"zip") else { throw LinkError.invalid("This Host is missing its Viewer installer. Use the complete RetinaLink Host app.") }
        let remote = ".retinalink-viewer-"+UUID().uuidString+".zip"
        let destination = target.username+"@"+(target.address.contains(":") ? "["+target.address+"]" : target.address)+":"+remote
        let result = try SystemTask.run("/usr/bin/scp",["-q","-o","ControlPath="+SystemTask.sshOptionPath(socket),"-o","BatchMode=yes","-o","ConnectTimeout=8",archive.path,destination],timeout:120)
        guard result.status == 0 else { throw LinkError.invalid("Viewer could not be copied to the iMac.\n"+String(result.errorText.prefix(400))) }
        let quoted = SystemTask.shellQuote(remote)
        _ = try execute("""
        set -eu
        /bin/mkdir -p "$HOME/Applications" "$HOME/Library/Application Support/RetinaLink/Install"
        /bin/chmod 700 "$HOME/Library/Application Support/RetinaLink/Install"
        staging=$(/usr/bin/mktemp -d "$HOME/Library/Application Support/RetinaLink/Install/incoming.XXXXXX")
        trap '/bin/rm -f "$HOME/"\(quoted)' EXIT
        /usr/bin/ditto -x -k "$HOME/"\(quoted) "$staging"
        incoming="$staging/RetinaLink Viewer.app"
        /usr/bin/codesign --verify --deep --strict "$incoming"
        identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$incoming/Contents/Info.plist")
        [ "$identity" = 'local.retinalink.Viewer' ]
        /bin/launchctl bootout "gui/$(/usr/bin/id -u)/local.retinalink.viewer.startup" 2>/dev/null || true
        for pid in $(/usr/bin/pgrep -x RetinaLink || true); do
            command=$(/bin/ps -p "$pid" -o command= || true)
            case "$command" in
              "$HOME/Applications/RetinaLink"*"Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -TERM "$pid" ;;
            esac
        done
        /bin/sleep 1
        current="$HOME/Applications/RetinaLink Viewer.app"
        if [ -e "$current" ]; then
            identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$current/Contents/Info.plist")
            [ "$identity" = 'local.retinalink.Viewer' ]
            /bin/mv "$current" "$staging/previous.app"
        fi
        /bin/mv "$incoming" "$current"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$current"
        """,timeout:60)
    }
    func enroll(_ request: EnrollmentRequest, replacing: Bool) throws {
        try request.validate()
        let result = try apply(JSONEncoder().encode(request),flags:replacing ? " --replace-pairing" : "")
        guard result["enrolled"] as? Bool == true else { throw LinkError.invalid(result["error"] as? String ?? "The iMac could not save its pairing. Sign in and unlock its login Keychain, then retry.") }
    }
    func removeBinding(_ hostID: String) throws {
        let result = try apply(JSONSerialization.data(withJSONObject:["hostID":hostID]),flags:" --remove-pairing")
        guard result["removed"] as? Bool == true else { throw LinkError.invalid(result["error"] as? String ?? "Could not remove pairing from the iMac.") }
        _ = try execute("/bin/launchctl bootout \"gui/$(/usr/bin/id -u)/local.retinalink.viewer.startup\" 2>/dev/null || true; /usr/bin/open \"$HOME/Applications/RetinaLink Viewer.app\" --args --appliance")
    }
    private func apply(_ data: Data, flags: String) throws -> [String:Any] {
        let response = try execute("""
        set -eu
        umask 077
        directory=$(/usr/bin/mktemp -d "$HOME/Library/Application Support/RetinaLink/Install/enroll.XXXXXX")
        trap '/bin/rm -rf "$directory"' EXIT
        /bin/cat > "$directory/request.json"
        /usr/bin/open -n "$HOME/Applications/RetinaLink Viewer.app" --args --apply-enrollment "$directory/request.json" --enrollment-result "$directory/result.json"\(flags)
        attempts=0
        while [ "$attempts" -lt 90 ]; do
            if [ -f "$directory/result.json" ]; then /bin/cat "$directory/result.json"; exit 0; fi
            attempts=$((attempts+1))
            /bin/sleep 1
        done
        /usr/bin/printf 'Enrollment needs the iMac signed in with its login Keychain unlocked.\\n' >&2
        exit 1
        """,input:data,timeout:100)
        guard let result = try JSONSerialization.jsonObject(with:response.output) as? [String:Any] else { throw LinkError.invalid("Invalid response from the iMac.") }
        return result
    }
    func startViewer(startup: Bool) throws {
        if startup {
            _ = try execute("/bin/launchctl enable \"gui/$(/usr/bin/id -u)/local.retinalink.viewer.startup\"; /bin/launchctl bootstrap \"gui/$(/usr/bin/id -u)\" \"$HOME/Library/LaunchAgents/local.retinalink.viewer.startup.plist\"")
        } else {
            _ = try execute("/usr/bin/open \"$HOME/Applications/RetinaLink Viewer.app\" --args --appliance")
        }
    }
    func releaseOldForward() {
        _ = try? SystemTask.run("/usr/bin/ssh",["-S",socket,"-O","cancel","-R","127.0.0.1:58473:127.0.0.1:58473","-o","BatchMode=yes","-l",target.username,target.address],timeout:10)
        if let folder = try? DeviceSettings.folder() {
            _ = try? SystemTask.run("/usr/bin/ssh",["-S",folder.appendingPathComponent("display-tunnel").path,"-O","exit","-o","BatchMode=yes","-l",target.username,target.address],timeout:10)
        }
    }
}

enum TunnelIdentity {
    static let account = "host-tunnel-private-key"
    static func create() throws -> (publicKey: String, privateKey: Data) {
        let directory = try DeviceSettings.folder().appendingPathComponent("key-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:directory) }
        let file = directory.appendingPathComponent("identity")
        let result = try SystemTask.run("/usr/bin/ssh-keygen",["-q","-t","ed25519","-N","","-C","RetinaLink-tunnel","-f",file.path])
        guard result.status == 0 else { throw LinkError.invalid("Could not create the display’s connection identity.") }
        return (try String(contentsOf:file.appendingPathExtension("pub"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines),try Data(contentsOf:file))
    }
}

final class TunnelSupervisor {
    private let queue = DispatchQueue(label:"retinalink.display-connection",qos:.utility)
    private var timer: DispatchSourceTimer?
    private var active = true
    var onState: ((String) -> Void)?
    func start() {
        let timer = DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now(),repeating:12)
        timer.setEventHandler { [weak self] in self?.ensure() }; self.timer = timer; timer.resume()
    }
    func stop() { queue.async { self.active = false; self.timer?.cancel(); self.timer = nil } }
    private func ensure() {
        guard active, let binding = DeviceSettings.binding else { return }
        do {
            let folder = try DeviceSettings.folder(), socket = folder.appendingPathComponent("display-tunnel").path
            let check = try SystemTask.run("/usr/bin/ssh",["-S",socket,"-O","check","-o","BatchMode=yes","-l",binding.username,binding.address],timeout:10)
            if check.status == 0 { return }
            guard let key = try DeviceVault.read(TunnelIdentity.account) else { throw LinkError.invalid("Set up this display again to restore its secure connection.") }
            let temporary = folder.appendingPathComponent("identity-"+UUID().uuidString)
            try key.write(to:temporary,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:temporary.path)
            defer { try? FileManager.default.removeItem(at:temporary) }
            let result = try SystemTask.run("/usr/bin/ssh",["-M","-S",socket,"-fN","-i",temporary.path,"-o","IdentitiesOnly=yes","-o","BatchMode=yes","-o","StrictHostKeyChecking=yes","-o","UserKnownHostsFile="+SystemTask.sshOptionPath(folder.appendingPathComponent("known_hosts").path),"-o","UpdateHostKeys=no","-o","ForwardAgent=no","-o","ConnectTimeout=6","-o","ExitOnForwardFailure=yes","-o","ServerAliveInterval=10","-o","ServerAliveCountMax=2","-R","127.0.0.1:58473:127.0.0.1:58473","-l",binding.username,binding.address],timeout:12,detachedOutput:true,detachedErrorFile:folder.appendingPathComponent("display-connection.log"))
            guard result.status == 0 else { throw LinkError.invalid("Waiting for your iMac. It may be asleep, offline, or waiting for FileVault unlock or sign-in.\n"+String(result.errorText.prefix(240))) }
            onState?("Secure display connection ready")
        } catch { onState?(String(describing:error)) }
    }
    deinit { timer?.cancel() }
}
#endif
