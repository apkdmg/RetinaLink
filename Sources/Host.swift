#if HOST
import AppKit
import ScreenCaptureKit
import Network
import CoreMedia

enum CaptureAuthorization {
    static func isDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }
}

// Constant-space ingress measurements; no screen content is retained.
final class CaptureTiming {
    private let lock = NSLock()
    private var counts = [Int](repeating:0,count:7)
    private var lastDisplay: Double?, gaps = 0, gapMS = 0.0, maxGapMS = 0.0, late = 0
    private var ages = 0, ageMS = 0.0, maxAgeMS = 0.0
    func record(status: Int, displayTime: UInt64?) {
        lock.lock(); defer { lock.unlock() }
        counts[min(6,max(0,status))] += 1
        guard status == SCFrameStatus.complete.rawValue, let ticks = displayTime, ticks > 0 else { return }
        let displayed = CMClockMakeHostTimeFromSystemUnits(ticks).seconds
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let age = max(0,(now-displayed)*1000)
        ageMS += age; maxAgeMS = max(maxAgeMS,age); ages += 1
        if let previous = lastDisplay, displayed > previous {
            let gap = (displayed-previous)*1000
            gaps += 1; gapMS += gap; maxGapMS = max(maxGapMS,gap)
            if gap > 25 { late += 1 }
        }
        lastDisplay = displayed
    }
    func summary() -> (complete:Int,text:String) {
        lock.lock(); defer { lock.unlock() }
        let text = String(format:"Capture callbacks complete %d · idle %d · blank %d · suspended %d · other %d\nSource display gap %.2f ms · max %.2f ms · gaps >25 ms %d · callback lag %.2f ms · max %.2f ms",counts[0],counts[1],counts[2],counts[3],counts[4]+counts[5]+counts[6],gapMS/Double(max(1,gaps)),maxGapMS,late,ageMS/Double(max(1,ages)),maxAgeMS)
        let result = (counts[0],text)
        counts = [Int](repeating:0,count:7); gaps = 0; gapMS = 0; maxGapMS = 0; late = 0; ages = 0; ageMS = 0; maxAgeMS = 0
        return result
    }
}

