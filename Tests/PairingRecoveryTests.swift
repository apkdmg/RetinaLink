import Foundation
import AppKit
import Network

func runPairingRecoveryTests() throws {
    guard DeviceSettings.nativeTestScope != nil, DeviceVault.service.contains(".native-test.") else {
        throw LinkError.invalid("Recovery tests require disposable preferences and Keychain.")
    }
    let defaults = DeviceSettings.defaults
    defer {
        DeviceVault.remove(DeviceVault.credentialAccount)
        if let scope = DeviceSettings.nativeTestScope {
            defaults.removePersistentDomain(forName:(Bundle.main.bundleIdentifier ?? "RetinaLink")+".NativeTest."+scope)
            defaults.synchronize()
        }
    }
    let hostID = DeviceSettings.hostID
    let binding = DeviceBinding(hostID:hostID,hostName:"Studio",viewerName:"iMac",address:"127.0.0.1",
        username:"account_a",dedicatedDisplay:false,viewerStartup:false,hostStartup:false,
        fileVault:.on,automaticLoginConfigured:false,enrolledAt:Date())
    let oldKey = String(repeating:"A",count:32)
    try DeviceVault.write(Data(oldKey.utf8),account:DeviceVault.credentialAccount)
    try DeviceSettings.save(binding); NativeConnectionSettings.enable()
    NativeConnectionSettings.rememberHost("127.0.0.1"); NativePendingSetup.begin(viewerID:UUID().uuidString)
    defaults.set(true,forKey:"SUEnableAutomaticChecks")
    defaults.set("12345",forKey:"hostShortCode")
    do {
        try NativeLocalPairing.forget { throw LinkError.invalid("Simulated locked test Keychain") }
        throw LinkError.invalid("Reset ignored failed credential deletion")
    } catch {
        try check(DeviceSettings.binding == binding && NativeConnectionSettings.enabled && NativePendingSetup.viewerID != nil,
                  "Failed credential deletion cleared the saved profile")
    }
    try check(try DeviceVault.credential() == oldKey,"Failed reset changed the old credential")
    #if HOST
    let identity = NativePeer(role:"host",id:hostID,name:"Studio",username:"owner",fileVault:.unknown,version:"test")
    let peer = NativePeer(role:"viewer",id:UUID().uuidString,name:"iMac",username:"account_b",fileVault:.on,version:"test")
    func prepare(_ existing:DeviceBinding?, _ replacement:DeviceBinding?, pending:String? = nil, key:String? = oldKey) throws -> NativeEnrollment {
        try NativeHostEnrollment.prepare(peer:peer,identity:identity,address:"127.0.0.1",existing:existing,
            pendingViewerID:pending,credential:key,replacing:replacement,viewerStartup:false,hostStartup:false,physicalID:peer.id)
    }
    try expectInvalid { _ = try prepare(binding,nil) }
    var stale = binding; stale.address = "old-imac.local"
    try expectInvalid { _ = try prepare(binding,stale) }
    var dedicated = binding; dedicated.dedicatedDisplay = true; dedicated.managementUsername = "administrator"
    let dedicatedReconnect = try prepare(dedicated,dedicated)
    let retainedDedicated = NativeHostEnrollment.savedDisplay(dedicatedReconnect,existing:dedicated)
    try check(retainedDedicated.username == dedicated.username && retainedDedicated.dedicatedDisplay &&
              retainedDedicated.managementUsername == dedicated.managementUsername &&
              retainedDedicated.automaticLoginConfigured == dedicated.automaticLoginConfigured,
              "Reconnection retargeted Dedicated Mode")
    try expectInvalid { _ = try prepare(binding,binding,pending:UUID().uuidString) }
    var otherDisplay = binding; otherDisplay.viewerDeviceID = UUID().uuidString
    try expectInvalid { _ = try prepare(otherDisplay,otherDisplay) }
    let fresh = try prepare(binding,binding)
    try check(fresh.binding.username == "account_b" && fresh.binding.fileVault == .on && !fresh.binding.automaticLoginConfigured,
              "Account replacement changed FileVault or requested automatic login")
    try check(fresh.credential == oldKey,"Reconnection invalidated a previously approved Viewer")
    let savedDisplay = NativeHostEnrollment.savedDisplay(fresh,existing:binding)
    try check(savedDisplay.viewerName == binding.viewerName && savedDisplay.enrolledAt == binding.enrolledAt &&
              savedDisplay.viewerDeviceID == peer.id,"Reconnection duplicated or renamed the saved display")
    try expectInvalid { _ = try prepare(binding,binding,key:nil) }
    try expectInvalid { _ = try prepare(binding,binding,key:"invalid") }
    try check(DeviceSettings.binding == binding && (try DeviceVault.credential()) == oldKey,
              "Preparing replacement changed the original pairing")
    let resumed = try prepare(fresh.binding,nil,pending:peer.id,key:fresh.credential)
    try check(resumed.binding == fresh.binding && resumed.credential == fresh.credential,"Interrupted replacement rotated the approved credential")
    try expectInvalid { _ = try prepare(fresh.binding,nil,pending:peer.id,key:nil) }
    try expectInvalid { _ = try prepare(fresh.binding,nil,pending:peer.id,key:"invalid") }
    try expectInvalid { _ = try prepare(binding,binding,pending:peer.id) }
    try check(NativeDisplayIdentity.current != nil && NativeDisplayIdentity.current == NativeDisplayIdentity.current,"Physical display identity is missing or unstable")
    let recovery = try NativeHostEnrollment.prepare(peer:peer,identity:identity,address:"127.0.0.1",existing:retainedDedicated,
        pendingViewerID:peer.id,credential:oldKey,replacing:nil,viewerStartup:false,hostStartup:false,pendingBinding:dedicatedReconnect.binding)
    try check(recovery.binding.username == peer.username && recovery.credential == oldKey,"Managed reconnect could not resume without changing auto login")
    print("PASS: local consent, one saved display, retained approved key, Dedicated Mode preserved and interrupted approval bound to its Viewer")
    #endif
    try NativeLocalPairing.forget()
    try check(DeviceSettings.binding == nil && (try DeviceVault.credential()) == nil && !NativeConnectionSettings.enabled,
              "Offline local reset kept a trusted profile")
    try check(NativePendingSetup.viewerID == nil && NativeConnectionSettings.hostAddress == nil,"Reset left pending or cached connection state")
    try check(DeviceSettings.hostID == hostID && defaults.bool(forKey:"SUEnableAutomaticChecks"),"Reset changed stable identity or update preferences")
    try check(NativeConnectionSettings.requiresSetup && defaults.string(forKey:"hostShortCode") == "12345",
              "Reset did not block background fallback to the saved legacy code")
    try NativeLocalPairing.forget()
    NativeConnectionSettings.enable()
    try check(!NativeConnectionSettings.requiresSetup,"Approved pairing could not clear the reset guard")
    print("PASS: unavailable-peer reset, failure preserves trust, idempotent deletion, stable identity and update preferences preserved; isolated Keychain only")
}

