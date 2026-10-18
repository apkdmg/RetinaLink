import Foundation
import Network

// A short, explicit diagnostic for the signed-in Viewer account. It authenticates
// transport only, sends no Hello or screen data, and never changes pairing or OS
// configuration. Ordinary Viewer launch does not enter this path.
func runDirectLinkProbe() throws {
    #if HOST
    throw LinkError.invalid("Run the direct-link probe from the signed Viewer on the display Mac.")
    #else
    guard Thread.isMainThread else { throw LinkError.invalid("Run the direct-link probe from the main thread.") }
    let duration:Int
    if let value = LaunchOptions.value("--probe-duration") {
        guard let seconds = Int(value), (2...25).contains(seconds) else {
            throw LinkError.invalid("Probe duration must be between 2 and 25 seconds.")
        }
        duration = seconds
    } else { duration = 12 }
    let requestedInterface = LaunchOptions.value("--probe-interface")
    if let name = requestedInterface {
        guard !name.isEmpty, name.utf8.count < 16,
              name.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0)}),
              name.utf8.allSatisfy({$0 < 128}) else {
            throw LinkError.invalid("Use a local interface name such as en0 for the probe.")
        }
    }
    let output = LaunchOptions.value("--probe-output")
    if let path = output {
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count < 4096 else {
            throw LinkError.invalid("The probe output must be an absolute JSON file path.")
        }
    }
    guard DistributionTrust.team != nil, DeviceSettings.nativeTestScope == nil else {
        throw LinkError.invalid("The direct-link probe requires a signed RetinaLink Viewer release.")
    }
    guard let binding = DeviceSettings.binding else {
        throw LinkError.invalid("Pair Viewer with its Host before running the direct-link probe.")
    }
    // DeviceVault.credential suppresses Keychain interaction. A CLI/SSH probe
    // must fail rather than opening a password or trust prompt on the iMac.
    let credential:String
    do {
        guard let saved = try DeviceVault.credential() else {
            throw LinkError.invalid("The saved display credential is unavailable.")
        }
        credential = saved
    } catch {
        throw LinkError.invalid("The display credential is not available silently. Use the signed-in Viewer account with its login Keychain unlocked.")
    }
    // Explicit local negative test only. No real trust is changed or exported.
    let untrustedTest = LaunchOptions.has("--probe-untrusted")
    let probeCredential = untrustedTest ? randomPairingCode().replacingOccurrences(of:"-",with:"") : credential
    let probe = DirectLinkProbe(hostID:binding.hostID,credential:probeCredential,requestedInterface:requestedInterface)
    let started = DispatchTime.now().uptimeNanoseconds
    let deadline = started + UInt64(duration) * 1_000_000_000
    probe.start()
    while !probe.finished && DispatchTime.now().uptimeNanoseconds < deadline {
        RunLoop.current.run(until:Date().addingTimeInterval(0.025))
    }
    probe.stop()
    let report:[String:Any] = [
        "success":probe.success,"identityMatched":probe.success,"requiredInterfaceVerified":probe.success,
        "selectedInterface":probe.selectedInterface,"connectionPath":probe.connectionPath,
        "status":probe.success ? "authenticated" : probe.status,
        "attempts":probe.attempts,"durationSeconds":Double(DispatchTime.now().uptimeNanoseconds-started)/1_000_000_000,
        "sentApplicationData":false,"networkSettingsChanged":false,"pairingChanged":false,"untrustedTest":untrustedTest
    ]
    let data = try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted])
    if let path = output {
        try data.write(to:URL(fileURLWithPath:path),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path)
    }
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
    if !probe.success { throw LinkError.invalid("The direct-link probe did not authenticate a matching Host within its bounded test window.") }
    #endif
}

#if !HOST
private final class DirectLinkProbe {
    private let discovery = DirectLinkDiscovery()
    private let hostID:String, credential:String, requestedInterface:String?
    private var candidates:[DirectLinkCandidate] = [], attempted = Set<String>()
    private var connection:NWConnection?, timeout:DispatchWorkItem?
    private(set) var finished = false, success = false, attempts = 0
    private(set) var selectedInterface = "", connectionPath:[String:Any] = [:]
    private(set) var status = "no-matching-endpoint"

    init(hostID:String,credential:String,requestedInterface:String?) {
        self.hostID = hostID; self.credential = credential; self.requestedInterface = requestedInterface
    }
    func start() {
        discovery.onChange = { [weak self] found in
            guard let self = self, !self.finished else { return }
            self.candidates = found.filter { candidate in
                candidate.id == self.hostID && (self.requestedInterface == nil || candidate.interfaceName == self.requestedInterface)
            }
            self.tryNext()
        }
        discovery.start(type:serviceType,identityKey:"hostID",matchingIdentity:hostID)
    }
    private func tryNext() {
        guard !finished, connection == nil, attempts < 8,
              let candidate = candidates.first(where:{!attempted.contains($0.key)}) else { return }
        attempted.insert(candidate.key); attempts += 1; status = "authentication-pending"
        do {
            let parameters = try networkParameters(credential)
            candidate.apply(to:parameters)
            let peer = NWConnection(to:candidate.endpoint,using:parameters)
            connection = peer
            peer.stateUpdateHandler = { [weak self,weak peer] state in
                guard let self = self, let peer = peer, !self.finished, self.connection === peer else { return }
                switch state {
                case .ready:
                    guard DirectLinkPath.requiredInterfaceVerified(connection:peer,candidate:candidate) else {
                        self.failed(peer,status:"interface-verification-failed"); return
                    }
                    self.selectedInterface = candidate.interfaceName
                    self.connectionPath = DirectLinkPath.metadata(connection:peer,candidate:candidate)
                    self.success = true; self.finished = true
                case .failed: self.failed(peer,status:"authentication-failed")
                case .cancelled: self.failed(peer,status:"connection-cancelled")
                default: break
                }
            }
            let work = DispatchWorkItem { [weak self,weak peer] in
                guard let self = self, let peer = peer, !self.finished, self.connection === peer else { return }
                self.failed(peer,status:"authentication-timeout")
            }
            timeout = work; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
            peer.start(queue:.main)
        } catch { status = "transport-configuration-failed"; tryNext() }
    }
    private func failed(_ peer:NWConnection,status:String) {
        guard connection === peer else { return }
        self.status = status; timeout?.cancel(); timeout = nil
        connection = nil; peer.cancel()
        DispatchQueue.main.async { [weak self] in self?.tryNext() }
    }
    func stop() {
        finished = true; timeout?.cancel(); timeout = nil
        connection?.cancel(); connection = nil; discovery.stop()
    }
}
#endif
