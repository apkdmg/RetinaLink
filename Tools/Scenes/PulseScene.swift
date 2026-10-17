import AppKit
import MetalKit
import QuartzCore

func pulseOption(_ name:String,_ fallback:String)->String {
    guard let i=CommandLine.arguments.firstIndex(of:name),i+1<CommandLine.arguments.count else{return fallback};return CommandLine.arguments[i+1]
}
// Diagnostic compositor clock: a transparent 1-point Metal surface. It neither
// samples nor records other windows and never receives keyboard/mouse input.
final class TransparentView:MTKView {override var isOpaque:Bool {false}}
final class PulseScene:NSObject,NSApplicationDelegate,MTKViewDelegate {
    var window:NSWindow!,view:MTKView!,queue:MTLCommandQueue!,timer:Timer?,activity:NSObjectProtocol?
    var began=0.0,frames=0,samples:[[String:Any]]=[]
    func applicationDidFinishLaunching(_ n:Notification) {
        guard let screen=NSScreen.screens.first(where:{CGDisplayVendorNumber(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value)==0x5254}),let device=MTLCreateSystemDefaultDevice() else {exit(1)}
        window=NSWindow(contentRect:NSRect(x:screen.frame.minX+4,y:screen.frame.minY+4,width:1,height:1),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false
        window.ignoresMouseEvents=true;window.level=NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1);window.collectionBehavior=[.canJoinAllSpaces,.stationary]
        queue=device.makeCommandQueue();view=TransparentView(frame:NSRect(x:0,y:0,width:1,height:1),device:device)
        view.colorPixelFormat = .bgra8Unorm;view.clearColor=MTLClearColorMake(0,0,0,0);view.preferredFramesPerSecond=60
        view.autoResizeDrawable=true;view.enableSetNeedsDisplay=false;view.isPaused=false;view.delegate=self
        if let layer=view.layer as? CAMetalLayer {layer.isOpaque=false;layer.displaySyncEnabled=true;layer.framebufferOnly=true}
        window.contentView=view;window.orderFrontRegardless()
        activity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Bounded transparent compositor-clock diagnostic")
        began=ProcessInfo.processInfo.systemUptime
        timer=Timer(timeInterval:1,repeats:true){[weak self] _ in self?.report()};RunLoop.main.add(timer!,forMode:.common)
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    func draw(in view:MTKView) {autoreleasepool {
        guard let drawable=view.currentDrawable,let pass=view.currentRenderPassDescriptor,let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        encoder.endEncoding();command.present(drawable);command.commit();frames += 1
    }}
    func report() {
        let elapsed=ProcessInfo.processInfo.systemUptime-began
        samples.append(["uptime":ProcessInfo.processInfo.systemUptime,"elapsed":elapsed,"issuedFrames":frames,"layerOpaque":(view.layer?.isOpaque ?? true),"windowOpaque":window.isOpaque]);frames=0
        if let data=try? JSONSerialization.data(withJSONObject:["samples":samples]) {try? data.write(to:URL(fileURLWithPath:pulseOption("--log","/tmp/retinalink-pulse.json")),options:.atomic)}
        if elapsed >= (Double(pulseOption("--seconds","60")) ?? 60) {timer?.invalidate();view.isPaused=true;window.close();NSApp.terminate(nil)}
    }
}
let app=NSApplication.shared;app.setActivationPolicy(.accessory);let delegate=PulseScene();app.delegate=delegate;app.run()
