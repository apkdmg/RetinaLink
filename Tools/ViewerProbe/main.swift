import AppKit
import Metal

func option(_ name:String,_ fallback:String)->String {
    guard let i=CommandLine.arguments.firstIndex(of:name),i+1<CommandLine.arguments.count else{return fallback};return CommandLine.arguments[i+1]
}
func flatBlock(_ gray:UInt8)->Data {
    var bytes=Data(repeating:0,count:16),bit=0
    func put(_ v:UInt32,_ n:Int) {for i in 0..<n {bytes[bit/8] |= UInt8((v>>i)&1) << (bit%8);bit += 1}}
    let parity=UInt32(gray&1),q=UInt32(gray>>1)
    put(64,7);for _ in 0..<3 {put(q,7);put(q,7)};put(127,7);put(127,7);put(parity,1);put(parity,1)
    return bytes
}
func tile(_ id:Int,_ gray:UInt8)->TileUpdate {
    let d=Frame.dimensions(id,5120,2880),block=flatBlock(gray)
    var data=Data(count:d.w*d.h)
    data.withUnsafeMutableBytes {dst in block.withUnsafeBytes {src in
        for off in stride(from:0,to:dst.count,by:16) {memcpy(dst.baseAddress!.advanced(by:off),src.baseAddress!,16)}
    }}
    return TileUpdate(id:id,bytes:data)
}
func rawPacket(_ tiles:[TileUpdate],key:Bool)->Data {
    var raw=Data();raw.reserveCapacity(24+tiles.reduce(0){$0+$1.bytes.count+4})
    raw.put64(0);raw.put32(5120);raw.put32(2880);raw.put32(key ? 1:0);raw.put32(UInt32(tiles.count))
    for tile in tiles {raw.put32(UInt32(tile.id));raw.append(tile.bytes)}
    var packet=Data([0]);packet.reserveCapacity(9+raw.count);packet.put32(UInt32(raw.count));packet.put32(UInt32(raw.count));packet.append(raw);return packet
}
final class LocalProbe:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var window:NSWindow!,view:DisplayView!,activity:StreamingActivity?,timer:DispatchSourceTimer?,statsTimer:Timer?
    let queue=DispatchQueue(label:"retinalink.local-probe",qos:.userInteractive),credits=DispatchSemaphore(value:3),statistics=ViewerStatistics()
    let lock=NSLock()
    let period=Double(option("--period","30")) ?? 30
    var began=0.0,sequence:UInt64=0,attempts=0,skips=0,copies=0,copyMS=0.0,maxCopy=0.0,phase = -1
    var key=Data(),full:[Data]=[],sparse:[Data]=[]
    var plan:[String]=[],finished=false
    func applicationDidFinishLaunching(_ n:Notification) {
        do {
            plan=option("--plan","full,sparse,full").split(separator:",").map(String.init)
            guard period.isFinite,(10...60).contains(period),!plan.isEmpty,plan.count<=8,plan.allSatisfy({["full","sparse"].contains($0)}) else {throw LinkError.invalid("Invalid local probe plan")}
            var tiles=(0..<920).map {tile($0,($0/40)%2==0 ? 210:190)}
            key=rawPacket(tiles,key:true)
            for v in [UInt8(40),56] {tiles[0]=tile(0,v);full.append(rawPacket(tiles,key:false));sparse.append(rawPacket([tiles[0],tiles[919]],key:false))}
            let test=try Frame.parse(key);try check(test.tiles.count==920 && test.width==5120,"Probe packet failed round trip")
            view=try DisplayView(viewer:true)
            if LaunchOptions.has("--opaque-layer") {view.metalLayer.isOpaque=true}
            window=NSWindow(contentRect:NSRect(x:100,y:100,width:960,height:540),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
            window.title="RetinaLink local 5K presentation probe";window.isReleasedWhenClosed=false;window.contentView=view;window.collectionBehavior=[.fullScreenPrimary];window.delegate=self
            activity=StreamingActivity()
            view.onFrame={[weak self] t in guard let self=self else{return};self.statistics.completed(t);self.credits.signal()}
            view.onPresentation={[weak self] w,h,t in self?.statistics.presented(width:w,height:h,time:t)}
            view.onActualPresent={[weak self] in self?.statistics.actualPresentCall($0)}
            view.onError={[weak self] text in self?.fail(text)}
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);window.toggleFullScreen(nil)
            DiagnosticLog.shared.record("local-probe","Prepared full 5K uncompressed packets; no capture, network or LZ4 decode")
        } catch {fail(String(describing:error))}
    }
    func windowDidEnterFullScreen(_ n:Notification) {
        guard began==0 else{return};began=ProcessInfo.processInfo.systemUptime
        if LaunchOptions.has("--opaque-layer") {view.metalLayer.isOpaque=true}
        DiagnosticLog.shared.record("probe-config","Drawable \(view.metalLayer.drawableSize); layer opaque \(view.metalLayer.isOpaque); window opaque \(window.isOpaque); GPU \(view.device.name); coalesced uploads \(view.uploader.coalesced); write-combined \(view.uploader.writeCombined)")
        let timer=DispatchSource.makeTimerSource(queue:queue);timer.schedule(deadline:.now(),repeating:.nanoseconds(16_666_667),leeway:.microseconds(100));timer.setEventHandler {[weak self] in self?.tick()};self.timer=timer;timer.resume()
        statsTimer=Timer(timeInterval:1,repeats:true){[weak self] _ in self?.report()};RunLoop.main.add(statsTimer!,forMode:.common)
    }
    func tick() {
        let now=ProcessInfo.processInfo.systemUptime
        let index=min(plan.count-1,Int((now-began)/period))
        if index != phase {phase=index;DiagnosticLog.shared.record("probe-phase","Local phase \(index) · \(plan[index])")}
        lock.lock();attempts += 1;lock.unlock()
        guard credits.wait(timeout:.now()) == .success else {lock.lock();skips += 1;lock.unlock();return}
        let start=ProcessInfo.processInfo.systemUptime
        var packet=sequence==0 ? key:(plan[index]=="full" ? full[Int(sequence&1)]:sparse[Int(sequence&1)])
        sequence += 1;var seq=sequence.bigEndian
        packet.withUnsafeMutableBytes {dst in withUnsafeBytes(of:&seq) {src in memcpy(dst.baseAddress!.advanced(by:9),src.baseAddress!,8)}}
        let cost=(ProcessInfo.processInfo.systemUptime-start)*1000
        lock.lock();copies += 1;copyMS += cost;maxCopy=max(maxCopy,cost);lock.unlock()
        statistics.received(packet.count);view.receive(packet)
    }
    func report() {
        lock.lock();let info=String(format:"Local producer attempts %d · credit skips %d · packet copy %.3f ms · max %.3f ms",attempts,skips,copyMS/Double(max(1,copies)),maxCopy);attempts=0;skips=0;copies=0;copyMS=0;maxCopy=0;lock.unlock()
        let screen=window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let asleep=screen.map {CGDisplayIsAsleep($0.uint32Value) != 0} ?? true
        let visibility="Window visible \(window.isVisible); occlusion visible \(window.occlusionState.contains(.visible)); active Space \(window.isOnActiveSpace); display asleep \(asleep)"
        DiagnosticLog.shared.record("viewer",statistics.report()+"\n"+info+"\n"+visibility)
        if ProcessInfo.processInfo.systemUptime-began >= period*Double(plan.count) {
            timer?.cancel();statsTimer?.invalidate();finished=true
            DiagnosticLog.shared.record("probe-done","Local probe complete")
            DispatchQueue.main.asyncAfter(deadline:.now()+1) {NSApp.terminate(nil)}
        }
    }
    func fail(_ text:String) {DiagnosticLog.shared.record("probe-error",text);DispatchQueue.main.asyncAfter(deadline:.now()+1){NSApp.terminate(nil)}}
}
if LaunchOptions.has("--self-test") {do {try runSelfTests();exit(0)} catch {fputs("FAIL: \(error)\n",stderr);exit(1)}}
let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=LocalProbe();app.delegate=delegate;app.run()
