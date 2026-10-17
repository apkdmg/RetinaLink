import AppKit

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
