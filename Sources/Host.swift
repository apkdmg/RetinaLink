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
    private var ages = 0, ageMS = 0.0, maxAgeMS = -Double.infinity, minAgeMS = Double.infinity
    func record(status: Int, displayTime: UInt64?) {
        lock.lock(); defer { lock.unlock() }
        counts[min(6,max(0,status))] += 1
        guard status == SCFrameStatus.complete.rawValue, let ticks = displayTime, ticks > 0 else { return }
        let displayed = CMClockMakeHostTimeFromSystemUnits(ticks).seconds
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        // Display timestamps can be ahead of callback delivery on a virtual
        // display. Keep the signed offset rather than hiding it as zero lag.
        let age = (now-displayed)*1000
        ageMS += age; maxAgeMS = max(maxAgeMS,age);minAgeMS=min(minAgeMS,age);ages += 1
        if let previous = lastDisplay, displayed > previous {
            let gap = (displayed-previous)*1000
            gaps += 1; gapMS += gap; maxGapMS = max(maxGapMS,gap)
            if gap > 25 { late += 1 }
        }
        lastDisplay = displayed
    }
    func summary() -> (complete:Int,text:String) {
        lock.lock(); defer { lock.unlock() }
        let text = String(format:"Capture callbacks complete %d · idle %d · blank %d · suspended %d · other %d\nSource display gap %.2f ms · max %.2f ms · gaps >25 ms %d · callback/display offset %.2f ms · range %.2f…%.2f ms",counts[0],counts[1],counts[2],counts[3],counts[4]+counts[5]+counts[6],gapMS/Double(max(1,gaps)),maxGapMS,late,ageMS/Double(max(1,ages)),ages==0 ? 0:minAgeMS,ages==0 ? 0:maxAgeMS)
        let result = (counts[0],text)
        counts = [Int](repeating:0,count:7); gaps = 0; gapMS = 0; maxGapMS = 0; late = 0; ages = 0; ageMS = 0; maxAgeMS = -Double.infinity;minAgeMS=Double.infinity
        return result
    }
}