final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    let work = DispatchQueue(label:"retinalink.capture",qos:.userInteractive,autoreleaseFrequency:.workItem)
    let captureQueue = DispatchQueue(label:"retinalink.capture.ingress",qos:.userInteractive,autoreleaseFrequency:.workItem)
    let mailbox = CaptureMailbox()
    let captureTiming = CaptureTiming()
    let captureOnly = LaunchOptions.has("--capture-only")
    let encodeOnly = LaunchOptions.has("--encode-only")
    var captureID:UInt64 = 0
    let inlineCapture = LaunchOptions.has("--inline-capture")
    let link: Link, encoder: TextureEncoder
    let packer: FramePacker? = LaunchOptions.has("--baseline-packing") ? nil:FramePacker()
    var stream: SCStream?, virtual: RLVirtualDisplay?
    var inFlight: [UInt64:Double] = [:], sequence: UInt64 = 0
    var frameLimit = 2
    var parallelPacking = false
    var sentBytes = 0, delivered = 0, skipped = 0, lastStats = ProcessInfo.processInfo.systemUptime
    var complete = 0, unchanged = 0, inactive = 0, encodes = 0
    var ackMS = 0.0, encodeMS = 0.0, active = false
    var sendMS = 0.0, sendCount = 0, ackDispatchMS = 0.0
    var maxACK=0.0, maxSend=0.0, maxACKDispatch=0.0
    var gpuMS = 0.0, gpuWaitMS = 0.0, gatherMS = 0.0, packMS = 0.0
    var watchdog: DispatchSourceTimer?
    var activity: StreamingActivity?
    var onStatus: ((String) -> Void)?, onError: ((String) -> Void)?
    var authorize: @MainActor () async throws -> Void = {
        _ = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
    }
    init(link: Link) throws { self.link = link; encoder = try TextureEncoder(); super.init() }
    @MainActor func start(width: Int,height: Int,fps: Int) async throws {
        activity = StreamingActivity()
        // ScreenCaptureKit is the authority for this capture request. A legacy
        // preflight result must not prevent a valid ScreenCaptureKit grant from working.
        // Enumerate once before creating a virtual display; denial is recoverable.
        try await authorize()
        try Task.checkCancellation()
        virtual = try RLVirtualDisplay(width:UInt(width),height:UInt(height),rate:Double(fps))
        guard let virtual = virtual else { throw LinkError.invalid("Virtual display creation failed") }
        var chosen: SCDisplay?
        for _ in 0..<10 {
            try Task.checkCancellation()
            let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
            chosen = content.displays.first { $0.displayID == virtual.displayID }
            if chosen != nil { break }; try await Task.sleep(nanoseconds:200_000_000)
        }
        guard let display = chosen, let mode = CGDisplayCopyDisplayMode(virtual.displayID),mode.pixelWidth == width,mode.pixelHeight == height else {
            throw LinkError.invalid("macOS did not create the requested native pixel dimensions. Capture was not started.")
        }
        DiagnosticLog.shared.record("display", "Native \(mode.pixelWidth) × \(mode.pixelHeight); virtual refresh \(mode.refreshRate) Hz; output target \(fps) fps")
        let config = SCStreamConfiguration(); config.width = width; config.height = height
        config.minimumFrameInterval = (fps == 60 && !LaunchOptions.has("--capture-throttle")) || LaunchOptions.has("--capture-max-rate") ? .zero : CMTime(value:1,timescale:CMTimeScale(fps))
        config.queueDepth = min(8,max(3,Int(LaunchOptions.value("--capture-depth") ?? "5") ?? 5))
        config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = !LaunchOptions.has("--capture-no-cursor")
        if !LaunchOptions.has("--capture-native-colour") { config.colorSpaceName = CGColorSpace.sRGB }
        if #available(macOS 14.0, *) { config.captureResolution = .best }
        DiagnosticLog.shared.record("capture-config", "BGRA \(width) × \(height); depth \(config.queueDepth); interval \(config.minimumFrameInterval.seconds); capture-only \(captureOnly); encode-only \(encodeOnly); parallel lossless packing \(parallelPacking); native-colour \(LaunchOptions.has("--capture-native-colour"))")
        var displayIDs = [CGDirectDisplayID](repeating:0,count:32), count:UInt32 = 0
        if CGGetActiveDisplayList(32,&displayIDs,&count) == .success {
            for id in displayIDs.prefix(Int(count)) {
                if let mode = CGDisplayCopyDisplayMode(id) { DiagnosticLog.shared.record("display-mode", "ID \(id) · \(mode.width) × \(mode.height) points / \(mode.pixelWidth) × \(mode.pixelHeight) pixels · \(mode.refreshRate) Hz · built-in \(CGDisplayIsBuiltin(id))") }
            }
        }
        let stream = SCStream(filter:SCContentFilter(display:display,excludingWindows:[]),configuration:config,delegate:self)
        try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:inlineCapture ? work : captureQueue)
        self.stream = stream
        work.sync { active = true }
        mailbox.start()
        try await stream.startCapture()
        work.async { [weak self] in
            guard let self = self, self.active else { return }
            let timer = DispatchSource.makeTimerSource(queue:self.work)
            self.lastStats = ProcessInfo.processInfo.systemUptime
            timer.schedule(deadline:.now()+1,repeating:1)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.active else { return }
                self.report()
                if let oldest = self.inFlight.values.min(), ProcessInfo.processInfo.systemUptime-oldest > 10 {
                    self.fail("The Viewer stopped responding. Reconnect when its display is awake.")
                }
            }; self.watchdog = timer; timer.resume()
        }
    }
    @MainActor func stop() async {
        mailbox.stop()
        work.sync { active = false; watchdog?.cancel(); watchdog = nil; inFlight.removeAll() }
        if let stream = stream { try? await stream.stopCapture() }
        stream = nil; virtual = nil
        activity = nil
    }
    func acknowledge(_ data: Data) {
        let received = ProcessInfo.processInfo.systemUptime
        FrameTrace.shared.event("ack_dispatch",fields:["bytes":data.count])
        work.async { [weak self] in
            guard let self = self, self.active else { return }
            do {
                var reader = Reader(data:data); let seq = try reader.u64()
                guard reader.atEnd, let time = self.inFlight.removeValue(forKey:seq) else { throw LinkError.invalid("Invalid frame acknowledgement") }
                FrameTrace.shared.event("ack_apply",sequence:seq,fields:["cycle_ms":(ProcessInfo.processInfo.systemUptime-time)*1000,"dispatch_ms":(ProcessInfo.processInfo.systemUptime-received)*1000])
                self.ackMS += (ProcessInfo.processInfo.systemUptime-time)*1000; self.delivered += 1
                self.ackDispatchMS += (ProcessInfo.processInfo.systemUptime-received)*1000
                self.maxACK=max(self.maxACK,(ProcessInfo.processInfo.systemUptime-time)*1000)
                self.maxACKDispatch=max(self.maxACKDispatch,(ProcessInfo.processInfo.systemUptime-received)*1000)
            } catch { self.fail(String(describing:error)) }
        }
    }
    func recordSend(_ milliseconds: Double) {
        work.async { [weak self] in
            guard let self = self, self.active else { return }
            self.sendMS += milliseconds; self.sendCount += 1
            self.maxSend=max(self.maxSend,milliseconds)
        }
    }
    func stream(_ stream: SCStream,didOutputSampleBuffer sampleBuffer: CMSampleBuffer,of type: SCStreamOutputType) {
        autoreleasepool {
            guard type == .screen, sampleBuffer.isValid else { return }
            let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]])?.first
            let state = info?[.status] as? Int ?? 6
            captureID += 1
            let ticks=(info?[.displayTime] as? NSNumber)?.uint64Value
            let displayTime=ticks.map {CMClockMakeHostTimeFromSystemUnits($0).seconds}
            FrameTrace.shared.event("capture",fields:["id":captureID,"status":state,"display":displayTime ?? -1,"pts":sampleBuffer.presentationTimeStamp.seconds,"image":sampleBuffer.imageBuffer != nil])
            captureTiming.record(status:state,displayTime:(info?[.displayTime] as? NSNumber)?.uint64Value)
            if captureOnly { return }
            if inlineCapture { process(sampleBuffer, type:type); return }
            guard type == .screen, sampleBuffer.isValid else { return }
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
                  let status=attachments.first?[.status] as? Int, status==SCFrameStatus.complete.rawValue,
                  let image=sampleBuffer.imageBuffer else { mailbox.idle(); return }
            if mailbox.offer(image,id:captureID,displayTime:displayTime) { work.async { [weak self] in self?.drainCapture() } }
        }
    }
    private func drainCapture() {
        guard active else { mailbox.stop(); return }
        guard let input = mailbox.takeInput() else { return }
        autoreleasepool { encode(input.image,captureID:input.id) }
        // Yield between frames so acknowledgements and the watchdog cannot starve.
        work.async { [weak self] in self?.drainCapture() }
    }
    private func process(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard active, type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
              let status = attachments.first?[.status] as? Int,status == SCFrameStatus.complete.rawValue else { inactive += 1; return }
        complete += 1
        guard let pixel = sampleBuffer.imageBuffer else { return }
        encode(pixel)
    }
    private func encode(_ pixel: CVPixelBuffer,captureID:UInt64=0) {
        guard inFlight.count < frameLimit else { skipped += 1;FrameTrace.shared.event("capture_backpressure",fields:["id":captureID]);return }
        do {
            let start = ProcessInfo.processInfo.systemUptime
            FrameTrace.shared.event("encode_begin",sequence:sequence+1,fields:["capture_id":captureID])
            guard let frame = try encoder.encode(pixel,sequence:sequence+1,force:sequence == 0) else { unchanged += 1;FrameTrace.shared.event("encode_unchanged",fields:["capture_id":captureID]);return }
            FrameTrace.shared.event("encode_end",sequence:frame.sequence,fields:["gpu_ms":encoder.lastGPUms,"wait_ms":encoder.lastWaitMS,"gather_ms":encoder.lastGatherMS,"tiles":frame.tiles.count])
            let packStart = ProcessInfo.processInfo.systemUptime
            let packet = try packer?.serialize(frame,parallel:parallelPacking) ?? frame.serialize(); encodeMS += (ProcessInfo.processInfo.systemUptime-start)*1000; encodes += 1
            gpuMS += encoder.lastGPUms; gpuWaitMS += encoder.lastWaitMS; gatherMS += encoder.lastGatherMS; packMS += (ProcessInfo.processInfo.systemUptime-packStart)*1000
            if encodeOnly {sequence += 1;FrameTrace.shared.event("discarded",sequence:sequence,fields:["bytes":packet.count]);return}
            sequence += 1; inFlight[sequence] = ProcessInfo.processInfo.systemUptime; sentBytes += packet.count
            FrameTrace.shared.event("packed",sequence:sequence,fields:["bytes":packet.count,"encoding":packet.first ?? 0])
            link.send(2,packet,traceSequence:sequence)
        } catch { fail(String(describing:error)) }
    }
    func stream(_ stream: SCStream,didStopWithError error: Error) { work.async { self.fail(String(describing:error)) } }
    private func fail(_ error: String) { guard active else { return }; active = false; onError?(error) }
    private func report() {
        let input = mailbox.counts()
        let timing = captureTiming.summary()
        if !inlineCapture { complete = input.complete; inactive = input.inactive }
        if captureOnly { complete = timing.complete }
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now-lastStats
        guard elapsed > 0 else { return }
        let timings = encodes == 0 && delivered == 0 ? "Idle — no sent or acknowledged frames in this interval." : String(format:"Average encode + pack %.1f ms · acknowledgement %.1f ms",encodeMS/Double(max(1,encodes)),ackMS/Double(max(1,delivered)))
        let transport = String(format:"\nSend queue + transport processing %.1f ms · ACK dispatch %.1f ms · coalesced %d",sendMS/Double(max(1,sendCount)),ackDispatchMS/Double(max(1,delivered)),input.replaced) + "\n" + timing.text + String(format:"\nEncoder GPU %.2f ms · GPU submit/wait %.2f ms · tile gather %.2f ms · packet pack %.2f ms",gpuMS/Double(max(1,encodes)),gpuWaitMS/Double(max(1,encodes)),gatherMS/Double(max(1,encodes)),packMS/Double(max(1,encodes)))
        let tails=String(format:"\nWorst ms: acknowledgement %.1f · send processing %.1f · ACK dispatch %.1f",maxACK,maxSend,maxACKDispatch)
        onStatus?(String(format:"%.1f delivered updates/s · %.1f Mbps · %d/%d frames in flight\nCapture %.1f/s · unchanged %d · backpressure skips %d · inactive %d\n",Double(delivered)/elapsed,Double(sentBytes)*8/elapsed/1e6,inFlight.count,frameLimit,Double(complete)/elapsed,unchanged,skipped,inactive) + timings + transport + tails)
        delivered = 0; sentBytes = 0; skipped = 0; lastStats = now
        complete = 0; unchanged = 0; inactive = 0; encodes = 0; encodeMS = 0; ackMS = 0
        sendMS = 0; sendCount = 0; ackDispatchMS = 0
        maxACK=0;maxSend=0;maxACKDispatch=0
        gpuMS = 0; gpuWaitMS = 0; gatherMS = 0; packMS = 0
    }
}

