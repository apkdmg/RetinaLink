import Foundation

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
            pendingViewerID:pending,credential:key,replacing:replacement,viewerStartup:false,hostStartup:false)
    }
    try expectInvalid { _ = try prepare(binding,nil) }
    var stale = binding; stale.address = "old-imac.local"
    try expectInvalid { _ = try prepare(binding,stale) }
    var dedicated = binding; dedicated.dedicatedDisplay = true; dedicated.managementUsername = "administrator"
    try expectInvalid { _ = try prepare(dedicated,dedicated) }
    try expectInvalid { _ = try prepare(binding,binding,pending:UUID().uuidString) }
    let fresh = try prepare(binding,binding)
    try check(fresh.binding.username == "account_b" && fresh.binding.fileVault == .on && !fresh.binding.automaticLoginConfigured,
              "Account replacement changed FileVault or requested automatic login")
    try check(fresh.credential != oldKey && fresh.credential.count == 32,"Account replacement reused account A’s key")
    try check(DeviceSettings.binding == binding && (try DeviceVault.credential()) == oldKey,
              "Preparing replacement changed the original pairing")
    let resumed = try prepare(fresh.binding,nil,pending:peer.id,key:fresh.credential)
    try check(resumed.binding == fresh.binding && resumed.credential == fresh.credential,"Interrupted replacement rotated the approved credential")
    try expectInvalid { _ = try prepare(fresh.binding,nil,pending:peer.id,key:nil) }
    try expectInvalid { _ = try prepare(fresh.binding,nil,pending:peer.id,key:"invalid") }
    try expectInvalid { _ = try prepare(binding,binding,pending:peer.id) }
    print("PASS: explicit current-profile consent, standard-account replacement, fresh credential, dedicated-account guard and interrupted setup identity")
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
