import Foundation
import Network
import Darwin

// These are transport-boundary tests. They do not browse the network, change
// interface settings, load production credentials, or claim that discovery is
// authentication. Viewer handover authentication is exercised separately.
func runDirectLinkSafetyTests() throws {
    try check(DirectLinkRoutePolicy.usbRouteUnavailable(recordedIndex:7,currentIndex:7,linkActive:false),
        "A confirmed USB disconnect kept a stale stream active")
    try check(DirectLinkRoutePolicy.usbRouteUnavailable(recordedIndex:7,currentIndex:0,linkActive:nil) &&
        DirectLinkRoutePolicy.usbRouteUnavailable(recordedIndex:7,currentIndex:9,linkActive:true),
        "A removed or renumbered USB interface retained its old path")
    try check(!DirectLinkRoutePolicy.usbRouteUnavailable(recordedIndex:7,currentIndex:7,linkActive:nil) &&
        !DirectLinkRoutePolicy.usbRouteUnavailable(recordedIndex:7,currentIndex:7,linkActive:true),
        "Unknown or healthy USB hardware status was treated as a disconnect")
    let localScope = NWEndpoint.Host("fe80::1%lo0")
    guard case .ipv6(let address) = localScope, let interface = address.interface else {
        throw LinkError.invalid("Network.framework lost the IPv6 link-local interface scope")
    }
    try check(address.isLinkLocal && interface.name == "lo0" && interface.index == Int(if_nametoindex("lo0")),
        "Scoped IPv6 endpoint selected a different interface")
    // The new transport must retain scope in typed Network.framework objects;
    // accepting zone syntax in the persisted legacy SSH address is unsafe.
    for legacyInput in ["fe80::1%lo0", "[fe80::1%lo0]", "Studio.local%en9", "Studio.local -oProxyCommand=anything"] {
        try check(!DeviceBinding.validAddress(legacyInput),"Scoped discovery weakened the legacy address validation boundary")
    }

    let service = NWEndpoint.service(name:"Disposable scope test",type:serviceType,domain:"local.",interface:interface)
    let observation = DirectLinkInterfaceState(hasLinkLocal:true,hasIPv6LinkLocal:true,hasConfiguredAddress:false,isUp:true)
    let candidate = DirectLinkCandidate(id:UUID().uuidString,name:"Disposable scope test",endpoint:service,
        interface:interface,state:observation,key:"disposable-scope-test")
    guard case .service(_,_,_,let endpointInterface) = candidate.endpoint else {
        throw LinkError.invalid("Bonjour endpoint was flattened into an unscoped hostname")
    }
    try check(endpointInterface?.index == interface.index,"Bonjour endpoint lost its concrete interface")

    // Selecting a cable is a path constraint, never a replacement security mode.
    // Test actual production TLS parameters with a disposable random-format key.
    let parameters = try networkParameters(String(repeating:"A",count:32))
    let originalStackCount = parameters.defaultProtocolStack.applicationProtocols.count
    try check(parameters.defaultProtocolStack.applicationProtocols.contains {$0 is NWProtocolTLS.Options},
        "The scoped connection test did not start with TLS")
    let originalLocalEndpoint = NWEndpoint.hostPort(host:localScope,port:.any)
    parameters.requiredLocalEndpoint = originalLocalEndpoint
    candidate.apply(to:parameters)
    try check(parameters.requiredInterface?.index == interface.index && !parameters.includePeerToPeer,
        "Scoped transport can escape to a different or peer-to-peer interface")
    try check(parameters.requiredLocalEndpoint == originalLocalEndpoint,
        "Interface selection rewrote an existing source endpoint")
    try check(parameters.defaultProtocolStack.applicationProtocols.count == originalStackCount &&
        parameters.defaultProtocolStack.applicationProtocols.contains {$0 is NWProtocolTLS.Options},
        "Choosing Ethernet removed TLS from the trusted connection")
    try check(!candidate.label.localizedCaseInsensitiveContains("direct") &&
        candidate.metadata["networkSettingsChanged"] as? Bool == false,
        "Transport observations claimed physical topology or system reconfiguration")
    print("PASS: typed IPv6/Bonjour interface scope, legacy SSH validation boundary and TLS-preserving path constraints")

    // NWInterface has no public initializer for a synthetic .other interface.
    // Test its USB policy separately, then exercise the same scoped connection
    // boundary with the real loopback interface and a synthetic local USB
    // observation. This fixture is not a physical USB connection.
    var usbObservation = observation
    usbObservation.usb = USBLinkObservation(source:.deviceNCM)
    let usbRank = DirectLinkPreference.rank(type:.other,state:usbObservation)
    try check(usbRank < DirectLinkPreference.rank(type:.wiredEthernet,state:observation),
        "A locally identified USB interface reported as .other cannot precede automatic Ethernet")
    let usbScopeCandidate = DirectLinkCandidate(id:UUID().uuidString,name:"Disposable USB scope test",endpoint:service,
        interface:interface,state:usbObservation,key:"disposable-usb-scope-test")
    try check(!usbScopeCandidate.isUSB,"A USB observation relabeled the actual loopback interface")
    let usbParameters = try networkParameters(String(repeating:"B",count:32))
    usbScopeCandidate.apply(to:usbParameters)
    try check(usbParameters.requiredInterface?.index == interface.index && !usbParameters.includePeerToPeer &&
        usbParameters.defaultProtocolStack.applicationProtocols.contains {$0 is NWProtocolTLS.Options},
        "The USB route selection path lost its concrete scope or TLS authentication")

    var policy = DirectLinkRoutePolicy()
    try check(!policy.mayProbe(key:"existing",rank:0,wired:true,activeKey:"existing",activeRank:10,now:0),
        "Discovery proposed replacing the active route with itself")
    try check(!policy.mayProbe(key:"same-quality",rank:10,wired:true,activeKey:"existing",activeRank:10,now:0),
        "Equal-ranked service announcements can churn a working route")
    try check(!policy.mayProbe(key:"wireless",rank:0,wired:false,activeKey:"existing",activeRank:10,now:0),
        "A wireless discovery result can trigger the Ethernet handover policy")
    try check(policy.mayProbe(key:"better",rank:0,wired:true,activeKey:"existing",activeRank:10,now:0),
        "A better Ethernet route cannot be tested while a working route remains active")
    try check(policy.mayProbe(key:"usb-other",rank:usbRank,wired:true,activeKey:"company-lan",activeRank:10,now:0),
        "A locally identified USB route cannot be authenticated before replacing company Ethernet")
    // A discovered UUID is untrusted. Even failed authentication must consume
    // the attempt interval, so many differently named advertisements cannot
    // repeatedly provoke TLS probes or interrupt normal display work.
    policy.reserveProbe(now:0)
    policy.failed("better",now:0)
    try check(!policy.eligible("better",now:29.999) && policy.eligible("other",now:1),
        "One failed route blocks every alternative or is retried without cooldown")
    try check(!policy.mayProbe(key:"other",rank:0,wired:true,activeKey:"existing",activeRank:10,now:29.999) &&
        policy.mayProbe(key:"other",rank:0,wired:true,activeKey:"existing",activeRank:10,now:30),
        "Different untrusted announcements bypass the global probe interval")
    policy.reserveProbe(now:30)
    policy.succeeded("better")
    try check(!policy.mayProbe(key:"other",rank:0,wired:true,activeKey:"existing",activeRank:10,now:31),
        "A successful probe cleared the global attempt interval")
    for index in 0..<200 { policy.failed("untrusted-\(index)",now:31) }
    try check(policy.retryAfter.count <= 64 && policy.eligible("untrusted-199",now:61),
        "Repeated discovery failures created unbounded or permanent retry state")
    // Reproduce the real starvation pattern: three failed 15-second attempts
    // make the first preferred route eligible again before a fourth, working
    // route is tried. An eligible-first search would repeat that cycle forever.
    let fallbackRoutes = [(key:"preferred-1",rank:0),(key:"preferred-2",rank:0),
                          (key:"preferred-3",rank:0),(key:"working-fallback",rank:20)]
    var recovery = DirectLinkRoutePolicy()
    for index in 0..<3 {
        let now = Double(index)*15
        let key = recovery.selectKey(from:fallbackRoutes,now:now)
        try check(key == "preferred-\(index+1)","Initial route attempts ignored preference order")
        recovery.failed(key!,now:now+15)
    }
    try check(recovery.eligible("preferred-1",now:45),"Starvation fixture did not reproduce an expired cooldown")
    try check(recovery.selectKey(from:fallbackRoutes,now:45) == "working-fallback",
        "Repeated preferred-route failures starved the working fallback")
    try check(recovery.lastAttempt["working-fallback"]?.time == 45,
        "Route selection did not record its attempt time")
    // Equal clock samples must still rotate fairly; timer precision must not
    // let the lexically first service monopolize retries.
    var sameTick = DirectLinkRoutePolicy(), selected = Set<String>()
    let equalRoutes = (0..<16).map { (key:"candidate-\($0)",rank:$0%3) }
    for _ in equalRoutes {
        guard let key = sameTick.selectKey(from:equalRoutes,now:100) else {
            throw LinkError.invalid("An eligible fallback route was lost")
        }
        try check(selected.insert(key).inserted,"Equal-time attempts revisited a route before trying every fallback")
    }
    let firstRound = selected
    selected.removeAll()
    for _ in equalRoutes {
        guard let key = sameTick.selectKey(from:equalRoutes,now:100) else {
            throw LinkError.invalid("A previously attempted fallback could not be retried")
        }
        try check(selected.insert(key).inserted,"Retried routes did not rotate fairly across ranks")
    }
    try check(selected == firstRound,"Fair retries omitted an available route")
    for index in 0..<200 {
        _ = recovery.selectKey(from:[(key:"rotating-\(index)",rank:0)],now:Double(index)+100)
    }
    try check(recovery.lastAttempt.count <= 64,"Discovery churn created unbounded route attempt history")
    // A USB interface can get a new index when it is plugged in again. Its old
    // failed endpoint must not suppress the new scoped endpoint or the healthy
    // company-network fallback, and no index is written into the pairing.
    var cableRecovery = DirectLinkRoutePolicy()
    let originalUSB = "trusted-host|usb-index-9", returnedUSB = "trusted-host|usb-index-12"
    try check(cableRecovery.selectKey(from:[(key:originalUSB,rank:0),(key:"company-lan",rank:10)],now:0) == originalUSB,
        "A newly available USB route was not selected before company Ethernet")
    cableRecovery.failed(originalUSB,now:1)
    try check(cableRecovery.selectKey(from:[(key:originalUSB,rank:0),(key:"company-lan",rank:10)],now:2) == "company-lan",
        "A lost USB route prevented company-network fallback")
    try check(cableRecovery.selectKey(from:[(key:returnedUSB,rank:0),(key:"company-lan",rank:10)],now:3) == returnedUSB,
        "The old USB interface cooldown prevented reconnection on its new index")
    let info = DirectLinkPath.endpointInfo(.hostPort(host:localScope,port:58473))
    try check(info.family == "IPv6" && info.linkLocal && info.interface?.index == interface.index,
        "Verified path metadata lost IPv6 link-local scope")
    let unresolved = DirectLinkPath.endpointInfo(.hostPort(host:.name("Studio.local",nil),port:58473))
    try check(unresolved.family == "unresolved" && !unresolved.linkLocal && unresolved.interface == nil,
        "A Bonjour hostname was treated as a verified numeric link-local route")
    // An unscoped accepted IPv4 connection may list both the company port and
    // the USB adapter as available. Changing their order must not invent an
    // actual interface; an explicitly verified candidate remains definitive.
    try check(DirectLinkPath.uniqueInterfaceIndex([4,9]) == nil &&
        DirectLinkPath.uniqueInterfaceIndex([9,4]) == nil,
        "Available-interface ordering was mistaken for an actual Ethernet route")
    try check(DirectLinkPath.uniqueInterfaceIndex([4,4]) == 4 &&
        DirectLinkPath.uniqueInterfaceIndex([9]) == 9 &&
        DirectLinkPath.uniqueInterfaceIndex([]) == nil &&
        DirectLinkPath.uniqueInterfaceIndex([0,-1]) == nil,
        "Unambiguous or absent interface observations were misreported")
    let unknownTransport = DirectLinkPath.transportMetadata(state:nil,interfaceObserved:false,
        usesEthernet:false,usesWiFi:false)
    try check(unknownTransport["transportKind"] as? String == "other" &&
        unknownTransport["connection"] as? String == "Local network" && unknownTransport["usbEvidence"] == nil,
        "An unknown path was presented as a USB connection")
    let companyTransport = DirectLinkPath.transportMetadata(state:observation,interfaceObserved:true,interfaceType:.wiredEthernet,
        usesEthernet:true,usesWiFi:false)
    try check(companyTransport["transportKind"] as? String == "ethernet" &&
        companyTransport["wired"] as? Bool == true && companyTransport["usbEvidence"] == nil,
        "Ordinary Ethernet was presented as a direct USB connection")
    let usbTransport = DirectLinkPath.transportMetadata(state:usbObservation,interfaceObserved:true,interfaceType:.other,
        usesEthernet:false,usesWiFi:false)
    try check(usbTransport["transportKind"] as? String == "usb" && usbTransport["connection"] as? String == "USB" &&
        usbTransport["wired"] as? Bool == true && usbTransport["usbEvidence"] as? String == USBLinkSource.deviceNCM.rawValue,
        "An observed USB .other interface lost its transport label or local evidence")
    for (observed,type):(Bool,NWInterface.InterfaceType?) in [(false,.other),(true,nil),(true,.wifi),(true,.loopback),(true,.cellular)] {
        let unverified = DirectLinkPath.transportMetadata(state:usbObservation,interfaceObserved:observed,interfaceType:type,
            usesEthernet:false,usesWiFi:type == .wifi)
        try check(unverified["transportKind"] as? String != "usb" && unverified["usbEvidence"] == nil,
            "An unverified or contradictory interface observation invented a USB path")
    }
    print("PASS: bounded probe backoff, fair fallback under repeated preferred-route failures, equal-time retries and scoped path reporting")
}
