import AppKit

if ProcessInfo.processInfo.environment["RETINALINK_SSH_ASKPASS"] == "1" { runSSHAskpass() }

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
app.setActivationPolicy(.regular)
#if HOST
let delegate = HostApp()
#else
let delegate = ViewerApp()
#endif
app.delegate = delegate
app.run()
