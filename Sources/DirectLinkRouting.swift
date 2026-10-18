import Foundation
import Network

// Pure connection policy: discovery can suggest a route, but only a successful
// TLS probe may trigger replacement of a working stream. All times are uptime.
struct DirectLinkRoutePolicy {
    struct Attempt { let time:Double; let order:UInt64 }
    private(set) var retryAfter:[String:Double] = [:]
    private(set) var lastAttempt:[String:Attempt] = [:]
    private(set) var nextProbe:Double = 0
    private var attemptOrder:UInt64 = 0
    func eligible(_ key:String,now:Double)->Bool { (retryAfter[key] ?? 0) <= now }
    mutating func select(_ candidates:[DirectLinkCandidate],now:Double)->DirectLinkCandidate? {
        guard let key = selectKey(from:candidates.map { (key:$0.key,rank:$0.rank) },now:now) else { return nil }
        return candidates.first {$0.key == key}
    }
    // Discovery supplies at most 64 candidates. Ranking picks the first new
    // route; subsequent failures must try every eligible route before cycling
    // through earlier attempts, even if those routes have a lower preference.
    // A monotonic ordinal preserves fairness if two attempt times are equal.
    mutating func selectKey(from routes:[(key:String,rank:Int)],now:Double)->String? {
        var seen = Set<String>()
        let available = routes.prefix(64).filter { seen.insert($0.key).inserted && eligible($0.key,now:now) }
        let selected = available.min { lhs,rhs in
            switch (lastAttempt[lhs.key],lastAttempt[rhs.key]) {
            case (nil,nil): return lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.key < rhs.key
            case (nil,_): return true
            case (_,nil): return false
            case (let left?,let right?):
                if left.order != right.order { return left.order < right.order }
                return lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.key < rhs.key
            }
        }
        guard let selected = selected else { return nil }
        if lastAttempt.count >= 64, lastAttempt[selected.key] == nil,
           let oldest = lastAttempt.min(by:{$0.value.order < $1.value.order})?.key {
            lastAttempt.removeValue(forKey:oldest)
        }
        attemptOrder &+= 1
        lastAttempt[selected.key] = Attempt(time:now,order:attemptOrder)
        return selected.key
    }
    mutating func failed(_ key:String,now:Double) {
        retryAfter = retryAfter.filter { $0.value > now }
        if retryAfter.count >= 64, retryAfter[key] == nil,
           let oldest = retryAfter.min(by:{$0.value < $1.value})?.key { retryAfter.removeValue(forKey:oldest) }
        retryAfter[key] = now+30
    }
    mutating func succeeded(_ key:String) { retryAfter.removeValue(forKey:key) }
    func mayProbe(key:String,rank:Int,wired:Bool,activeKey:String?,activeRank:Int?,now:Double)->Bool {
        wired && key != activeKey && rank < (activeRank ?? 100) && now >= nextProbe && eligible(key,now:now)
    }
    mutating func reserveProbe(now:Double) { nextProbe = now+30 }
}

enum DirectLinkPath {
    // An available path interface is a useful fallback only when unambiguous.
    // Its ordering alone does not prove which Ethernet port carries traffic.
    static func uniqueInterfaceIndex(_ indexes:[Int])->Int? {
        let unique = Set(indexes.filter {$0 > 0})
        return unique.count == 1 ? unique.first : nil
    }
    static func requiredInterfaceVerified(connection:NWConnection,candidate:DirectLinkCandidate)->Bool {
        guard let path = connection.currentPath, path.status == .satisfied,
              connection.parameters.requiredInterface?.index == candidate.interfaceIndex,
              path.availableInterfaces.contains(where:{$0.index == candidate.interfaceIndex}) else { return false }
        return path.usesInterfaceType(candidate.interface.type)
    }
    // Never emit literal addresses: an IPv6 link-local address may embed a MAC.
    static func endpointInfo(_ endpoint:NWEndpoint?)->(family:String,linkLocal:Bool,interface:NWInterface?) {
        guard case .hostPort(let host,_) = endpoint else { return ("unknown",false,nil) }
        switch host {
        case .ipv6(let ip): return ("IPv6",ip.isLinkLocal,ip.interface)
        case .ipv4(let ip): return ("IPv4",ip.isLinkLocal,ip.interface)
        case .name: return ("unresolved",false,nil)
        @unknown default: return ("unknown",false,nil)
        }
    }
    static func metadata(connection:NWConnection,candidate:DirectLinkCandidate? = nil)->[String:Any] {
        guard let path = connection.currentPath else { return ["connection":"Connecting","authenticated":false,"networkSettingsChanged":false] }
        let local = endpointInfo(path.localEndpoint), remote = endpointInfo(path.remoteEndpoint)
        let bound = candidate.map { requiredInterfaceVerified(connection:connection,candidate:$0) } ?? false
        let matching = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }
        let uniqueIndex = uniqueInterfaceIndex(matching.map(\.index))
        let unambiguous = matching.first { $0.index == uniqueIndex }
        let interface = bound ? candidate?.interface : (local.interface ?? remote.interface ?? unambiguous)
        let wired = path.usesInterfaceType(.wiredEthernet)
        let automatic = interface.flatMap { DirectLinkInterfaceState.snapshot()[$0.name] }?.automaticAddressing ?? false
        let label = wired ? (automatic ? "Ethernet · automatic addressing" : "Ethernet") : (path.usesInterfaceType(.wifi) ? "Wi-Fi" : "Local network")
        return ["connection":label,"interface":interface?.name ?? "unknown","interfaceIndex":interface?.index ?? 0,
                "wired":wired,"automaticAddressing":automatic,"scopedDiscovery":candidate != nil,
                "requiredInterfaceVerified":bound,"addressFamily":remote.family,
                "localLinkLocal":local.linkLocal,"remoteLinkLocal":remote.linkLocal,
                "authenticated":connection.state == .ready && connection.parameters.defaultProtocolStack.applicationProtocols.contains(where:{$0 is NWProtocolTLS.Options}),"networkSettingsChanged":false]
    }
}