final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    let work = DispatchQueue(label:"retinalink.capture",qos:.userInteractive,autoreleaseFrequency:.workItem)
    let captureQueue = DispatchQueue(label:"retinalink.capture.ingress",qos:.userInteractive,autoreleaseFrequency:.workItem)
    let mailbox = CaptureMailbox()
    var creditGate = CaptureCreditGate()
    let dropCreditFrames = LaunchOptions.has("--drop-credit-frames")
    var creditWaits = 0, creditResumes = 0
    let captureTiming = CaptureTiming()
    let captureOnly = LaunchOptions.has("--capture-only")
    let encodeOnly = LaunchOptions.has("--encode-only")
    var captureID:UInt64 = 0
    let inlineCapture = LaunchOptions.has("--inline-capture")
    let link: Link, encoder: TextureEncoder
    let probe:CaptureProbe?
    let packer: FramePacker? = LaunchOptions.has("--baseline-packing") ? nil:FramePacker()
    var stream: SCStream?, virtual: RLVirtualDisplay?
    var captureCycle:Task<Void,Never>?
    let captureCyclePeriod:Double?
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
    init(link: Link) throws {
        self.link=link;encoder=try TextureEncoder()
        if let raw=LaunchOptions.value("--capture-cycle-period") {
            guard let seconds=Double(raw),seconds.isFinite,(10...60).contains(seconds) else {throw LinkError.invalid("Capture cycle period must be 10…60 seconds")}
            captureCyclePeriod=seconds
        } else {captureCyclePeriod=nil}
        if let plan=LaunchOptions.value("--probe-plan") {probe=try CaptureProbe(plan:plan,period:Double(LaunchOptions.value("--probe-period") ?? "30") ?? 30,hold:Double(LaunchOptions.value("--probe-hold") ?? "0.006") ?? 0.006)} else {probe=nil}
        super.init()
    }
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
        work.sync { creditGate.reset(); active = true }
        mailbox.start()
        try await stream.startCapture()
        if let period=captureCyclePeriod {
            DiagnosticLog.shared.record("capture-cycle","Capture on; virtual display retained; period \(period)")
            captureCycle=Task { @MainActor [weak self,weak stream] in
                var paused=false
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds:UInt64(period*1e9))
                        guard let self=self,let stream=stream,self.stream === stream else{return}
                        if paused {try await stream.startCapture()} else {try await stream.stopCapture()}
                        paused.toggle()
                        DiagnosticLog.shared.record("capture-cycle",paused ? "Capture off; virtual display retained":"Capture on; virtual display retained")
                    } catch {
                        if Task.isCancelled {return}
                        self?.work.async {[weak self] in self?.fail("Capture cycle: \(error)")};return
                    }
                }
            }
        }
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
        captureCycle?.cancel();captureCycle=nil
        mailbox.stop()
        work.sync { active = false; creditGate.reset(); watchdog?.cancel(); watchdog = nil; inFlight.removeAll() }
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
                if self.creditGate.resumeAfterAcknowledgement(inFlight:self.inFlight.count,limit:self.frameLimit) {
                    self.creditResumes += 1
                    FrameTrace.shared.event("capture_credit_resume",sequence:seq,fields:["in_flight":self.inFlight.count,"limit":self.frameLimit])
                    self.work.async { [weak self] in self?.drainCapture() }
                }
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
        guard active else { creditGate.reset(); mailbox.stop(); return }
        if !dropCreditFrames && !encodeOnly && probe == nil {
            let wasWaiting = creditGate.waiting
            if creditGate.pauseIfFull(inFlight:inFlight.count,limit:frameLimit,mailbox:mailbox) {
                if creditGate.waiting && !wasWaiting {
                    creditWaits += 1
                    FrameTrace.shared.event("capture_credit_wait",fields:["in_flight":inFlight.count,"limit":frameLimit])
                }
                return
            }
        }
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
        if let probe=probe {
            do {try probe.process(pixel,encoder:encoder,packer:packer,parallel:parallelPacking)} catch {fail(String(describing:error))}
            return
        }
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
    private func fail(_ error: String) { guard active else { return }; active = false; creditGate.reset(); mailbox.stop(); onError?(error) }
    private func report() {
        let input = mailbox.counts()
        let timing = captureTiming.summary()
        if !inlineCapture { complete = input.complete; inactive = input.inactive }
        if captureOnly { complete = timing.complete }
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now-lastStats
        guard elapsed > 0 else { return }
        let timings = encodes == 0 && delivered == 0 ? "Idle — no sent or acknowledged frames in this interval." : String(format:"Average encode + pack %.1f ms · acknowledgement %.1f ms",encodeMS/Double(max(1,encodes)),ackMS/Double(max(1,delivered)))
        let transport = String(format:"\nSend queue + transport processing %.1f ms · ACK dispatch %.1f ms · coalesced %d",sendMS/Double(max(1,sendCount)),ackDispatchMS/Double(max(1,delivered)),input.replaced) + "\n" + timing.text + String(format:"\nEncoder GPU %.2f ms · GPU submit/wait %.2f ms · tile gather %.2f ms · packet pack %.2f ms",gpuMS/Double(max(1,encodes)),gpuWaitMS/Double(max(1,encodes)),gatherMS/Double(max(1,encodes)),packMS/Double(max(1,encodes)))
        let probeText=probe.map {"\n"+$0.report()} ?? ""
        let tails=String(format:"\nWorst ms: acknowledgement %.1f · send processing %.1f · ACK dispatch %.1f",maxACK,maxSend,maxACKDispatch)
        let creditText=String(format:"\nCredit waits %d · ACK resumes %d · pending for credit %@",creditWaits,creditResumes,creditGate.waiting ? "yes":"no")
        onStatus?(String(format:"%.1f delivered updates/s · %.1f Mbps · %d/%d frames in flight\nCapture %.1f/s · unchanged %d · backpressure skips %d · inactive %d\n",Double(delivered)/elapsed,Double(sentBytes)*8/elapsed/1e6,inFlight.count,frameLimit,Double(complete)/elapsed,unchanged,skipped,inactive) + timings + transport + tails + creditText + probeText)
        delivered = 0; sentBytes = 0; skipped = 0; lastStats = now
        complete = 0; unchanged = 0; inactive = 0; encodes = 0; encodeMS = 0; ackMS = 0
        sendMS = 0; sendCount = 0; ackDispatchMS = 0
        maxACK=0;maxSend=0;maxACKDispatch=0
        creditWaits=0;creditResumes=0
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
    var trustedCredential: String?
    var reconnectEnabled = false, quitting = false
    var displayPaused = UserDefaults.standard.bool(forKey:"displayPaused")
    var setupController: HostSetupController?, tunnel: TunnelSupervisor?
    var nativeSetupController:NativeHostSetup?
    var forgettingNative = false
    var homeTimer: Timer?, statusItem: NSStatusItem?
    var windowLifecycle: HostWindowLifecycle?
    var updatingViewer = false
    var updateButton: NSButton?
    let softwareUpdater = AutomaticUpdater()
    let automaticUpdates = NSButton(checkboxWithTitle:"Automatically keep both Macs up to date",target:nil,action:nil)
    let hostUpdateNote = Design.text("",12,secondary:true)
    let viewerUpdateNote = Design.text("iMac: waiting for display connection.",12,secondary:true)
    var viewerSupportsUpdates = false
    var viewerUpdateRelay: HostUpdateRelay?
    var viewerSupportsRelay = false
    var viewerUpdateState: SoftwareUpdateStatus?
    var pendingHostUpdate = false
    var viewerUpdateRequested: Bool {
        get { UserDefaults.standard.bool(forKey:"RetinaLink.viewerUpdateRequested") }
        set { UserDefaults.standard.set(newValue,forKey:"RetinaLink.viewerUpdateRequested") }
    }
    var viewerUpdateTarget: String? {
        get { UserDefaults.standard.string(forKey:"RetinaLink.viewerUpdateTarget") }
        set { UserDefaults.standard.set(newValue,forKey:"RetinaLink.viewerUpdateTarget") }
    }
    let displayName = Design.text("A second life for your iMac.",23,.semibold)
    let displaySubtitle = Design.text("Your desktop, beautifully extended.",14,secondary:true)
    let restartNote = Design.text("",12,secondary:true)
    let connectionNote = Design.text("",12,secondary:true)
    let homeStatus = Design.text("Ready to add a display",13,.medium)
    var advanced: NSView?
    var mode: PairingMode { PairingMode(rawValue:pairingMode.indexOfSelectedItem) ?? .shortCode }
    var code: String? { trustedCredential ?? (mode == .noCode ? nil : (mode == .shortCode ? shortCode : longCode)) }
    var connectionLabel: String { trustedCredential == nil ? mode.connectionLabel : "Encrypted · trusted display" }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        UpdateSettings.applyLaunchOptions()
        if UpdateSettings.returnToStartupAgentIfNeeded() { return }
        do { trustedCredential = try DeviceVault.credential() }
        catch { DiagnosticLog.shared.record("state",String(describing:error)); connectionNote.stringValue = String(describing:error) }
        reconnectEnabled = DeviceSettings.binding != nil && trustedCredential != nil
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
        makeHome()
        if let statusItem = statusItem {
            let lifecycle = HostWindowLifecycle(home:window,statusItem:statusItem)
            windowLifecycle = lifecycle; lifecycle.start(background:LaunchOptions.has("--autostart"))
        }
        DiagnosticLog.shared.record("launch", "Host ready; activity \(!LaunchOptions.has("--no-streaming-activity")); capture depth \(LaunchOptions.value("--capture-depth") ?? "5"); tile layout \(!LaunchOptions.has("--row-major-encoder")); reusable packer \(!LaunchOptions.has("--baseline-packing")); baseline encoder \(LaunchOptions.has("--baseline-encoder")); inline capture \(LaunchOptions.has("--inline-capture"))")
        if LaunchOptions.has("--autostart") || reconnectEnabled { start() }
        if reconnectEnabled { startTunnel() }
        homeTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.refreshHome() }
        if let path = LaunchOptions.value("--export-ui") { DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in if let window = self?.window { Design.export(window,path:path) } } }
        if LaunchOptions.has("--setup-viewer") { runAutomatedSetup() }
        if LaunchOptions.has("--update-viewer") { updateViewerSoftware() }
        softwareUpdater.onChange = { [weak self] status in self?.hostUpdateNote.stringValue = "This Mac: "+status.message }
        softwareUpdater.start()
    }
    func makeHome() {
        let title = horizontal([Design.symbol("display.2",size:27),Design.text("RetinaLink",19,.semibold)])
        let artwork = MonitorArtwork(); artwork.widthAnchor.constraint(equalToConstant:230).isActive = true; artwork.heightAnchor.constraint(equalToConstant:145).isActive = true
        let information = Design.vertical([displayName,displaySubtitle,homeStatus,connectionNote],spacing:10)
        let hero = Design.card([horizontal([artwork,information]),horizontal([
            Design.button("Arrange Displays",target:self,action:#selector(arrange)),
            Design.button("Identify",target:self,action:#selector(identify)),button])],padding:25)
        let add = Design.button("Add Display",target:self,action:#selector(addDisplay),primary:true)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let heading = horizontal([Design.vertical([Design.text("Your displays",30,.bold),Design.text("Set up once. Connect effortlessly.",14,secondary:true)],spacing:7),spacer,add])
        let automatic = Design.card([Design.message("Always ready, after sign-in",detail:"Connect your Macs with a compatible USB data cable or Ethernet. Viewer finds the connection and reconnects automatically. Your display stays paired and company network settings stay unchanged.",symbol:"arrow.triangle.2.circlepath"),restartNote,
            horizontal([Design.button("Display Setup…",target:self,action:#selector(addDisplay)),Design.button("Dedicated Display Guide…",target:self,action:#selector(dedicatedGuide))])])
        updateButton = Design.button("Update Display Software…",target:self,action:#selector(updateViewerSoftware))
        let details = Design.card([Design.text("Connection details",17,.semibold),Design.text("Native 5K at a target of 60 updates/s. Actual performance depends on capture and network conditions.",12,secondary:true),status,profiles,stats,updateButton!,
            horizontal([Design.button("Copy Diagnostics",target:self,action:#selector(copyDiagnostics)),retryCaptureButton]),
            Design.button("Forget Display…",target:self,action:#selector(forgetDisplay)),
            Design.text("Legacy connection",13,.semibold),horizontal([pairingMode,copyCodeButton,newCodeButton]),pairing,pairingNote,addresses])
        details.isHidden = true; advanced = details
        stats.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        let footer = horizontal([Design.button("Connection Details",target:self,action:#selector(toggleDetails)),Design.text("RetinaLink \(LaunchOptions.version)",11,secondary:true)])
        automaticUpdates.state = UpdateSettings.automatic ? .on : .off
        automaticUpdates.target = self; automaticUpdates.action = #selector(automaticUpdatesChanged)
        let software = Design.card([horizontal([Design.symbol("arrow.down.circle",size:22),Design.text("Always up to date",17,.semibold)]),automaticUpdates,hostUpdateNote,viewerUpdateNote,
            horizontal([Design.text("Signed updates install automatically. Your display reconnects and stays paired.",12,secondary:true),Design.button("Update Now…",target:self,action:#selector(updateBothNow))])])
        let content = Design.vertical([title,heading,hero,automatic,software,footer,details],spacing:20)
        heading.widthAnchor.constraint(equalTo:content.widthAnchor).isActive = true
        for card in [hero,automatic,software,details] { card.widthAnchor.constraint(equalTo:content.widthAnchor).isActive = true }
        window = Design.window("RetinaLink",content:content,width:940,height:880,show:false)
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if #available(macOS 11.0, *) { item.button?.image = NSImage(systemSymbolName:"display.2",accessibilityDescription:"RetinaLink") }
        let menu = NSMenu()
        menu.addItem(withTitle:"Open RetinaLink",action:#selector(openHome),keyEquivalent:"").target = self
        menu.addItem(withTitle:"Display Setup…",action:#selector(addDisplay),keyEquivalent:"").target = self
        menu.addItem(withTitle:"Update RetinaLink…",action:#selector(updateBothNow),keyEquivalent:"").target = self
        menu.addItem(.separator()); menu.addItem(withTitle:"Quit RetinaLink",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.menu = menu; statusItem = item; refreshHome()
    }
    func refreshHome() {
        consumeTestCommand()
        updateButton?.isEnabled = !updatingViewer && DeviceSettings.binding != nil && trustedCredential != nil && DistributionTrust.team != nil
        if let binding = DeviceSettings.binding {
            displayName.stringValue = binding.viewerName
            displaySubtitle.stringValue = displayPaused ? "Paused · still securely paired" : (capture == nil ? "Ready to connect · Native 5K" : "Extended desktop · Native 5K")
            homeStatus.stringValue = waitingForPermission ? "Allow Screen Recording on this Mac to continue" : (displayPaused ? "Ready whenever you are" : (startingCapture ? "Preparing your desktop…" : (capture == nil ? "Waiting for your iMac" : "Connected securely")))
            homeStatus.textColor = waitingForPermission ? .systemOrange : (capture == nil ? .secondaryLabelColor : .systemGreen)
            restartNote.stringValue = binding.dedicatedDisplay && binding.automaticLoginConfigured ? "Dedicated display · automatic login and Viewer startup configured. FileVault unchanged. Manual locking still requires a password." : binding.fileVault.setupMessage
            button?.title = displayPaused ? "Connect" : "Disconnect"
            button?.action = #selector(toggle)
            if trustedCredential == nil {
                homeStatus.stringValue = "Finish display setup to restore this connection"
                button?.title = "Restore Pairing"; button?.action = #selector(addDisplay)
            }
            if waitingForPermission { button?.title = "Retry Capture"; button?.action = #selector(retryCapture) }
            pairing.stringValue = "Device pairing is managed automatically."
            pairingNote.stringValue = "Credentials are stored in Keychain. Your iMac stays paired across app restarts."
            copyCodeButton?.isHidden = true; newCodeButton?.isHidden = true; pairingMode.isHidden = true
        } else {
            restartNote.stringValue = "Setup checks FileVault first and explains any restart limits. No disk changes or additional macOS installation."
            displaySubtitle.stringValue = "Install Viewer on your iMac once, then choose Add Display. No Remote Login needed."
            button?.title = "Set Up Display"; button?.action = #selector(addDisplay)
            if listener == nil && link == nil { homeStatus.stringValue = "Ready for setup from this Mac" }
        }
        if let path = LaunchOptions.value("--ui-state-path") ?? Optional(NSHomeDirectory()+"/Library/Logs/RetinaLink/Host-ui.json") {
            let state: [String:Any] = ["version":LaunchOptions.version,"build":LaunchOptions.build,"pid":ProcessInfo.processInfo.processIdentifier,"trusted":reconnectEnabled,"paused":displayPaused,"listening":listener != nil,"streaming":capture != nil && helloReceived,"setupStage":nativeSetupController?.stage ?? setupController?.stage ?? "closed","fileVault":DeviceSettings.binding?.fileVault.rawValue ?? "unknown","transport":NativeConnectionSettings.enabled ? "direct-tls" : "legacy-ssh","requiresRemoteLogin":!NativeConnectionSettings.enabled,"connectionID":link?.traceID ?? "","provisionalConnections":pending.count,"connectionPath":link.map { DirectLinkPath.metadata(connection:$0.connection) } ?? [:],"networkSettingsChanged":false,"time":Date().timeIntervalSince1970]
            var report = state; report["windowPresentation"] = windowLifecycle?.metadata ?? [:]
            report["viewerUpdateRelay"] = viewerSupportsRelay
            report["viewerUpdateRequested"] = viewerUpdateRequested
            if let update = viewerUpdateState, let data = try? JSONEncoder().encode(update),
               let value = try? JSONSerialization.jsonObject(with:data) { report["viewerUpdate"] = value }
            if let data = try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys) { try? data.write(to:URL(fileURLWithPath:path),options:.atomic); try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path) }
        }
    }
    func consumeTestCommand() {
        // Explicit, local-only test seam: exercises the actual button actions
        // without an accessibility/screen-capture helper. Absent in normal runs.
        guard let directory = LaunchOptions.value("--test-control-directory") else { return }
        let folder = URL(fileURLWithPath:directory,isDirectory:true), file = folder.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf:file), data.count <= 1024,
              let item = try? JSONSerialization.jsonObject(with:data) as? [String:String], let command = item["command"] else { return }
        try? FileManager.default.removeItem(at:file)
        switch command {
        case "pause": if !displayPaused { toggle() }
        case "resume": if displayPaused { toggle() }
        case "identify": identify()
        case "close-home": window.close()
        case "open-home": openHome()
        case "snapshot": Design.export(window,path:folder.appendingPathComponent("host-ui.png").path)
        case "snapshot-setup": if let window = setupController?.window { Design.export(window,path:folder.appendingPathComponent("setup-ui.png").path) }
        case "forget": forgetConfirmed()
        case "reenroll": setupController?.window?.close(); setupController = nil; runAutomatedSetup()
        case "updates-check": checkUpdatesBoth(installNow:false)
        case "updates-install": checkUpdatesBoth(installNow:true)
        case "updates-interrupt-next-transfer": viewerUpdateRelay?.interruptNextArchiveForTesting()
        case "updates-automatic": setAutomaticUpdates(item["enabled"] == "true")
        case "updates-test-feed":
            if let url = item["url"], url.isEmpty || UpdateSettings.validTestBase(url) {
                softwareUpdater.configureTestBase(url)
                sendUpdateCommand(SoftwareUpdateCommand(action:"test-feed",testBaseURL:url))
            }
        default: break
        }
    }
    @objc func openHome() { windowLifecycle?.showHome() }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        openHome(); return false
    }
    @objc func automaticUpdatesChanged() { setAutomaticUpdates(automaticUpdates.state == .on) }
    func setAutomaticUpdates(_ enabled: Bool) {
        softwareUpdater.setAutomatic(enabled); automaticUpdates.state = enabled ? .on : .off
        sendUpdateCommand(SoftwareUpdateCommand(action:"automatic",automatic:enabled))
    }
    func sendUpdateCommand(_ command: SoftwareUpdateCommand) {
        guard trustedCredential != nil, viewerSupportsUpdates, let peer = link, helloReceived,
              let data = try? JSONEncoder().encode(command) else { return }
        peer.send(6,data)
    }
    @objc func updateBothNow() {
        openHome()
        let alert = NSAlert(); alert.messageText = "Update RetinaLink on both Macs?"
        alert.informativeText = "RetinaLink checks for signed updates and installs any available versions. Your display may reconnect briefly. Pairing and login settings stay unchanged."
        alert.addButton(withTitle:"Update Now"); alert.addButton(withTitle:"Later")
        if alert.runModal() == .alertFirstButtonReturn { checkUpdatesBoth(installNow:true) }
    }
    func checkUpdatesBoth(installNow: Bool) {
        if installNow { viewerUpdateRequested = true; viewerUpdateTarget = nil }
        if installNow, viewerSupportsRelay, link != nil, helloReceived {
            pendingHostUpdate = true
            viewerUpdateNote.stringValue = "iMac: checking through this Mac…"
            sendUpdateCommand(SoftwareUpdateCommand(action:"install")); return
        }
        if installNow, link == nil { viewerUpdateNote.stringValue = "iMac: update queued until the display reconnects." }
        sendUpdateCommand(SoftwareUpdateCommand(action:installNow ? "install" : "check"))
        softwareUpdater.check(installNow:installNow)
    }
    func releaseHostUpdate() {
        guard pendingHostUpdate else { return }; pendingHostUpdate = false
        softwareUpdater.check(installNow:true)
    }
    func observeViewerUpdate(_ update: SoftwareUpdateStatus) {
        viewerUpdateState = update
        if let target = update.targetBuild, Int(target) != nil { viewerUpdateTarget = target }
        viewerUpdateNote.stringValue = "iMac: "+String(update.message.prefix(240))
        if update.phase == "reconnected", viewerUpdateRequested,
           let target = viewerUpdateTarget, UpdateRelayPolicy.confirmed(installed:update.build,target:target,fullscreen:update.fullscreen == true) {
            viewerUpdateRequested = false; viewerUpdateTarget = nil
            viewerUpdateNote.stringValue = "iMac: updated to \(update.version) (\(update.build)) · reconnected fullscreen."
            releaseHostUpdate()
        } else if update.phase == "up-to-date" {
            if viewerUpdateRequested, let target = viewerUpdateTarget {
                if (Int(update.build) ?? -1) < (Int(target) ?? Int.max) {
                    viewerUpdateNote.stringValue = "iMac: update has not completed. Installed \(update.version) (\(update.build)); waiting for build \(target)."
                } else { viewerUpdateNote.stringValue = "iMac: installed \(update.version) (\(update.build)) · waiting for fullscreen display…" }
            } else { viewerUpdateRequested = false; viewerUpdateTarget = nil; releaseHostUpdate() }
        } else if update.phase == "error" { releaseHostUpdate() }
    }
    @objc func updateViewerSoftware() {
        if NativeConnectionSettings.enabled || DeviceSettings.binding?.managementUsername != nil { checkUpdatesBoth(installNow:true); return }
        guard !updatingViewer, let binding = DeviceSettings.binding, trustedCredential != nil else { return }
        updatingViewer = true; connectionNote.stringValue = "Updating display software. Pairing will be preserved…"
        DispatchQueue.global(qos:.utility).async { [weak self] in
            var report: [String:Any]
            do {
                let connection = try SetupConnection(SetupTarget(address:binding.address,username:binding.username,managementSocket:LaunchOptions.value("--ssh-control-path")))
                let result = try connection.updateViewer(binding:binding)
                report = ["success":true,"version":result.version,"build":result.build,"pairingPreserved":true]
            } catch { report = ["success":false,"error":String(describing:error)] }
            if let path = LaunchOptions.value("--update-report"), let data = try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys) { try? data.write(to:URL(fileURLWithPath:path),options:.atomic) }
            let message = report["success"] as? Bool == true ? "Display software updated. Your pairing is unchanged." : (report["error"] as? String ?? "Display update could not finish.")
            DispatchQueue.main.async { self?.updatingViewer = false; self?.connectionNote.stringValue = message; self?.refreshHome() }
        }
    }
    @objc func toggleDetails() { advanced?.isHidden.toggle() }
    @objc func arrange() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
    @objc func identify() { link?.send(5,Data("identify".utf8)) }
    @objc func forgetDisplay() {
        guard let binding = DeviceSettings.binding else { return }
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Forget \(binding.viewerName)?"
        alert.informativeText = "This disconnects the display and removes saved pairing and automatic Viewer startup. The iMac must be reachable to finish. Its FileVault, files and login settings stay unchanged."
        alert.addButton(withTitle:"Forget Display"); alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn { forgetConfirmed() }
    }
    func forgetConfirmed() {
        guard let binding = DeviceSettings.binding else { return }
        if binding.managementUsername != nil && binding.dedicatedDisplay {
            connectionNote.stringValue = "Turn off Dedicated Mode first to restore ordinary login, then forget this display."
            dedicatedGuide(); return
        }
        if NativeConnectionSettings.enabled {
            guard let peer = link, helloReceived else { connectionNote.stringValue = "Reconnect your iMac before forgetting it. Your pairing is kept."; return }
            forgettingNative = true; peer.send(8,Data(binding.hostID.utf8))
            connectionNote.stringValue = "Removing pairing through your encrypted app connection…"
            DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self] in
                guard let self = self, self.forgettingNative else { return }
                self.forgettingNative = false; self.connectionNote.stringValue = "Could not confirm removal. Your Host pairing is kept. Reconnect Viewer and try again."
            }
            return
        }
        connectionNote.stringValue = "Removing pairing securely…"
        DispatchQueue.global(qos:.utility).async { [weak self] in
            do {
                let connection = try SetupConnection(SetupTarget(address:binding.address,username:binding.username,managementSocket:LaunchOptions.value("--ssh-control-path")))
                try connection.ensure(); try connection.removeBinding(binding.hostID)
                connection.releaseOldForward()
                DeviceVault.remove(DeviceVault.credentialAccount); DeviceVault.remove(TunnelIdentity.account)
                UserDefaults.standard.removeObject(forKey:DeviceSettings.bindingKey); UserDefaults.standard.synchronize()
                try? FileManager.default.removeItem(at:StartupAgent.path(role:"Host"))
                DispatchQueue.main.async {
                    guard let self = self else { return }; self.reconnectEnabled = false; self.trustedCredential = nil; self.tunnel?.stop(); self.tunnel = nil
                    self.stop(message:"Display removed. Choose Add Display to set it up again.",reconnect:false)
                    self.displayName.stringValue = "A second life for your iMac."; self.connectionNote.stringValue = "Pairing removed on both Macs."
                    self.refreshHome()
                }
            } catch { DispatchQueue.main.async { self?.connectionNote.stringValue = String(describing:error) } }
        }
    }
    @objc func dedicatedGuide() {
        legacyDisplaySetup()
        if let controller = setupController { controller.dedicated.state = .on; controller.advance() }
    }
    @objc func addDisplay() {
        windowLifecycle?.prepareForControls()
        if nativeSetupController == nil {
            let controller = NativeHostSetup(); nativeSetupController = controller
            controller.onPrepared = { [weak self] in self?.enrollmentCompleted($0) }
        }
        nativeSetupController?.show()
    }
    func legacyDisplaySetup() {
        windowLifecycle?.prepareForControls()
        if setupController == nil { setupController = HostSetupController(host:self) }
        setupController?.show()
    }
    func enrollmentCompleted(_ binding: DeviceBinding) {
        do { trustedCredential = try DeviceVault.credential() } catch { connectionNote.stringValue = String(describing:error); return }
        reconnectEnabled = true; displayPaused = false; UserDefaults.standard.set(false,forKey:"displayPaused")
        stop(message:"Your display is paired. Connecting automatically…")
        startTunnel(); refreshHome()
        DiagnosticLog.shared.record("setup","Enrollment complete; encrypted trusted pairing; Viewer startup enabled; FileVault unchanged")
    }
    func startTunnel() {
        if NativeConnectionSettings.enabled || LaunchOptions.has("--native-only") {
            tunnel?.stop(disconnect:true); tunnel = nil
            DispatchQueue.global(qos:.utility).async { TunnelSupervisor.disconnectExisting() }
            connectionNote.stringValue = "Paired directly · Remote Login is not needed"
            return
        }
        tunnel?.stop(); let tunnel = TunnelSupervisor(); self.tunnel = tunnel
        tunnel.onState = { [weak self] message in DispatchQueue.main.async {
            self?.connectionNote.stringValue = message.hasPrefix("Secure") ? "Paired with this Mac · reconnects automatically" : "Check the iMac’s power, network or sign-in screen."
        } }; tunnel.start()
    }
    func runAutomatedSetup() {
        legacyDisplaySetup()
        guard let controller = setupController else { return }
        controller.address.stringValue = LaunchOptions.value("--viewer-address") ?? ""
        controller.username.stringValue = LaunchOptions.value("--viewer-user") ?? ""
        controller.dedicated.state = LaunchOptions.has("--dedicated-display") ? .on : .off
        controller.onCompletion = { outcome in
            let report: [String:Any]
            switch outcome {
            case .success(let binding): report = ["success":true,"fileVault":binding.fileVault.rawValue,"fileVaultChanged":false,"automaticLoginChanged":binding.dedicatedDisplay && binding.automaticLoginConfigured,"startupAtLogin":binding.viewerStartup,"dedicatedDisplay":binding.dedicatedDisplay]
            case .failure(let error): report = ["success":false,"error":String(describing:error)]
            }
            if let path = LaunchOptions.value("--setup-report"), let data = try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys) { try? data.write(to:URL(fileURLWithPath:path),options:.atomic) }
        }
        controller.advance()
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
        let text = "RetinaLink Host \(LaunchOptions.version) (build \(LaunchOptions.build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)\nApp: \(Bundle.main.bundlePath)\nTransport: 0.2.2 baseline · default priority · whole-message I/O\nLegacy Screen Recording preflight: \(CGPreflightScreenCaptureAccess())\n\(profiles.titleOfSelectedItem ?? "")\n\(connectionLabel)\n\(status.stringValue)\nRecent one-second samples, oldest first:\n\(samples)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
    }
    @objc func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc func retryCapture() {
        guard waitingForPermission, !startingCapture, !stopping, let peer = link else { return }
        beginCapture(peer)
    }
    @objc func toggle() {
        if reconnectEnabled {
            displayPaused.toggle(); UserDefaults.standard.set(displayPaused,forKey:"displayPaused")
            if displayPaused { stop(message:"Display paused. Pairing is saved.") }
            else if let peer = link, helloReceived { peer.send(5,Data("resume".utf8)); beginCapture(peer) }
            else if listener == nil { start() }
            refreshHome()
        } else if listener != nil || link != nil { stop(reconnect:false) } else { start() }
    }
    func start() {
        guard !stopping, listener == nil else { return }
        guard DeviceSettings.binding == nil || trustedCredential != nil else {
            status.stringValue = "Device trust is unavailable. Finish Display Setup to restore this connection."
            // A locked/missing Keychain entry must never fall back to a weak
            // legacy code for a display that was already enrolled securely.
            refreshHome(); return
        }
        do {
            let listener = try NWListener(using:networkParameters(code),on:NWEndpoint.Port(rawValue:defaultPort)!)
            self.listener = listener; listener.service = NWListener.Service(name:Host.current().localizedName ?? "RetinaLink Host",type:serviceType,domain:nil,txtRecord:NativeConnectionSettings.record(hostID:DeviceSettings.hostID))
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready: self.status.stringValue = "Waiting for Viewer · \(self.connectionLabel)"; self.addresses.stringValue = localAddresses(); DiagnosticLog.shared.record("state", "Waiting for Viewer")
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
        // A preferred-route probe may authenticate while the current display
        // keeps streaming. It cannot claim the display without a valid Hello.
        guard listener != nil, !stopping, pending.count < 4 else { connection.cancel(); return }
        let peer = Link(connection), id = ObjectIdentifier(connection); pending[id] = peer
        peer.onReady = { [weak self,weak peer] in
            DispatchQueue.main.async {
                guard let self = self, let peer = peer else { return }
                guard self.pending[id] === peer, self.listener != nil, !self.stopping else { peer.cancel(); return }
                DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self,weak peer] in
                    guard let self = self, let peer = peer, self.pending[id] === peer else { return }; peer.cancel()
                }
            }
        }
        peer.onMessage = { [weak self,weak peer] type,data in
            DispatchQueue.main.async {
                guard let self = self, let peer = peer else { return }
                if self.pending[id] === peer {
                    guard self.link == nil, self.listener != nil, !self.stopping, type == 1, data.count < 4096,
                          let hello = try? JSONDecoder().decode(Hello.self,from:data),
                          hello.version == 1, hello.bc7, (try? hello.frameLimit()) != nil else {
                        peer.cancel(reason:"The Host already has a display connection, or the greeting was invalid."); return
                    }
                    self.pending.removeValue(forKey:id); self.link = peer; self.helloReceived = false
                    for other in self.pending.values { other.cancel() }; self.pending.removeAll()
                    self.status.stringValue = "\(self.connectionLabel) · \(peer.pathLabel)"
                }
                guard self.link === peer else { return }
                if type == 1, !self.helloReceived {
                    do {
                        guard data.count < 4096 else { throw LinkError.invalid("Invalid Viewer greeting") }
                        let hello = try JSONDecoder().decode(Hello.self,from:data)
                        guard hello.version == 1, hello.bc7 else { throw LinkError.invalid("Viewer does not support this protocol or GPU format") }
                        self.frameLimit = try hello.frameLimit(requested:Int(LaunchOptions.value("--frames-in-flight") ?? "3") ?? 3)
                        self.parallelPacking = hello.chunkedPacking == true && !LaunchOptions.has("--serial-packing")
                        self.helloReceived = true
                        self.viewerSupportsUpdates = hello.automaticUpdates == true
                        self.viewerSupportsRelay = hello.updateRelay == UpdateRelayPolicy.version
                        if self.viewerSupportsRelay, self.trustedCredential != nil {
                            let relay = HostUpdateRelay(peer:peer); self.viewerUpdateRelay = relay
                            relay.onProgress = { [weak self,weak relay] text in
                                guard let self = self, self.viewerUpdateRelay === relay else { return }
                                self.viewerUpdateNote.stringValue = "iMac: "+text
                            }
                            self.sendUpdateCommand(SoftwareUpdateCommand(action:"relay",relayVersion:UpdateRelayPolicy.version))
                        }
                        if hello.directConnection == true, self.trustedCredential != nil {
                            NativePendingSetup.complete()
                            let migrating = !NativeConnectionSettings.enabled
                            NativeConnectionSettings.enable(); self.tunnel?.stop(disconnect:true); self.tunnel = nil
                            if migrating { DispatchQueue.global(qos:.utility).async { TunnelSupervisor.disconnectExisting() } }
                            self.connectionNote.stringValue = "\(peer.pathLabel) · encrypted · network settings unchanged"
                            DiagnosticLog.shared.record("transport","Direct authenticated TLS; SSH display tunnel stopped; pairing unchanged")
                        }
                        self.viewerUpdateNote.stringValue = "iMac: RetinaLink \(hello.appVersion ?? "earlier release") · build \(hello.appBuild ?? "unknown")"
                        self.sendUpdateCommand(SoftwareUpdateCommand(action:"automatic",automatic:UpdateSettings.automatic))
                        if self.viewerUpdateRequested {
                            if let target = self.viewerUpdateTarget, let build = hello.appBuild,
                               let installed = Int(build), let expected = Int(target), installed >= expected {
                                self.viewerUpdateNote.stringValue = "iMac: installed \(hello.appVersion ?? "") (\(build)) · reconnecting display…"
                            } else { self.sendUpdateCommand(SoftwareUpdateCommand(action:"install")) }
                        }
                        if self.displayPaused { peer.send(5,Data("paused".utf8)); self.status.stringValue = "Display paused · securely paired" }
                        else { self.beginCapture(peer) }
                    } catch { self.stop(message:String(describing:error)) }
                } else if type == 7, self.helloReceived, self.trustedCredential != nil, data.count < 4096 {
                    if let status = try? JSONDecoder().decode(SoftwareUpdateStatus.self,from:data) {
                        self.observeViewerUpdate(status)
                    }
                } else if type == UpdateRelayPolicy.message, self.helloReceived, self.trustedCredential != nil, self.viewerSupportsRelay {
                    self.viewerUpdateRelay?.receive(data)
                } else if type == 9, self.helloReceived, self.forgettingNative,
                          String(data:data,encoding:.utf8) == DeviceSettings.binding?.hostID {
                    self.forgettingNative = false; self.reconnectEnabled = false
                    DeviceVault.remove(DeviceVault.credentialAccount); DeviceVault.remove(TunnelIdentity.account)
                    UserDefaults.standard.removeObject(forKey:DeviceSettings.bindingKey)
                    UserDefaults.standard.removeObject(forKey:"nativeConnectionEnabled.v1"); UserDefaults.standard.synchronize()
                    try? FileManager.default.removeItem(at:StartupAgent.path(role:"Host"))
                    self.trustedCredential = nil
                    self.stop(message:"Display forgotten. Install/open Viewer to approve a new Host.",reconnect:false)
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
                self.status.stringValue = "Streaming \(width) × \(height) · target \(fps) fps · \(peer.pathLabel)\n\(self.connectionLabel)"
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
    func stop(message: String = "Stopped. Your virtual display has been released.", reconnect: Bool = true) {
        DiagnosticLog.shared.record("state", message)
        guard !stopping else { return }; stopping = true; button?.isEnabled = false
        retryCaptureButton?.isEnabled = false
        startup?.cancel(); let startup = self.startup; self.startup = nil
        listener?.cancel(); listener = nil
        let peer = link; link = nil; peer?.cancel()
        viewerUpdateRelay?.stop(); viewerUpdateRelay = nil; viewerSupportsRelay = false
        for p in pending.values { p.cancel() }; pending.removeAll()
        Task { @MainActor [weak self] in
            await startup?.value
            guard let self = self else { return }
            if let capture = self.capture { await capture.stop() }; self.capture = nil
            self.status.stringValue = message; self.stats.stringValue = "No display is being captured."
            self.button?.title = "Start hosting"; self.button?.isEnabled = true; self.profiles.isEnabled = true; self.stopping = false
            self.startingCapture = false; self.waitingForPermission = false
            self.pairingMode.isEnabled = true; self.pairingModeChanged()
            self.refreshHome()
            if reconnect && self.reconnectEnabled && !self.quitting { DispatchQueue.main.asyncAfter(deadline:.now()+0.6) { [weak self] in self?.start() } }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { quitting = true; windowLifecycle?.stop(); homeTimer?.invalidate(); tunnel?.stop(); listener?.cancel(); link?.cancel(); startup?.cancel(); capture = nil }
}
#endif
