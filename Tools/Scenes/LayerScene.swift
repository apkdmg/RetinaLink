import AppKit
import QuartzCore
func opt(_ key:String,_ fallback:String)->String {
    guard let i=CommandLine.arguments.firstIndex(of:key),i+1<CommandLine.arguments.count else{return fallback};return CommandLine.arguments[i+1]
}
let seconds=Double(opt("--seconds","30")) ?? 30, scene=opt("--scene","window"), path=opt("--log","/tmp/retinalink-layer-scene.json")
final class Test: NSObject, NSApplicationDelegate {
    var window:NSWindow!, timer:Timer?, token:NSObjectProtocol?, start=0.0
    var displayLink:CADisplayLink?, displayTicks=0, lastDisplayTick=0.0, maxTickGap=0.0
    var samples:[[String:Any]]=[]
    func applicationDidFinishLaunching(_ n:Notification) {
        guard let screen=NSScreen.screens.first(where:{CGDisplayVendorNumber(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value)==0x5254}) else{exit(1)}
        window=NSWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.title="RetinaLink Compositor Test";window.isReleasedWhenClosed=false;window.level = .floating;window.collectionBehavior = [.canJoinAllSpaces]
        let view=NSView(frame:NSRect(origin:.zero,size:screen.frame.size));view.wantsLayer=true
        let root=view.layer!;root.backgroundColor=NSColor(calibratedRed:0.13,green:0.18,blue:0.24,alpha:1).cgColor
        let scroll=scene=="scroll", w=scroll ? 5120:2000, h=scroll ? 5760:1400
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        NSColor.white.setFill();NSRect(x:0,y:0,width:w,height:h).fill()
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:24),.foregroundColor:NSColor.darkGray]
        for y in stride(from:40,to:h-35,by:46) { for x in stride(from:35,to:w-600,by:640) {
            ("RetinaLink — native 5K motion test  \(y/46)" as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:attributes)
        } }
        NSColor.systemBlue.setFill();NSRect(x:0,y:h-60,width:w,height:60).fill()
        NSGraphicsContext.restoreGraphicsState()
        let card=CALayer();card.contents=bitmap.cgImage;card.contentsScale=2;card.bounds=CGRect(x:0,y:0,width:CGFloat(w)/2,height:CGFloat(h)/2)
        card.position=CGPoint(x:screen.frame.width/2,y:screen.frame.height/2);root.addSublayer(card)
        let animation=CABasicAnimation(keyPath:scroll ? "position.y":"position.x")
        animation.fromValue=scroll ? -600:550;animation.toValue=scroll ? 1300:2010
        animation.duration=4;animation.autoreverses=true;animation.repeatCount=Float.infinity;animation.timingFunction=CAMediaTimingFunction(name:.linear)
        if CommandLine.arguments.contains("--prefer-60") {
            animation.preferredFrameRateRange=CAFrameRateRange(minimum:60,maximum:60,preferred:60)
        }
        window.contentView=view;window.orderFrontRegardless();NSApp.activate(ignoringOtherApps:true)
        token=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Bounded Core Animation display benchmark")
        card.add(animation,forKey:"motion");start=ProcessInfo.processInfo.systemUptime
        if CommandLine.arguments.contains("--measure-display-link") {
            displayLink=view.displayLink(target:self,selector:#selector(displayTick(_:)))
            displayLink?.preferredFrameRateRange=CAFrameRateRange(minimum:60,maximum:60,preferred:60)
            displayLink?.add(to:.main,forMode:.common)
        }
        timer=Timer(timeInterval:1,repeats:true){[weak self] _ in self?.tick()};RunLoop.main.add(timer!,forMode:.common)
    }
    @objc func displayTick(_ link:CADisplayLink) {
        displayTicks += 1
        let now=ProcessInfo.processInfo.systemUptime
        if lastDisplayTick>0 { maxTickGap=max(maxTickGap,(now-lastDisplayTick)*1000) }
        lastDisplayTick=now
    }
    func tick() {
        let now=ProcessInfo.processInfo.systemUptime
        samples.append(["uptime":now,"elapsed":now-start,"width":5120,"height":2880,"displayLinkTicks":displayTicks,"maxTickGapMS":maxTickGap])
        displayTicks=0;maxTickGap=0
        let j:[String:Any]=["source":"CoreAnimation","scene":scene,"samples":samples,"explicit60HzHint":CommandLine.arguments.contains("--prefer-60")]
        if let data=try? JSONSerialization.data(withJSONObject:j,options:.sortedKeys){try? data.write(to:URL(fileURLWithPath:path),options:.atomic)}
        if now-start>=seconds {displayLink?.invalidate();timer?.invalidate();window.close();NSApp.terminate(nil)}
    }
}
let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=Test();app.delegate=delegate;app.run()