final class HostApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!, listener: NWListener?, link: Link?, capture: CaptureSession?
    var startup: Task<Void,Never>?, helloReceived = false, stopping = false
    var frameLimit = 2
    var parallelPacking = false
    var startingCapture = false, waitingForPermission = false
    var makeCapture: (Link) throws -> CaptureSession = { try CaptureSession(link:$0) }
    let profiles = NSPopUpButton()
    let pairingMode = NSPopUpButton(), pairingNote = label("",size:11)
    let pairing = NSTextField(), status = label("Ready. Start hosting, then connect from the Viewer."), stats = label("No display is being captured.")
    let addresses = label("")
    var button: NSButton!, newCodeButton: NSButton!, copyCodeButton: NSButton!, retryCaptureButton: NSButton!
    var pending: [ObjectIdentifier:Link] = [:]
    var recentDiagnostics: [String] = []
    var shortCode = "", longCode = randomPairingCode()
    var mode: PairingMode { PairingMode(rawValue:pairingMode.indexOfSelectedItem) ?? .shortCode }
    var code: String? { mode == .noCode ? nil : (mode == .shortCode ? shortCode : longCode) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        shortCode = savedShortCode(UserDefaults.standard.string(forKey:"hostShortCode")) { UserDefaults.standard.set($0,forKey:"hostShortCode") }
        pairingMode.addItems(withTitles:PairingMode.allCases.map(\.title))
        pairingMode.selectItem(at:(PairingMode(rawValue:UserDefaults.standard.integer(forKey:"pairingMode")) ?? .shortCode).rawValue)
        pairingMode.target = self; pairingMode.action = #selector(pairingModeChanged)
        pairing.isEditable = false; pairing.isSelectable = true
        pairing.font = .monospacedSystemFont(ofSize:16,weight:.medium); pairing.widthAnchor.constraint(equalToConstant:590).isActive = true
        profiles.addItems(withTitles:["Native 5K · 5120 × 2880 · target 60 fps","Native 5K · 5120 × 2880 · target 30 fps","Wi-Fi preview · 2560 × 1440 · target 30 fps"])
        profiles.selectItem(at:0)
        button = NSButton(title:"Start hosting",target:self,action:#selector(toggle))
        copyCodeButton = NSButton(title:"Copy code",target:self,action:#selector(copyCode))
        newCodeButton = NSButton(title:"New code",target:self,action:#selector(newCode))
        retryCaptureButton = NSButton(title:"Retry capture",target:self,action:#selector(retryCapture)); retryCaptureButton.isEnabled = false
        pairingModeChanged()
        addresses.stringValue = localAddresses()
        window = makeWindow("RetinaLink Host",views:[
            label("RetinaLink",size:30,weight:.bold),label("HOST  ·  VERSION \(LaunchOptions.version) · BUILD \(LaunchOptions.build)",size:11,weight:.semibold),
            label("Extend this Mac’s desktop to your iMac over Wi-Fi, Ethernet or Thunderbolt networking. Both Macs must be reachable on the local network."),
            label("Display profile",weight:.semibold),profiles,
            horizontal([label("Pairing",weight:.semibold),pairingMode]),pairing,pairingNote,
            horizontal([button,copyCodeButton,newCodeButton]),status,stats,
            horizontal([NSButton(title:"Copy diagnostics",target:self,action:#selector(copyDiagnostics)),retryCaptureButton,
                        NSButton(title:"Show app in Finder",target:self,action:#selector(revealApp))]),
            label("Manual connection addresses · port 58473",size:11,weight:.semibold),addresses,
            label("Experimental: 5K60 is a target, not a performance guarantee. BC7 texture compression is lossy. The acknowledgement cycle is not input-to-screen latency. Lower the profile if your network cannot keep up.",size:11)
        ],height:830)
        NSApp.activate(ignoringOtherApps:true)
        DiagnosticLog.shared.record("launch", "Host ready; activity \(!LaunchOptions.has("--no-streaming-activity")); capture depth \(LaunchOptions.value("--capture-depth") ?? "5"); tile layout \(!LaunchOptions.has("--row-major-encoder")); reusable packer \(!LaunchOptions.has("--baseline-packing")); baseline encoder \(LaunchOptions.has("--baseline-encoder")); inline capture \(LaunchOptions.has("--inline-capture"))")
        if LaunchOptions.has("--autostart") { start() }
    }
    @objc func pairingModeChanged() {
        UserDefaults.standard.set(mode.rawValue,forKey:"pairingMode")
        pairing.stringValue = code ?? "No code needed"; pairing.isEnabled = mode != .noCode
        copyCodeButton.isEnabled = mode != .noCode; newCodeButton.isEnabled = mode != .noCode
        switch mode {
        case .shortCode: pairingNote.stringValue = "Saved across restarts. Five digits are easy to guess; use on a trusted local network."
        case .longCode: pairingNote.stringValue = "Enter this long code in Viewer. A new long code is generated when Host reopens."
        case .noCode: pairingNote.stringValue = "Testing only: no encryption or access control. Anyone who can reach this Host can view the extended desktop. Select No code in Viewer too."
        }
    }
    @objc func newCode() {
        guard listener == nil, link == nil, !stopping else { return }
        if mode == .shortCode {
            let old = shortCode
            repeat { shortCode = randomShortCode() } while shortCode == old
            UserDefaults.standard.set(shortCode,forKey:"hostShortCode")
        } else if mode == .longCode { longCode = randomPairingCode() }
        pairingModeChanged()
    }
    @objc func copyCode() { guard let code = code else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code,forType:.string) }
    @objc func copyDiagnostics() {
        let samples = recentDiagnostics.isEmpty ? stats.stringValue : recentDiagnostics.joined(separator:"\n\n")
        let text = "RetinaLink Host \(LaunchOptions.version) (build \(LaunchOptions.build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)\nApp: \(Bundle.main.bundlePath)\nTransport: 0.2.2 baseline · default priority · whole-message I/O\nLegacy Screen Recording preflight: \(CGPreflightScreenCaptureAccess())\n\(profiles.titleOfSelectedItem ?? "")\n\(mode.connectionLabel)\n\(status.stringValue)\nRecent one-second samples, oldest first:\n\(samples)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
    }
    @objc func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc func retryCapture() {
        guard waitingForPermission, !startingCapture, !stopping, let peer = link else { return }
        beginCapture(peer)
    }
    @objc func toggle() { if listener != nil || link != nil { stop() } else { start() } }
    func start() {
        guard !stopping else { return }
        do {
            let listener = try NWListener(using:networkParameters(code),on:NWEndpoint.Port(rawValue:defaultPort)!)
            self.listener = listener; listener.service = NWListener.Service(name:Host.current().localizedName ?? "RetinaLink Host",type:serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready: self.status.stringValue = "Waiting for Viewer · \(self.mode.connectionLabel)"; self.addresses.stringValue = localAddresses(); DiagnosticLog.shared.record("state", "Waiting for Viewer")
                case .failed(let error): self.stop(message:"Could not listen: \(error)")
                case .waiting(let error): self.status.stringValue = "Waiting for network permission: \(error)"
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue:.main); button.title = "Stop hosting"; profiles.isEnabled = false
            pairingMode.isEnabled = false; newCodeButton.isEnabled = false
        } catch { status.stringValue = String(describing:error) }
    }
    func accept(_ connection: NWConnection) {
        guard link == nil, pending.count < 4 else { connection.cancel(); return }
        let peer = Link(connection), id = ObjectIdentifier(connection); pending[id] = peer
        peer.onReady = { [weak self,weak peer] in
            DispatchQueue.main.async {
                guard let self = self, let peer = peer else { return }
                guard self.link == nil, self.listener != nil else { peer.cancel(); return }
                self.pending.removeValue(forKey:id); self.link = peer; self.helloReceived = false
                for other in self.pending.values { other.cancel() }; self.pending.removeAll()
                self.status.stringValue = "\(self.mode.connectionLabel) · \(peer.pathLabel)"
                DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self,weak peer] in
                    guard let self = self, self.link === peer, !self.helloReceived else { return }; peer?.cancel()
                }
            }
        }
        peer.onMessage = { [weak self,weak peer] type,data in
            DispatchQueue.main.async {
                guard let self = self, let peer = peer, self.link === peer else { return }
                if type == 1, !self.helloReceived {
                    do {
                        guard data.count < 4096 else { throw LinkError.invalid("Invalid Viewer greeting") }
                        let hello = try JSONDecoder().decode(Hello.self,from:data)
                        guard hello.version == 1, hello.bc7 else { throw LinkError.invalid("Viewer does not support this protocol or GPU format") }
                        self.frameLimit = try hello.frameLimit(requested:Int(LaunchOptions.value("--frames-in-flight") ?? "3") ?? 3)
                        self.parallelPacking = hello.chunkedPacking == true && !LaunchOptions.has("--serial-packing")
                        self.helloReceived = true; self.beginCapture(peer)
                    } catch { self.stop(message:String(describing:error)) }
                } else if type == 3, self.helloReceived { self.capture?.acknowledge(data) }
                else { peer.cancel() }
            }
        }
        peer.onClose = { [weak self,weak peer] reason in
            DispatchQueue.main.async {
                guard let self = self else { return }; self.pending.removeValue(forKey:id)
                if let peer = peer, self.link === peer { self.stop(message:reason) }
            }
        }
        peer.start()
    }
    func beginCapture(_ peer: Link) {
        guard !startingCapture, !stopping, link === peer else { return }
        startingCapture = true; waitingForPermission = false; retryCaptureButton?.isEnabled = false
        status.stringValue = "Starting capture · waiting for macOS authorization if needed…"
        recentDiagnostics.removeAll()
        let index = profiles.indexOfSelectedItem, width = index == 2 ? 2560 : 5120, height = index == 2 ? 1440 : 2880, fps = index == 0 ? 60 : 30
        startup = Task { @MainActor [weak self,weak peer] in
            guard let self = self, let peer = peer else { return }
            var attemptedSession: CaptureSession?
            do {
                let session = try self.makeCapture(peer); self.capture = session
                session.frameLimit = self.frameLimit
                session.parallelPacking = self.parallelPacking
                attemptedSession = session
                peer.setAcknowledgementHandler { [weak session] data in session?.acknowledge(data) }
                peer.setSendTimingHandler { [weak session] type, milliseconds in
                    if type == 2 { session?.recordSend(milliseconds) }
                }
                session.onStatus = { [weak self,weak session] text in DispatchQueue.main.async {
                    guard let self = self, self.capture === session else { return }
                    self.stats.stringValue = text; self.recentDiagnostics.append(text)
                    DiagnosticLog.shared.record("host", text)
                    if self.recentDiagnostics.count > 15 { self.recentDiagnostics.removeFirst() }
                } }
                session.onError = { [weak self] text in DispatchQueue.main.async { self?.stop(message:text) } }
                try await session.start(width:width,height:height,fps:fps)
                guard !Task.isCancelled, self.link === peer else { await session.stop(); return }
                self.startingCapture = false
                self.status.stringValue = "Streaming \(width) × \(height) · target \(fps) fps · \(peer.pathLabel)\n\(self.mode.connectionLabel)"
                DiagnosticLog.shared.record("state", self.status.stringValue)
                peer.send(4,Data(self.status.stringValue.utf8))
            } catch {
                if let session = attemptedSession {
                    session.onStatus = nil; session.onError = nil
                    await session.stop()
                    if self.capture === session { self.capture = nil }
                }
                guard !Task.isCancelled, !self.stopping, self.link === peer else { return }
                self.startingCapture = false
                if CaptureAuthorization.isDenied(error) {
                    self.waitForCapturePermission(peer,error:error)
                } else { self.stop(message:String(describing:error)) }
            }
        }
    }
    func waitForCapturePermission(_ peer: Link, error: Error) {
        guard link === peer, !stopping else { return }
        waitingForPermission = true; retryCaptureButton?.isEnabled = true
        status.stringValue = "Waiting for Screen Recording permission. Host is still listening."
        stats.stringValue = "Enable this copy of RetinaLink Host in System Settings, then click Retry capture. If macOS requests a restart, quit and reopen Host.\nIf already enabled after an update, reset this app’s Screen Recording entry."
        let error = error as NSError
        DiagnosticLog.shared.record("state", "Waiting for capture permission: \(error.domain) \(error.code)")
        recentDiagnostics.append("Capture authorization: \(error.domain) \(error.code) · \(error.localizedDescription)")
        peer.send(4,Data("Host is waiting for Screen Recording permission. Keep Viewer connected; enable permission and click Retry capture on Host.".utf8))
    }
    func stop(message: String = "Stopped. Your virtual display has been released.") {
        DiagnosticLog.shared.record("state", message)
        guard !stopping else { return }; stopping = true; button?.isEnabled = false
        retryCaptureButton?.isEnabled = false
        startup?.cancel(); let startup = self.startup; self.startup = nil
        listener?.cancel(); listener = nil
        let peer = link; link = nil; peer?.cancel()
        for p in pending.values { p.cancel() }; pending.removeAll()
        Task { @MainActor [weak self] in
            await startup?.value
            guard let self = self else { return }
            if let capture = self.capture { await capture.stop() }; self.capture = nil
            self.status.stringValue = message; self.stats.stringValue = "No display is being captured."
            self.button?.title = "Start hosting"; self.button?.isEnabled = true; self.profiles.isEnabled = true; self.stopping = false
            self.startingCapture = false; self.waitingForPermission = false
            self.pairingMode.isEnabled = true; self.pairingModeChanged()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { listener?.cancel(); link?.cancel(); startup?.cancel(); capture = nil }
}
#endif
