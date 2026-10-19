import AppKit

// Presentation only: this object does not own a stream, pairing or startup
// agent. Closing a window must never be interpreted as disconnecting a display.
final class HostWindowLifecycle: NSObject {
    static let hintKey = "RetinaLink.hostMenuBarHintShown.v1"
    let home: NSWindow
    private let statusItem: NSStatusItem
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private let closing = NSHashTable<NSWindow>.weakObjects()
    private var hint: NSPopover?
    private var hintTimer: Timer?
    private var stopped = false

    init(home: NSWindow, statusItem: NSStatusItem, defaults: UserDefaults = .standard) {
        self.home = home; self.statusItem = statusItem; self.defaults = defaults
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName:NSWindow.willCloseNotification,object:nil,queue:.main) { [weak self] note in
            guard let self = self, let window = note.object as? NSWindow, self.isControlWindow(window) else { return }
            self.closing.add(window)
            self.reconcile()
            if window === self.home {
                DispatchQueue.main.async { [weak self] in self?.showHintIfNeeded() }
            }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                guard let self = self, let window = note.object as? NSWindow, self.isControlWindow(window) else { return }
                self.closing.remove(window); self.reconcile()
            })
        }
    }

    private func isControlWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && window !== hint?.contentViewController?.view.window
    }
    private var hasOpenControls: Bool {
        NSApp.windows.contains {
            isControlWindow($0) && !closing.contains($0) && ($0.isVisible || $0.isMiniaturized)
        }
    }
    func reconcile() {
        guard !stopped else { return }
        let policy: NSApplication.ActivationPolicy = hasOpenControls ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
    func prepareForControls() {
        dismissHint()
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }
    func showHome() {
        prepareForControls(); closing.remove(home)
        if home.isMiniaturized { home.deminiaturize(nil) }
        home.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func start(background: Bool) {
        if background { home.orderOut(nil); reconcile() }
        else { showHome() }
    }
    private func showHintIfNeeded() {
        guard !stopped, !hasOpenControls, !defaults.bool(forKey:Self.hintKey),
              let button = statusItem.button, button.window != nil else { return }
        let controller = NSViewController()
        let title = NSTextField(labelWithString:"RetinaLink is still running in the menu bar.")
        title.font = .systemFont(ofSize:13,weight:.semibold)
        title.maximumNumberOfLines = 2; title.lineBreakMode = .byWordWrapping
        let detail = NSTextField(wrappingLabelWithString:"Closing this window doesn't disconnect your display. Open RetinaLink here whenever you need its controls.")
        detail.font = .systemFont(ofSize:12); detail.textColor = .secondaryLabelColor
        let gotIt = NSButton(title:"Got it",target:self,action:#selector(closeHint))
        let stack = NSStackView(views:[title,detail,gotIt])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        let view = NSView(frame:NSRect(x:0,y:0,width:300,height:140))
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:18),
            stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-18),
            stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),
            stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16)
        ])
        controller.view = view
        let popover = NSPopover(); popover.contentViewController = controller
        popover.behavior = .transient; popover.animates = false
        hint = popover
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        if popover.isShown {
            defaults.set(true,forKey:Self.hintKey)
            hintTimer = Timer.scheduledTimer(withTimeInterval:8,repeats:false) { [weak self] _ in self?.dismissHint() }
        }
    }
    @objc private func closeHint() { dismissHint() }
    func dismissHint() {
        hintTimer?.invalidate(); hintTimer = nil
        hint?.close(); hint = nil
    }
    var metadata: [String:Any] {
        ["dockVisible":NSApp.activationPolicy() == .regular,"homeVisible":home.isVisible,
         "homeMiniaturized":home.isMiniaturized,"hintShownBefore":defaults.bool(forKey:Self.hintKey),
         "hintVisible":hint?.isShown == true]
    }
    func stop() {
        stopped = true; dismissHint()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }
    deinit { stop() }
}
