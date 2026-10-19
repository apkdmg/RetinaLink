import AppKit

// Exercises real AppKit windows and activation policies without screen capture,
// production preferences, Keychain, pairing, network access or an updater.
final class LifecycleTest: NSObject, NSApplicationDelegate {
    let suite = "local.retinalink.HostWindowTest."+UUID().uuidString
    var defaults: UserDefaults!
    var home: NSWindow!, auxiliary: NSWindow!
    var item: NSStatusItem!, lifecycle: HostWindowLifecycle!
    var passed: [String] = []
    var finished = false
    let output: URL
    init(output: URL) { self.output = output; super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults = UserDefaults(suiteName:suite)!
        home = makeWindow("RetinaLink lifecycle test")
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName:"display.2",accessibilityDescription:"RetinaLink test")
        lifecycle = HostWindowLifecycle(home:home,statusItem:item,defaults:defaults)
        lifecycle.start(background:true)
        expect(NSApp.activationPolicy() == .accessory && !home.isVisible,"Login startup stays hidden without a Dock icon")
        lifecycle.showHome()
        later {
            self.expect(NSApp.activationPolicy() == .regular && self.home.isVisible,"Opening controls restores window and Dock policy")
            self.home.performClose(nil)
            self.later {
                self.expect(NSApp.activationPolicy() == .accessory && !self.home.isVisible,"Red close hides window and Dock without terminating")
                self.expect(self.defaults.bool(forKey:HostWindowLifecycle.hintKey),"First close presents and records the menu-bar hint")
                self.expect(self.item.button?.window != nil,"Menu-bar access remains available after closing")
                self.lifecycle.showHome()
                self.later {
                    self.expect(self.lifecycle.metadata["hintVisible"] as? Bool == false,"Reopening dismisses the hint")
                    self.home.performClose(nil)
                    self.later {
                        self.expect(NSApp.activationPolicy() == .accessory && self.lifecycle.metadata["hintVisible"] as? Bool == false,"Later closes do not repeat the hint")
                        self.testAuxiliaryWindow()
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+25) { if !self.finished { self.fail("Native lifecycle test timed out") } }
    }
    func testAuxiliaryWindow() {
        lifecycle.prepareForControls()
        auxiliary = makeWindow("Setup window")
        auxiliary.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        lifecycle.showHome()
        later {
            self.home.performClose(nil)
            self.later {
                self.expect(self.auxiliary.isVisible && NSApp.activationPolicy() == .regular,"An open setup window keeps normal Dock navigation")
                self.auxiliary.performClose(nil)
                self.later {
                    self.expect(NSApp.activationPolicy() == .accessory,"Closing the final setup window returns to menu-bar mode")
                    self.lifecycle.showHome(); self.home.miniaturize(nil)
                    self.later(1) {
                        self.expect(self.home.isMiniaturized && NSApp.activationPolicy() == .regular,"Yellow minimize keeps the Dock icon")
                        self.lifecycle.showHome()
                        self.later {
                            self.expect(!self.home.isMiniaturized && self.home.isVisible && NSApp.activationPolicy() == .regular,"Reopen restores a minimized window")
                            self.testRememberedHint()
                        }
                    }
                }
            }
        }
    }
    func testRememberedHint() {
        lifecycle.stop(); defaults.synchronize()
        lifecycle = HostWindowLifecycle(home:home,statusItem:item,defaults:UserDefaults(suiteName:suite)!)
        lifecycle.start(background:true); lifecycle.showHome(); home.performClose(nil)
        later {
            self.expect(self.defaults.bool(forKey:HostWindowLifecycle.hintKey) && self.lifecycle.metadata["hintVisible"] as? Bool == false,"Remembered hint is not repeated by a new controller")
            self.lifecycle.stop(); NSApp.setActivationPolicy(.regular)
            self.auxiliary.makeKeyAndOrderFront(nil); self.auxiliary.close()
            self.later {
                self.expect(NSApp.activationPolicy() == .regular,"Stopping removes lifecycle observers")
                self.finish(success:true)
            }
        }
    }
    func makeWindow(_ title: String) -> NSWindow {
        let window = NSWindow(contentRect:NSRect(x:120,y:120,width:420,height:180),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = title; window.isReleasedWhenClosed = false
        return window
    }
    func later(_ delay: Double = 0.4, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { if !self.finished { body() } }
    }
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message); return }
        passed.append(message); print("PASS: "+message)
    }
    func fail(_ reason: String) { fputs("FAIL: "+reason+"\n",stderr); finish(success:false,error:reason) }
    func finish(success: Bool, error: String? = nil) {
        guard !finished else { return }; finished = true
        lifecycle?.stop()
        defaults?.removePersistentDomain(forName:suite); defaults?.synchronize()
        if let item = item { NSStatusBar.system.removeStatusItem(item) }
        let report: [String:Any] = ["complete":success,"checks":passed,"error":error ?? "",
            "screenCaptureUsed":false,"productionPreferencesAccessed":false,"pairingAccessed":false]
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:output,options:.atomic) }
        exit(success ? 0 : 1)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

guard CommandLine.arguments.count == 2 else { fputs("Usage: HostLifecycleTest OUTPUT_JSON\n",stderr); exit(2) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LifecycleTest(output:URL(fileURLWithPath:CommandLine.arguments[1]))
app.delegate = delegate
app.run()
