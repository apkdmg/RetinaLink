import AppKit
import MetalKit
import QuartzCore

func option(_ name: String, _ fallback: String) -> String {
    guard let i = CommandLine.arguments.firstIndex(of:name), i+1 < CommandLine.arguments.count else { return fallback }
    return CommandLine.arguments[i+1]
}
let logPath = option("--log", "/tmp/retinalink-gpu-scene.json")
let duration = Double(option("--seconds", "30")) ?? 30
let mode = option("--scene", "window")

let metalSource = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; float2 uv; };
vertex V sceneVertex(uint id [[vertex_id]]) {
    float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
    V v; v.position=float4(p[id],0,1); v.uv=float2((p[id].x+1)/2,(1-p[id].y)/2); return v;
}
struct P { uint frame; uint mode; float width; float height; };
fragment float4 sceneFragment(V in [[stage_in]], constant P &p [[buffer(0)]]) {
    float2 xy=in.uv*float2(p.width,p.height); float2 q=xy;
    float3 color=float3(.13,.18,.24);
    if(p.mode==0) {
        float2 origin=float2(1400+850*sin(float(p.frame)/55),700+350*cos(float(p.frame)/77));
        q=xy-origin;
        if(q.x<0 || q.y<0 || q.x>2000 || q.y>1400) return float4(color,1);
    } else if(p.mode==1) { q.y+=float(p.frame)*5; }
    else if(p.mode==2) {
        q.x+=float(p.frame)*7;
        color=.5+.25*sin(float3(q.x*.017,q.y*.019,(q.x+q.y)*.011))+.15*cos(float3(q.y*.12,q.x*.07,(q.x-q.y)*.051));
        return float4(color,1);
    }
    color=float3(.96,.97,.98);
    float column=fmod(q.x,640.0), line=fmod(q.y,48.0);
    if(column>35 && column<580 && line>15 && line<30 && fmod(column,30.0)<22) color=float3(.17,.19,.22);
    if(fmod(q.y,480.0)<8) color=float3(.1,.4,.7);
    if(fmod(q.x,640.0)<12) color=float3(.78,.84,.91);
    // The marker changes each generated frame, including a fixed-position page.
    if(xy.y<24 && xy.x<384) color=((p.frame>>uint(xy.x/24))&1) ? float3(1):float3(0);
    return float4(color,1);
}
"""

final class Scene: NSObject, NSApplicationDelegate, MTKViewDelegate {
    var window: NSWindow!, view: MTKView!, queue: MTLCommandQueue!, pipeline: MTLRenderPipelineState!
    var activity: NSObjectProtocol?, timer: Timer?
    var start=0.0, previous=0.0, frame: UInt32=0
    let lock=NSLock(); var drawn=0, presented=0, totalPresented=0
    var frameRecords:[[String:Any]]=[]
    var lastDraw=0.0
    let traceFrames=CommandLine.arguments.contains("--frame-trace")
    let presentationPlan=option("--presentation-plan","native").split(separator:",").map(String.init)
    let phasePeriod=max(10,Double(option("--presentation-period","20")) ?? 20)
    var phaseName="native",phaseIndex = -1
    var records: [[String:Any]]=[]
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !presentationPlan.isEmpty,presentationPlan.count<=10,presentationPlan.allSatisfy({["native","no-counter","unsynced"].contains($0)}) else {fputs("Invalid presentation plan\n",stderr);exit(1)}
        guard let screen=NSScreen.screens.first(where:{
            let id=($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
            return CGDisplayVendorNumber(id)==0x5254
        }),let device=MTLCreateSystemDefaultDevice() else { fputs("No RetinaLink display or Metal GPU\n",stderr); exit(1) }
        queue=device.makeCommandQueue()
        do {
            let lib=try device.makeLibrary(source:metalSource,options:nil), d=MTLRenderPipelineDescriptor()
            d.vertexFunction=lib.makeFunction(name:"sceneVertex"); d.fragmentFunction=lib.makeFunction(name:"sceneFragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline=try device.makeRenderPipelineState(descriptor:d)
        } catch { fputs("\(error)\n",stderr); exit(1) }
        window=NSWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.title="RetinaLink GPU Motion Test"; window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces]; window.isReleasedWhenClosed=false
        view=MTKView(frame:NSRect(origin:.zero,size:screen.frame.size),device:device)
        view.colorPixelFormat = .bgra8Unorm; view.preferredFramesPerSecond=60; view.delegate=self
        view.autoResizeDrawable=true; view.enableSetNeedsDisplay=false; view.isPaused=false
        if let layer=view.layer as? CAMetalLayer { layer.maximumDrawableCount=3; layer.displaySyncEnabled=true }
        window.contentView=view; window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps:true)
        activity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Bounded display performance test")
        start=ProcessInfo.processInfo.systemUptime; previous=start
        timer=Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.report() }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        autoreleasepool {
            let entered=ProcessInfo.processInfo.systemUptime
            let index=min(presentationPlan.count-1,Int(max(0,entered-start)/phasePeriod))
            if index != phaseIndex {
                phaseIndex=index;phaseName=presentationPlan[index]
                (view.layer as? CAMetalLayer)?.displaySyncEnabled=phaseName != "unsynced"
            }
            let gap=lastDraw==0 ? 0:(entered-lastDraw)*1000;lastDraw=entered
            guard let drawable=view.currentDrawable,let pass=view.currentRenderPassDescriptor,
                  let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { return }
            let acquired=ProcessInfo.processInfo.systemUptime
            frame += 1
            struct Params { var frame, mode: UInt32; var width,height: Float }
            var p=Params(frame:frame,mode:mode=="window" ? 0 : (mode=="scroll" ? 1:(mode=="marker" ? 3:2)),width:Float(drawable.texture.width),height:Float(drawable.texture.height))
            encoder.setRenderPipelineState(pipeline); encoder.setFragmentBytes(&p,length:MemoryLayout<Params>.size,index:0)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); encoder.endEncoding()
            lock.lock(); drawn += 1; lock.unlock()
            if phaseName != "no-counter" {
                drawable.addPresentedHandler { [weak self] drawable in
                    guard let self=self, drawable.presentedTime>0 else {return}
                    self.lock.lock(); self.presented += 1; self.totalPresented += 1; self.lock.unlock()
                }
            }
            let encoded=ProcessInfo.processInfo.systemUptime,identity=frame,active=NSApp.isActive,visible=window.occlusionState.contains(.visible)
            if traceFrames {
                command.addCompletedHandler {[weak self] command in
                    guard let self=self else{return}
                    let row:[String:Any]=["frame":identity,"draw":entered,"draw_gap_ms":gap,"drawable_ms":(acquired-entered)*1000,"encode_ms":(encoded-acquired)*1000,"gpu_start":command.gpuStartTime,"gpu_end":command.gpuEndTime,"completed":ProcessInfo.processInfo.systemUptime,"active":active,"visible":visible]
                    self.lock.lock();if self.frameRecords.count<15000 {self.frameRecords.append(row)};self.lock.unlock()
                }
            }
            command.present(drawable); command.commit()
        }
    }
    func report() {
        let now=ProcessInfo.processInfo.systemUptime, dt=now-previous
        lock.lock(); let d=drawn, p=presented, total=totalPresented,frames=frameRecords; drawn=0; presented=0; lock.unlock()
        records.append(["uptime":now,"elapsed":now-start,"drawnFPS":Double(d)/dt,"presentedFPS":Double(p)/dt,
                        "totalPresented":total,"width":view.drawableSize.width,"height":view.drawableSize.height,"active":NSApp.isActive,"visible":window.occlusionState.contains(.visible),"phase":phaseName,"phaseIndex":phaseIndex])
        let result:[String:Any]=["scene":mode,"samples":records,"frames":frames]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:logPath),options:.atomic) }
        previous=now
        if now-start>=duration { timer?.invalidate(); view.isPaused=true; window.close(); NSApp.terminate(nil) }
    }
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=Scene(); app.delegate=delegate; app.run()
