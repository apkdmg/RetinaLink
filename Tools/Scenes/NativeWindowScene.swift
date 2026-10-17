import AppKit
import QuartzCore
func option(_ key:String,_ fallback:String)->String {
    guard let i=CommandLine.arguments.firstIndex(of:key),i+1<CommandLine.arguments.count else{return fallback};return CommandLine.arguments[i+1]
}
let seconds=Double(option("--seconds","90")) ?? 90
let path=option("--log","/tmp/retinalink-native-window.json")
final class NativeWindowScene:NSObject,NSApplicationDelegate {
    var window:NSWindow!, screen:NSScreen!, link:CADisplayLink?, timer:Timer?, activity:NSObjectProtocol?
    var began=0.0, previous=0.0, updates=0, samples:[[String:Any]]=[]
    func applicationDidFinishLaunching(_ notification:Notification) {
        guard let target=NSScreen.screens.first(where:{CGDisplayVendorNumber(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value)==0x5254}) else{exit(1)}
        screen=target
        window=NSWindow(contentRect:NSRect(x:target.frame.minX+500,y:target.frame.minY+350,width:1000,height:700),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="RetinaLink Native Window Test";window.isReleasedWhenClosed=false;window.level = .floating
        let view=NSView(frame:NSRect(x:0,y:0,width:1000,height:700));view.wantsLayer=true
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2000,pixelsHigh:1400,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        NSColor.white.setFill();NSRect(x:0,y:0,width:2000,height:1400).fill()
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:26),.foregroundColor:NSColor.darkGray]
        for y in stride(from:50,to:1350,by:48) {for x in stride(from:40,to:1500,by:650) {
            ("Native window motion — line \(y/48)" as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:attributes)
        }}
        NSColor.systemBlue.setFill();NSRect(x:0,y:1340,width:2000,height:60).fill()
        NSGraphicsContext.restoreGraphicsState()
        view.layer!.contents=bitmap.cgImage;view.layer!.contentsScale=2
        window.contentView=view;window.orderFrontRegardless();NSApp.activate(ignoringOtherApps:true)
        activity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Bounded native window motion benchmark")
        began=ProcessInfo.processInfo.systemUptime;previous=began
        link=view.displayLink(target:self,selector:#selector(moveWindow(_:)))
        link!.preferredFrameRateRange=CAFrameRateRange(minimum:60,maximum:60,preferred:60);link!.add(to:.main,forMode:.common)
        timer=Timer(timeInterval:1,repeats:true){[weak self] _ in self?.report()};RunLoop.main.add(timer!,forMode:.common)
    }
    @objc func moveWindow(_ link:CADisplayLink) {
        let t=ProcessInfo.processInfo.systemUptime-began
        window.setFrameOrigin(NSPoint(x:screen.frame.minX+750+550*sin(t*0.9),y:screen.frame.minY+350+200*cos(t*0.7)))
        updates += 1
    }
    func report() {
        let now=ProcessInfo.processInfo.systemUptime
        samples.append(["elapsed":now-began,"uptime":now,"issuedWindowUpdatesFPS":Double(updates)/max(0.001,now-previous)])
        updates=0;previous=now
        let result:[String:Any]=["source":"AppKit native window positions","samples":samples,"streamWidth":5120,"streamHeight":2880]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:.sortedKeys){try?data.write(to:URL(fileURLWithPath:path),options:.atomic)}
        if now-began>=seconds {link?.invalidate();timer?.invalidate();window.close();NSApp.terminate(nil)}
    }
}
let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=NativeWindowScene();app.delegate=delegate;app.run()
