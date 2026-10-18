import Foundation
import Network
import Darwin

// Read-only interface observations. An interface with only link-local addresses
// is a useful cable preference, not proof of a literal point-to-point cable.
// In particular, this code never changes DHCP, IPv6, routes, DNS or service order.
struct DirectLinkInterfaceState:Equatable {
    var hasLinkLocal = false
    var hasIPv6LinkLocal = false
    var hasConfiguredAddress = false
    var isUp = false

    var automaticAddressing:Bool { hasLinkLocal && !hasConfiguredAddress }

    enum AddressClass:Equatable { case ignored,linkLocal,configured }
    static func classifyIPv4(_ bytes:[UInt8])->AddressClass {
        guard bytes.count == 4, bytes[0] != 0, bytes[0] != 127, bytes[0] < 224 else { return .ignored }
        return bytes[0] == 169 && bytes[1] == 254 ? .linkLocal : .configured
    }
    static func classifyIPv6(_ bytes:[UInt8])->AddressClass {
        guard bytes.count == 16, bytes[0] != 0xff,
              !bytes.prefix(15).allSatisfy({$0 == 0}) || bytes[15] > 1 else { return .ignored }
        return bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 ? .linkLocal : .configured
    }

    static func snapshot()->[String:DirectLinkInterfaceState] {
        var first:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return [:] }
        defer { freeifaddrs(start) }
        var states:[String:DirectLinkInterfaceState] = [:], cursor:UnsafeMutablePointer<ifaddrs>? = start
        while let pointer = cursor {
            let item = pointer.pointee; cursor = item.ifa_next
            guard let name = item.ifa_name, let address = item.ifa_addr else { continue }
            let interfaceName = String(cString:name)
            var state = states[interfaceName] ?? DirectLinkInterfaceState()
            state.isUp = item.ifa_flags & UInt32(IFF_UP) != 0 && item.ifa_flags & UInt32(IFF_LOOPBACK) == 0
            let kind:AddressClass
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                var value = UnsafeRawPointer(address).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr
                let bytes = withUnsafeBytes(of:&value) { Array($0) }
                kind = classifyIPv4(bytes)
            case AF_INET6:
                var value = UnsafeRawPointer(address).assumingMemoryBound(to:sockaddr_in6.self).pointee.sin6_addr
                let bytes = withUnsafeBytes(of:&value) { Array($0) }
                kind = classifyIPv6(bytes)
                if kind == .linkLocal { state.hasIPv6LinkLocal = true }
            default: kind = .ignored
            }
            if kind == .linkLocal { state.hasLinkLocal = true }
            if kind == .configured { state.hasConfiguredAddress = true }
            states[interfaceName] = state
        }
        return states
    }
}

enum DirectLinkPreference {
    static func rank(type:NWInterface.InterfaceType,state:DirectLinkInterfaceState)->Int {
        switch type {
        case .wiredEthernet: return state.automaticAddressing ? 0 : 10
        case .wifi: return 20
        case .other: return 30
        case .cellular: return 40
        case .loopback: return 50
        @unknown default: return 60
        }
    }
}

enum DirectLinkTXT {
    // Big Sur can expose hostID in .dictionary while its key subscript and
    // getEntry(for:) both return nil. Use the compatibility dictionary and DNS
    // TXT's case-insensitive key semantics, rejecting ambiguous duplicate keys.
    static func identity(_ record:NWTXTRecord,key:String)->String? {
        identity(record.dictionary,key:key)
    }
    static func identity(_ dictionary:[String:String],key:String)->String? {
        let matches = dictionary.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        guard matches.count == 1, let value = matches.first?.value,
              value.utf8.count <= 64, UUID(uuidString:value) != nil else { return nil }
        return value
    }
}

// Bonjour identity and topology are untrusted transport hints. The caller must
// authenticate this endpoint with the saved TLS credential before using it or
// replacing a working connection. Scope/index are deliberately never persisted:
// a USB adapter can receive a different interface index after unplug/restart.
struct DirectLinkCandidate {
    let id:String
    let name:String
    let endpoint:NWEndpoint
    let interface:NWInterface
    let state:DirectLinkInterfaceState
    let key:String
    var rank:Int { DirectLinkPreference.rank(type:interface.type,state:state) }
    var interfaceName:String { interface.name }
    var interfaceIndex:Int { interface.index }
    var wired:Bool { interface.type == .wiredEthernet }
    var noRoutableAddress:Bool { !state.hasConfiguredAddress }
    var automaticAddressing:Bool { state.automaticAddressing }
    var label:String {
        switch interface.type {
        case .wiredEthernet: return "Local Ethernet"
        case .wifi: return "Wi-Fi"
        default: return "Local network"
        }
    }
    func apply(to parameters:NWParameters) {
        parameters.requiredInterface = interface
        parameters.includePeerToPeer = false
    }
    var metadata:[String:Any] {
        ["interface":interfaceName,"interfaceIndex":interfaceIndex,"connection":label,
         "wired":wired,"automaticAddressing":automaticAddressing,"ipv6LinkLocal":state.hasIPv6LinkLocal,
         "networkSettingsChanged":false]
    }
}

