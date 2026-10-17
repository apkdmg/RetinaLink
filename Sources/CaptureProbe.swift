#if HOST
import Foundation
import CoreVideo

// Opt-in diagnostic only. No pixels or encoded payloads are saved/transmitted.
// Keep one stream and source alive while changing exactly which work consumes it.
final class CaptureProbe {
    enum Mode:String,CaseIterable {case capture,hold,source,snapshot,pack}
    let plan:[Mode], period:Double, hold:Double
    private var began:Double?, phase = -1
    private var snapshot:CVPixelBuffer?, fixedFrame:Frame?
    private var sequence:UInt64=0, processed=0, bytes=0
    private var workMS=0.0,gpuMS=0.0,packMS=0.0
    init(plan:String,period:Double=30,hold:Double=0.006) throws {
        let names=plan.split(separator:",").map(String.init)
        let modes=names.compactMap(Mode.init(rawValue:))
        guard !modes.isEmpty,modes.count==names.count,modes.count<=20,period.isFinite,(10...120).contains(period),hold.isFinite,(0...0.1).contains(hold) else {throw LinkError.invalid("Invalid capture probe plan")}
        self.plan=modes;self.period=period;self.hold=hold
    }
    func index(at elapsed:Double)->Int {min(plan.count-1,max(0,Int(elapsed/period)))}
    static func copy(_ image:CVPixelBuffer) throws -> CVPixelBuffer {
        let w=CVPixelBufferGetWidth(image),h=CVPixelBufferGetHeight(image)
        guard CVPixelBufferGetPixelFormatType(image)==kCVPixelFormatType_32BGRA else {throw LinkError.invalid("Probe expects BGRA")}
        var pixel:CVPixelBuffer?
        let attrs:[String:Any]=[kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
        guard CVPixelBufferCreate(nil,w,h,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&pixel)==kCVReturnSuccess,let pixel=pixel else {throw LinkError.invalid("Probe snapshot allocation failed")}
        guard CVPixelBufferLockBaseAddress(image,.readOnly)==kCVReturnSuccess else {throw LinkError.invalid("Probe input lock failed")}
        defer {CVPixelBufferUnlockBaseAddress(image,.readOnly)}
        guard CVPixelBufferLockBaseAddress(pixel,[])==kCVReturnSuccess else {throw LinkError.invalid("Probe snapshot lock failed")}
        defer {CVPixelBufferUnlockBaseAddress(pixel,[])}
        guard let src=CVPixelBufferGetBaseAddress(image),let dst=CVPixelBufferGetBaseAddress(pixel) else {throw LinkError.invalid("Missing snapshot pixels")}
        for row in 0..<h {memcpy(dst.advanced(by:row*CVPixelBufferGetBytesPerRow(pixel)),src.advanced(by:row*CVPixelBufferGetBytesPerRow(image)),w*4)}
        return pixel
    }
    func process(_ image:CVPixelBuffer,encoder:TextureEncoder,packer:FramePacker?,parallel:Bool) throws {
        let start=ProcessInfo.processInfo.systemUptime
        if began==nil {began=start}
        let current=index(at:start-began!)
        if phase != current {
            phase=current
            DiagnosticLog.shared.record("probe-phase","Phase \(current) · \(plan[current].rawValue) · elapsed \(start-began!) · period \(period) · no transmission")
        }
        let mode=plan[current]
        processed += 1
        if mode == .capture {return}
        if mode == .hold {Thread.sleep(forTimeInterval:hold);workMS += (ProcessInfo.processInfo.systemUptime-start)*1000;return}
        if snapshot==nil {snapshot=try Self.copy(image)}
        let frame:Frame
        if mode == .pack,let cached=fixedFrame {frame=cached}
        else {
            guard let encoded=try encoder.encode(mode == .source ? image:snapshot!,sequence:sequence+1,force:true) else {throw LinkError.invalid("Missing probe keyframe")}
            frame=encoded;gpuMS += encoder.lastGPUms
            if mode == .pack {fixedFrame=frame}
        }
        let packStart=ProcessInfo.processInfo.systemUptime
        let packet=try packer?.serialize(frame,parallel:parallel) ?? frame.serialize()
        sequence += 1;bytes += packet.count;packMS += (ProcessInfo.processInfo.systemUptime-packStart)*1000
        workMS += (ProcessInfo.processInfo.systemUptime-start)*1000
    }
    func report()->String {
        let n=Double(max(1,processed))
        let text=String(format:"Capture probe phase %d · %@ · processed %d · work %.3f ms · GPU %.3f ms · pack %.3f ms · bytes %d · no transmission",phase,phase<0 ? "waiting":plan[phase].rawValue,processed,workMS/n,gpuMS/n,packMS/n,bytes)
        processed=0;bytes=0;workMS=0;gpuMS=0;packMS=0
        return text
    }
}
#endif
