import AppKit

final class FlippedDocumentView: NSView { override var isFlipped: Bool { true } }

enum Design {
    static func text(_ value: String, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let view = label(value,size:size,weight:weight)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        view.setContentCompressionResistancePriority(.required,for:.vertical)
        return view
    }
    static func symbol(_ name: String, size: CGFloat = 24) -> NSImageView {
        let view = NSImageView()
        if #available(macOS 11.0, *) { view.image = NSImage(systemSymbolName:name,accessibilityDescription:nil) }
        else { view.image = NSImage(named:NSImage.computerName) }
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant:size),view.heightAnchor.constraint(equalToConstant:size)])
        return view
    }
    static func vertical(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let view = NSStackView(views:views); view.orientation = .vertical; view.alignment = .leading; view.spacing = spacing
        return view
    }
    static func button(_ title: String, target: AnyObject?, action: Selector?, primary: Bool = false) -> NSButton {
        let button = NSButton(title:title,target:target,action:action)
        button.bezelStyle = .rounded; button.controlSize = .regular
        if primary { button.keyEquivalent = "\r"; button.bezelColor = .controlAccentColor }
        return button
    }
    static func card(_ views: [NSView], padding: CGFloat = 22) -> NSView {
        let effect = NSVisualEffectView(); effect.material = .contentBackground
        effect.blendingMode = .withinWindow; effect.state = .followsWindowActiveState
        effect.wantsLayer = true; effect.layer?.cornerRadius = 18; effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 0.5; effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        let stack = vertical(views); stack.translatesAutoresizingMaskIntoConstraints = false; effect.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:effect.leadingAnchor,constant:padding),stack.trailingAnchor.constraint(equalTo:effect.trailingAnchor,constant:-padding),stack.topAnchor.constraint(equalTo:effect.topAnchor,constant:padding),stack.bottomAnchor.constraint(equalTo:effect.bottomAnchor,constant:-padding)])
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo:stack.widthAnchor).isActive = true }
        return effect
    }
    static func window(_ title: String, content: NSView, width: CGFloat = 820, height: CGFloat = 720, footer: NSView? = nil) -> NSWindow {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = title; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width:640,height:540)
        let background = NSVisualEffectView(); background.material = .underWindowBackground
        background.blendingMode = .behindWindow; background.state = .followsWindowActiveState
        window.contentView = background
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false; background.addSubview(scroll)
        let document = FlippedDocumentView(); content.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(content); scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:background.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:background.trailingAnchor),scroll.topAnchor.constraint(equalTo:background.topAnchor,constant:32),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),content.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:32),content.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-32),content.topAnchor.constraint(equalTo:document.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-28)])
        if let footer = footer {
            let bar = NSVisualEffectView(); bar.material = .titlebar; bar.blendingMode = .withinWindow
            bar.translatesAutoresizingMaskIntoConstraints = false; footer.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(bar); bar.addSubview(footer)
            let rule = NSBox(); rule.boxType = .separator; rule.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(rule)
            NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo:background.leadingAnchor),bar.trailingAnchor.constraint(equalTo:background.trailingAnchor),bar.bottomAnchor.constraint(equalTo:background.bottomAnchor),scroll.bottomAnchor.constraint(equalTo:bar.topAnchor),footer.trailingAnchor.constraint(equalTo:bar.trailingAnchor,constant:-28),footer.leadingAnchor.constraint(greaterThanOrEqualTo:bar.leadingAnchor,constant:28),footer.topAnchor.constraint(equalTo:bar.topAnchor,constant:15),footer.bottomAnchor.constraint(equalTo:bar.bottomAnchor,constant:-15),rule.leadingAnchor.constraint(equalTo:bar.leadingAnchor),rule.trailingAnchor.constraint(equalTo:bar.trailingAnchor),rule.topAnchor.constraint(equalTo:bar.topAnchor)])
        } else { scroll.bottomAnchor.constraint(equalTo:background.bottomAnchor).isActive = true }
        window.center(); window.makeKeyAndOrderFront(nil); return window
    }
    static func formField(_ title: String, field: NSTextField, hint: String? = nil) -> NSView {
        field.bezelStyle = .roundedBezel; field.font = .systemFont(ofSize:14)
        field.translatesAutoresizingMaskIntoConstraints = false; field.heightAnchor.constraint(equalToConstant:30).isActive = true
        var items: [NSView] = [text(title,12,.semibold),field]
        if let hint = hint { items.append(text(hint,11,secondary:true)) }
        let stack = vertical(items,spacing:6); field.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        return stack
    }
    static func message(_ title: String, detail: String, symbol: String = "info.circle") -> NSView {
        horizontal([self.symbol(symbol,size:22),vertical([text(title,13,.semibold),text(detail,12,secondary:true)],spacing:5)])
    }
    static func export(_ window: NSWindow, path: String) {
        // Render only this application's view hierarchy. No screen capture,
        // accessibility bridge, WindowServer capture client or other app pixels.
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in:content.bounds) else { return }
        content.cacheDisplay(in:content.bounds,to:bitmap)
        if let data = bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path)) }
    }
}

final class MonitorArtwork: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width:240,height:140) }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let available = bounds.insetBy(dx:12,dy:13)
        let width = min(available.width,available.height*1.88)
        let frame = NSRect(x:bounds.midX-width/2,y:available.minY,width:width,height:available.height)
        let screen = NSRect(x:frame.minX,y:frame.minY+22,width:frame.width,height:frame.height-22)
        NSColor.labelColor.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect:screen,xRadius:10,yRadius:10).fill()
        let inner = screen.insetBy(dx:5,dy:5)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect:inner,xRadius:6,yRadius:6).addClip()
        NSGradient(colors:[NSColor.systemIndigo,NSColor.systemTeal,NSColor.systemBlue])?.draw(in:inner,angle:25)
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect:NSRect(x:inner.minX+16,y:inner.minY+17,width:inner.width*0.56,height:inner.height*0.6),xRadius:6,yRadius:6).fill()
        NSColor.white.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect:NSRect(x:inner.minX+26,y:inner.minY+25,width:inner.width*0.6,height:inner.height*0.52),xRadius:6,yRadius:6).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect:NSRect(x:bounds.midX-12,y:frame.minY+3,width:24,height:21),xRadius:3,yRadius:3).fill()
        NSBezierPath(roundedRect:NSRect(x:bounds.midX-37,y:frame.minY,width:74,height:5),xRadius:2,yRadius:2).fill()
    }
}

func runSSHAskpass() -> Never {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let prompt = String(CommandLine.arguments.dropFirst().joined(separator:" ").prefix(1800))
    let alert = NSAlert(); alert.alertStyle = .informational
    let verify = prompt.contains("yes/no")
    alert.messageText = verify ? "Trust this iMac?" : "Sign in to your iMac"
    alert.informativeText = verify ? "Check this computer’s identity before continuing.\n\n"+prompt : prompt+"\n\nYour password is sent to SSH and is never saved by RetinaLink."
    alert.addButton(withTitle:verify ? "Trust and Continue" : "Continue"); alert.addButton(withTitle:"Cancel")
    let password = NSSecureTextField(frame:NSRect(x:0,y:0,width:340,height:26))
    if !verify { password.placeholderString = "Password or key passphrase"; alert.accessoryView = password }
    app.activate(ignoringOtherApps:true)
    let result = alert.runModal()
    guard result == .alertFirstButtonReturn else { exit(1) }
    let answer = verify ? "yes" : password.stringValue
    FileHandle.standardOutput.write(Data((answer+"\n").utf8)); exit(0)
}
