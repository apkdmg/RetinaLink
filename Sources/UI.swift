import AppKit

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
    let v = NSTextField(wrappingLabelWithString:text); v.font = .systemFont(ofSize:size,weight:weight)
    v.isSelectable = true; v.maximumNumberOfLines = 0; return v
}
func horizontal(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views:views); s.orientation = .horizontal; s.spacing = 10; s.alignment = .centerY; return s
}
func makeWindow(_ title: String, views: [NSView], height: CGFloat = 600) -> NSWindow {
    let w = NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:height),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
    w.title = title; w.isReleasedWhenClosed = false
    let stack = NSStackView(views:views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = NSView(); content.addSubview(stack); w.contentView = content
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:28)])
    for view in views { view.widthAnchor.constraint(lessThanOrEqualTo:stack.widthAnchor).isActive = true }
    w.center(); w.makeKeyAndOrderFront(nil); return w
}
func installMenu() {
    let menu = NSMenu(), item = NSMenuItem(), app = NSMenu()
    app.addItem(withTitle:"About RetinaLink",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
    app.addItem(.separator()); app.addItem(withTitle:"Quit RetinaLink",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
    item.submenu = app; menu.addItem(item)
    let editItem = NSMenuItem(), edit = NSMenu(title:"Edit")
    edit.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
    edit.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
    edit.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
    editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
}
func localAddresses() -> String {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return "" }; defer { freeifaddrs(list) }
    var result: [String] = [], pointer = list
    while let entry = pointer {
        defer { pointer = entry.pointee.ifa_next }
        guard let addr = entry.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET else { continue }
        let name = String(cString:entry.pointee.ifa_name)
        guard name != "lo0", (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
        var storage = [CChar](repeating:0,count:Int(NI_MAXHOST))
        if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&storage,socklen_t(storage.count),nil,0,NI_NUMERICHOST) == 0 {
            result.append("\(name): \(String(cString:storage))")
        }
    }
    return result.joined(separator:"  •  ")
}
