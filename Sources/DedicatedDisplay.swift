import AppKit
#if HOST
struct DedicatedDisplayResult: Decodable {
    let configured: Bool?
    let restored: Bool?
    let account: String?
    let restartRequired: Bool?
    let error: String?
}

extension SetupConnection {
    // Administrator password is carried on SSH stdin only. Never store in defaults,
    // Keychain, process arguments, diagnostics, temporary files or a control command.
    func configureDedicatedDisplay(_ enrollment: EnrollmentRequest, administratorPassword: String, operation: String = "configure") throws -> DedicatedDisplayResult {
        guard let team = DistributionTrust.team,
              let helper = Bundle.main.url(forResource:"RetinaLinkDedicatedSetup",withExtension:nil) else {
            throw LinkError.invalid("Dedicated display setup requires the complete Developer ID release.")
        }
        try ensure()
        let remote = ".retinalink-dedicated-"+UUID().uuidString
        let destination = target.username+"@"+(target.address.contains(":") ? "["+target.address+"]" : target.address)+":"+remote
        let copy = try SystemTask.run("/usr/bin/scp",["-q","-o","ControlPath="+SystemTask.sshOptionPath(socket),"-o","BatchMode=yes",helper.path,destination],timeout:60)
        guard copy.status == 0 else { throw LinkError.invalid("Could not send the signed account setup helper to the iMac.") }
        defer { _ = try? execute("/bin/rm -f \"$HOME/\(remote)\"") }
        let requirement = "anchor apple generic and identifier \"local.retinalink.DedicatedSetup\" and certificate leaf[subject.OU] = \""+team+"\""
        _ = try execute("/bin/chmod 700 \"$HOME/\(remote)\"; /usr/bin/codesign --verify --strict -R="+SystemTask.shellQuote(requirement)+" \"$HOME/\(remote)\"")
        let object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(enrollment))
        let source = try execute("/usr/bin/printf '%s' \"$HOME/Applications/RetinaLink Viewer.app\"").text
        var request: [String:Any] = ["operation":operation,"hostID":enrollment.binding.hostID,"enrollment":object,"viewerPath":source,"team":team]
        if let file = LaunchOptions.value("--dedicated-test-public-key") {
            request["testPublicKey"] = try String(contentsOfFile:file,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        let data = try JSONSerialization.data(withJSONObject:request,options:.sortedKeys)
        guard !administratorPassword.isEmpty, !administratorPassword.contains("\n"), !administratorPassword.contains("\r") else { throw LinkError.invalid("Enter the iMac administrator’s password.") }
        var input = Data((administratorPassword+"\n").utf8); input.append(data)
        defer { input.resetBytes(in:input.indices) }
        // sudo reads exactly its password line, then the helper reads the JSON body.
        // -k avoids a cached sudo timestamp consuming the JSON as a password.
        let output = try SystemTask.run("/usr/bin/ssh",base+["/usr/bin/sudo -S -k -p '' -- \"$HOME/\(remote)\""],input:input,timeout:180)
        guard let result = try? JSONDecoder().decode(DedicatedDisplayResult.self,from:output.output) else {
            throw LinkError.invalid("Administrator authorization failed or setup could not start. Check the iMac administrator password and try again.")
        }
        guard output.status == 0, (operation == "restore" ? result.restored == true : result.configured == true) else { throw LinkError.invalid(result.error ?? "Dedicated display setup did not complete.") }
        return result
    }
}
#else
import IOKit.pwr_mgt

enum DedicatedViewerStartup {
    static var sleepAssertion: IOPMAssertionID = 0
    static func applyPendingEnrollment() throws {
        let file = try DeviceSettings.folder().appendingPathComponent("dedicated-enrollment.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        let values = try file.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey])
        let attrs = try FileManager.default.attributesOfItem(atPath:file.path)
        guard NSUserName() == "retinalinkdisplay", values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 16_384,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
            throw LinkError.invalid("Dedicated display enrollment needs administrator review.")
        }
        let data = try Data(contentsOf:file)
        _ = try ViewerEnrollment.enroll(data)
        // Remove the one-time request only after Keychain + pairing are committed.
        try FileManager.default.removeItem(at:file)
        DiagnosticLog.shared.record("setup","Dedicated account enrolled on first sign-in; FileVault unchanged")
    }
    static func keepReady() {
        guard sleepAssertion == 0, NSUserName() == "retinalinkdisplay", DeviceSettings.binding?.dedicatedDisplay == true,
              UserDefaults.standard.bool(forKey:"dedicatedKeepAwake") else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),"RetinaLink dedicated display" as CFString,&sleepAssertion)
    }
    static func release() { if sleepAssertion != 0 { IOPMAssertionRelease(sleepAssertion); sleepAssertion = 0 } }
}
#endif