#if HOST
func runDisplayRemovalTests() throws {
    guard DeviceSettings.nativeTestScope != nil, DeviceVault.service.contains(".native-test.") else {
        throw LinkError.invalid("Display removal tests require disposable preferences and Keychain.")
    }
    let defaults = DeviceSettings.defaults
    defer {
        DeviceVault.remove(DeviceVault.credentialAccount)
        if let scope = DeviceSettings.nativeTestScope {
            defaults.removePersistentDomain(forName:(Bundle.main.bundleIdentifier ?? "RetinaLink")+".NativeTest."+scope)
        }
    }
    _ = NSApplication.shared
    for dedicated in [false,true] {
        var binding = DeviceBinding(hostID:DeviceSettings.hostID,hostName:"Studio",viewerName:"iMac",address:"127.0.0.1",
            username:dedicated ? "retinalinkdisplay" : "owner",dedicatedDisplay:dedicated,viewerStartup:true,
            hostStartup:true,fileVault:dedicated ? .off : .on,automaticLoginConfigured:dedicated,enrolledAt:Date(timeIntervalSince1970:100))
        binding.managementUsername = dedicated ? "original_administrator" : nil
        binding.viewerDeviceID = UUID().uuidString
        let key = String(repeating:dedicated ? "B" : "A",count:32)
        try DeviceVault.write(Data(key.utf8),account:DeviceVault.credentialAccount)
        try DeviceSettings.save(binding); NativeConnectionSettings.enable()
        defaults.set(false,forKey:"SUEnableAutomaticChecks")
        try expectInvalid { try NativeSavedDisplay.remove { throw LinkError.invalid("Simulated locked test Keychain") } }
        try check(DeviceSettings.binding == binding && NativeSavedDisplay.removed == nil,"Failed removal lost the active display")
        NativePendingSetup.begin(viewerID:UUID().uuidString,binding:binding)
        try NativeSavedDisplay.remove()
        try check(DeviceSettings.binding == nil && NativeSavedDisplay.isRemoved && !NativeSavedDisplay.mayShareDesktop,
                  "Removing the display did not disable desktop sharing")
        try check(NativeSavedDisplay.removed?.binding == binding && (try DeviceVault.credential()) == key,
                  "Removing the display changed its approval or Dedicated Mode metadata")
        try check(NativeSavedDisplay.connectionBinding == binding && NativeConnectionSettings.enabled,
                  "Offline removal lost authenticated automatic reconnection")
        try check(NativePendingSetup.viewerID == nil,"Removal retained an unfinished setup")
        // Simulate either side of an interrupted preferences transaction:
        // removal persisted before clearing the old binding, or re-add saved
        // its binding before clearing the removal record.
        try DeviceSettings.save(binding)
        try check(DeviceSettings.binding == nil && NativeSavedDisplay.isRemoved && !NativeSavedDisplay.mayShareDesktop,
                  "An interrupted write made a removed display active after restart")
        // Exercise the actual capture entry point, including its retry action.
        let host = HostApp(), peer = Link(NWConnection(host:"127.0.0.1",port:9,using:try networkParameters(key)))
        host.link = peer
        var captureAttempts = 0
        host.makeCapture = { _ in captureAttempts += 1; throw LinkError.invalid("Capture must stay off") }
        host.beginCapture(peer); host.waitingForPermission = true; host.retryCapture()
        try check(captureAttempts == 0 && !host.startingCapture && host.startup == nil,
                  "A removed display reached capture through reconnect/retry")
        // Re-add through the same controller/button used by Host, without Viewer.
        let setup = NativeHostSetup(); setup.show()
        defer { setup.cancel() }
        try check(setup.stage == "approved" && setup.continueButton.title == "Add Display" &&
                  setup.installationCard?.isHidden == true && setup.discoveryCard?.isHidden == true,
                  "Re-adding still asked for installation or Viewer interaction")
        setup.chooseDifferentDisplay()
        try check(setup.stage == "choose" && setup.discoveryCard?.isHidden == false && NativeSavedDisplay.removed?.binding == binding,
                  "Choosing a different display discarded the previous approval before new consent")
        setup.cancel(); setup.show()
        var restored:DeviceBinding?
        setup.onPrepared = { restored = $0 }; setup.advance()
        try check(restored == binding && DeviceSettings.binding == binding && !NativeSavedDisplay.isRemoved,
                  "Host-only re-add lost the saved display configuration")
        try check(NativeSavedDisplay.mayShareDesktop && (try DeviceVault.credential()) == key &&
                  !defaults.bool(forKey:"SUEnableAutomaticChecks"),"Re-add changed approval or update preferences")
        try NativeSavedDisplay.remove()
        try DeviceVault.write(Data(String(repeating:"C",count:32).utf8),account:DeviceVault.credentialAccount)
        try expectInvalid { _ = try NativeSavedDisplay.restore() }
        try check(NativeSavedDisplay.isRemoved && DeviceSettings.binding == nil,"Mismatched approval restored a removed display")
        try NativeLocalPairing.forget()
        try check(NativeSavedDisplay.removed == nil && (try DeviceVault.credential()) == nil && !NativeSavedDisplay.mayShareDesktop,
                  "Full revocation retained removable approval")
        print("PASS: \(dedicated ? "dedicated" : "ordinary") display: offline removal, capture/retry blocked, Host-only re-add, configuration retained and full revocation")
    }
    defaults.set(Data("corrupt".utf8),forKey:NativeConnectionSettings.removedDisplayKey)
    NativeConnectionSettings.enable()
    try check(NativeSavedDisplay.isRemoved && !NativeSavedDisplay.mayShareDesktop,"Corrupt removal metadata enabled desktop sharing")
    print("PASS: stale/malformed approvals fail closed; no production pairing, startup or OS settings accessed")
}
#endif
