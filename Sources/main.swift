import AppKit

if ProcessInfo.processInfo.environment["RETINALINK_SSH_ASKPASS"] == "1" { runSSHAskpass() }
if LaunchOptions.has("--update-relay-test") {
    do { try runUpdateRelayTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}

if LaunchOptions.has("--usb-link-status") {
    // Read-only SSH diagnostic. Hardware presence alone never means that a
    // cable is connected, or that the peer is the trusted RetinaLink Mac.
    let observations = USBLinkInterfaces.snapshot(), states = DirectLinkInterfaceState.snapshot()
    let interfaces:[[String:Any]] = observations.keys.sorted().map { name in
        let observation = observations[name]!, state = states[name]
        var value:[String:Any] = ["interface":name,"usbEvidence":observation.source.rawValue,
            "interfaceUp":state?.isUp == true,"hasLinkLocalAddress":state?.hasLinkLocal == true,
            "automaticAddressing":state?.automaticAddressing == true]
        if let active = observation.linkActive { value["linkActive"] = active }
        if let speed = observation.nominalLinkSpeed { value["nominalLinkSpeed"] = speed }
        return value
    }
    let report:[String:Any] = ["schema":1,"version":LaunchOptions.version,"build":LaunchOptions.build,
        "interfaces":interfaces,"networkSettingsChanged":false,"pairingAccessed":false,
        "peerAuthenticated":false,"readOnly":true]
    do { FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted])); print(""); exit(0) }
    catch { fputs("USB interface observations could not be encoded.\n",stderr); exit(1) }
}

if LaunchOptions.has("--pairing-recovery-test") {
    guard DeviceSettings.nativeTestScope != nil else { fputs("An isolated native test scope is required.\n",stderr); exit(2) }
    do { try runPairingRecoveryTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
if LaunchOptions.has("--native-test-harness") {
    guard DeviceSettings.nativeTestScope != nil else { exit(2) }
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    let delegate = NativeTestHarness(); app.delegate = delegate; app.run(); exit(0)
}
if LaunchOptions.has("--native-pairing-test") {
    do { try runNativeTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
if LaunchOptions.has("--direct-link-probe") {
    do { try runDirectLinkProbe(); exit(0) } catch { fputs("\(error)\n",stderr); exit(1) }
}

#if !HOST
if LaunchOptions.has("--device-status") {
    // Non-secret update metadata only. No Keychain access or credential export.
    do { FileHandle.standardOutput.write(try JSONEncoder().encode(DeviceSoftwareStatus.current())); print(""); exit(0) }
    catch { fputs("\(error)\n",stderr); exit(1) }
}
if LaunchOptions.has("--apply-enrollment") {
    // Launch Services puts this short-lived enrollment helper in the signed-in
    // user's security session, where its login Keychain is available.
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let delegate = EnrollmentApplication(); app.delegate = delegate; app.run(); exit(0)
}
if LaunchOptions.has("--enroll-stdin") {
    do {
        let data = FileHandle.standardInput.readData(ofLength:16_385)
        let result = try ViewerEnrollment.enroll(data,replacing:LaunchOptions.has("--replace-pairing"))
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result,options:.sortedKeys)); print(""); exit(0)
    } catch { fputs("\(error)\n",stderr); exit(1) }
}
#endif

if CommandLine.arguments.contains("--transport-test") {
    do { try runTransportTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}

if CommandLine.arguments.contains("--pairing-test") {
    do { try runPairingTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--render-test") {
    do { try testViewerPresentation(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--list-displays") {
    var ids = [CGDirectDisplayID](repeating:0,count:32), count: UInt32 = 0
    CGGetOnlineDisplayList(32,&ids,&count)
    for id in ids.prefix(Int(count)) {
        if let m = CGDisplayCopyDisplayMode(id) { print("Display \(id): vendor \(CGDisplayVendorNumber(id)), \(m.pixelWidth)×\(m.pixelHeight)") }
    }
    exit(0)
}
if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
#if HOST
if CommandLine.arguments.contains("--permission-test") {
    do { try runPermissionTests(); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
if CommandLine.arguments.contains("--probe-display") {
    do {
        let display = try RLVirtualDisplay(width:5120,height:2880,rate:60)
        RunLoop.current.run(until:Date(timeIntervalSinceNow:1))
        guard let mode = CGDisplayCopyDisplayMode(display.displayID) else { throw LinkError.invalid("No mode") }
        print("Virtual display: \(mode.width)×\(mode.height) logical, \(mode.pixelWidth)×\(mode.pixelHeight) physical, \(mode.refreshRate) Hz")
        guard mode.pixelWidth == 5120, mode.pixelHeight == 2880 else { throw LinkError.invalid("Incorrect native mode") }
        print("PASS: native 5K virtual display. Process exit releases it.")
        exit(0)
    } catch { fputs("FAIL: \(error)\n",stderr); exit(1) }
}
#endif
let app = NSApplication.shared
#if HOST
// Start without a Dock flash. Manual launches promote when presenting controls;
// login-agent launches stay in the menu bar without stealing focus.
app.setActivationPolicy(.accessory)
let delegate = HostApp()
#else
app.setActivationPolicy(.regular)
let delegate = ViewerApp()
#endif
app.delegate = delegate
app.run()