// Network.framework resolves the service on the exact advertised interface,
// including IPv6 link-local scope and its SRV port. Converting this back to a
// hostname would discard that scope and allow macOS to select another network.
// All state and callbacks belong to the main queue, like NativeDiscovery.
final class DirectLinkDiscovery {
    private var browser:NWBrowser?, monitor:NWPathMonitor?, timer:DispatchSourceTimer?
    private var records:Set<NWBrowser.Result> = []
    private var identityKey = "", matchingIdentity:String?
    private var generation = UUID(), fingerprint = ""
    private(set) var candidates:[DirectLinkCandidate] = []
    var onChange:(([DirectLinkCandidate])->Void)?
    var onError:((String)->Void)?

    func start(type:String,identityKey:String,matchingIdentity:String? = nil) {
        stop(); self.identityKey = identityKey; self.matchingIdentity = matchingIdentity
        let token = UUID(); generation = token
        let parameters = NWParameters.tcp; parameters.includePeerToPeer = false
        let browser = NWBrowser(for:.bonjourWithTXTRecord(type:type,domain:"local."),using:parameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results,_ in
            guard let self = self, self.generation == token else { return }
            // Filter the known identity before applying the cap, so unrelated
            // LAN advertisements cannot crowd out this Viewer’s trusted Host.
            let accepted = results.filter { record in
                guard case .bonjour(let txt) = record.metadata,
                      let id = DirectLinkTXT.identity(txt,key:self.identityKey),
                      self.matchingIdentity == nil || id == self.matchingIdentity else { return false }
                return true
            }.sorted { String(describing:$0.endpoint) < String(describing:$1.endpoint) }
            self.records = Set(accepted.prefix(64)); self.publish()
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self, self.generation == token else { return }
            switch state {
            case .waiting, .failed:
                self.onError?("Local discovery is waiting. Allow Local Network access for RetinaLink if macOS asks.")
            default: break
            }
        }
        browser.start(queue:.main)
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self = self, self.generation == token else { return }; self.publish()
        }
        monitor.start(queue:.main)
        // DHCP fallback can add IPv4 link-local without a Bonjour result change.
        // Only observe while discovery runs; no polling or settings helper process.
        let timer = DispatchSource.makeTimerSource(queue:.main); self.timer = timer
        timer.schedule(deadline:.now()+3,repeating:3,leeway:.milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.generation == token else { return }; self.publish()
        }
        timer.resume()
    }
    func stop() {
        generation = UUID()
        browser?.cancel(); browser = nil; monitor?.cancel(); monitor = nil
        timer?.cancel(); timer = nil; records.removeAll(); candidates.removeAll(); fingerprint = ""
    }
    private func publish() {
        let states = DirectLinkInterfaceState.snapshot()
        var next:[DirectLinkCandidate] = [], keys = Set<String>()
        // Sort before capping so Set iteration does not make selection unstable.
        let ordered = records.sorted { String(describing:$0.endpoint) < String(describing:$1.endpoint) }
        for record in ordered {
            guard case .bonjour(let txt) = record.metadata,
                  let id = DirectLinkTXT.identity(txt,key:identityKey),
                  matchingIdentity == nil || id == matchingIdentity,
                  case .service(let name,let type,let domain,_) = record.endpoint,
                  name.utf8.count <= 256, type.utf8.count <= 256, domain.utf8.count <= 256 else { continue }
            for interface in record.interfaces.sorted(by:{$0.index < $1.index}) {
                guard interface.type != .loopback, interface.type != .cellular,
                      interface.index > 0, let state = states[interface.name], state.isUp else { continue }
                let key = "\(id)|\(interface.index)|\(name)|\(type)|\(domain)"
                guard keys.insert(key).inserted else { continue }
                next.append(DirectLinkCandidate(id:id,name:String(name.prefix(160)),
                    endpoint:.service(name:name,type:type,domain:domain,interface:interface),
                    interface:interface,state:state,key:key))
                if next.count >= 64 { break }
            }
            if next.count >= 64 { break }
        }
        next.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.key < $1.key }
        let newFingerprint = next.map { "\($0.key):\($0.rank):\($0.state.hasLinkLocal):\($0.state.hasIPv6LinkLocal):\($0.noRoutableAddress)" }.joined(separator:"\n")
        guard newFingerprint != fingerprint else { return }
        fingerprint = newFingerprint; candidates = next; onChange?(next)
    }
    deinit { browser?.cancel(); monitor?.cancel(); timer?.cancel() }
}
