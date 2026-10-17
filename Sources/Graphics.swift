import AppKit
import Metal
import QuartzCore
import CoreVideo

func shaderLibrary(_ device: MTLDevice, baseline: Bool = LaunchOptions.has("--baseline-encoder"), tileMajor: Bool = !LaunchOptions.has("--row-major-encoder"), atomicStore: Bool = !LaunchOptions.has("--baseline-dirty-atomic")) throws -> MTLLibrary {
    let url = Bundle.main.url(forResource: "Shaders", withExtension: "metal") ?? URL(fileURLWithPath: "Resources/Shaders.metal")
    let source = try String(contentsOf: url)
    let options = MTLCompileOptions(); options.languageVersion = .version2_2
    options.preprocessorMacros = ["BASELINE_ENCODER": NSNumber(value:baseline),"TILE_MAJOR_ENCODER": NSNumber(value:tileMajor),"STORE_DIRTY_FLAG":NSNumber(value:atomicStore)]
    return try device.makeLibrary(source: source, options: options)
}
func supportsBC(_ device: MTLDevice) -> Bool {
    if #available(macOS 11.0, *) { return device.supportsBCTextureCompression }
    return device.supportsFeatureSet(.macOS_GPUFamily1_v1)
}

#if HOST
struct EncodeParams { var width, height, columns, force: UInt32 }
final class TextureEncoder {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let queue: MTLCommandQueue
    var cache: CVMetalTextureCache!
    var buffers: [MTLBuffer] = []
    var dirty: MTLBuffer?
    var width = 0, height = 0, current = 0
    let tileMajor: Bool
    private(set) var lastGPUms = 0.0, lastWaitMS = 0.0, lastGatherMS = 0.0
    init(baseline: Bool = LaunchOptions.has("--baseline-encoder"), tileMajor: Bool = !LaunchOptions.has("--row-major-encoder"), atomicStore: Bool = !LaunchOptions.has("--baseline-dirty-atomic")) throws {
        self.tileMajor = tileMajor
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { throw LinkError.invalid("Metal GPU unavailable") }
        device = d; queue = q
        guard let function = try shaderLibrary(d,baseline:baseline,tileMajor:tileMajor,atomicStore:atomicStore).makeFunction(name: "encodeBC7") else { throw LinkError.invalid("Compression shader missing") }
        pipeline = try d.makeComputePipelineState(function: function)
        guard CVMetalTextureCacheCreate(nil,nil,d,nil,&cache) == kCVReturnSuccess else { throw LinkError.invalid("Could not create GPU texture cache") }
    }
    func encode(_ pixel: CVPixelBuffer, sequence: UInt64, force: Bool) throws -> Frame? {
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        guard Frame.supported(w,h) else { throw LinkError.invalid("Capture returned \(w)×\(h); refusing to label an upscaled image as 5K") }
        let columns = (w+127)/128, rows = (h+127)/128
        var keyframe = force
        if w != width || h != height {
            width = w; height = h; current = 0; buffers = []
            for _ in 0..<2 {
                guard let b = device.makeBuffer(length: w*h, options: .storageModeShared) else { throw LinkError.invalid("GPU buffer allocation failed") }
                memset(b.contents(),0,w*h); buffers.append(b)
            }
            dirty = device.makeBuffer(length: columns*rows*4, options: .storageModeShared)
            keyframe = true
        }
        guard let dirty = dirty else { throw LinkError.invalid("GPU dirty-map allocation failed") }
        memset(dirty.contents(),0,dirty.length)
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(nil,cache,pixel,nil,.bgra8Unorm,w,h,0,&cvTexture)
        guard result == kCVReturnSuccess, let wrapped = cvTexture, let texture = CVMetalTextureGetTexture(wrapped),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw LinkError.invalid("Could not access capture GPU surface") }
        encoder.setComputePipelineState(pipeline); encoder.setTexture(texture,index:0)
        encoder.setBuffer(buffers[current],offset:0,index:0); encoder.setBuffer(buffers[1-current],offset:0,index:1)
        encoder.setBuffer(dirty,offset:0,index:2)
        var p = EncodeParams(width: UInt32(w),height:UInt32(h),columns:UInt32(columns),force:keyframe ? 1 : 0)
        encoder.setBytes(&p,length:MemoryLayout<EncodeParams>.size,index:3)
        encoder.dispatchThreads(MTLSize(width:w/4,height:h/4,depth:1),threadsPerThreadgroup:MTLSize(width:8,height:8,depth:1))
        encoder.endEncoding()
        let submit = ProcessInfo.processInfo.systemUptime
        command.commit(); command.waitUntilCompleted()
        lastWaitMS = (ProcessInfo.processInfo.systemUptime-submit)*1000
        lastGPUms = max(0,command.gpuEndTime-command.gpuStartTime)*1000
        if let error = command.error { throw error }
        let gatherStart = ProcessInfo.processInfo.systemUptime
        let flags = dirty.contents().bindMemory(to: UInt32.self,capacity:columns*rows)
        let base = buffers[current].contents().bindMemory(to: UInt8.self,capacity:w*h)
        var tiles: [TileUpdate] = []
        for id in 0..<(columns*rows) where flags[id] != 0 {
            let d = Frame.dimensions(id,w,h)
            let data: Data
            if tileMajor {
                data = Data(bytes:base.advanced(by:d.y*w+d.x*d.h),count:d.w*d.h)
            } else {
                var gathered = Data(capacity:d.w*d.h)
                for row in 0..<(d.h/4) {
                    let offset = (d.y/4+row)*w*4+d.x*4
                    gathered.append(base.advanced(by:offset),count:d.w*4)
                }
                data = gathered
            }
            tiles.append(TileUpdate(id:id,bytes:data))
        }
        current = 1-current
        lastGatherMS = (ProcessInfo.processInfo.systemUptime-gatherStart)*1000
        guard !tiles.isEmpty else { return nil }
        return Frame(sequence:sequence,width:w,height:h,keyframe:keyframe,tiles:tiles)
    }
}
#endif

// All texture writes and draws use the same command queue. A frame's staging
// buffer is returned only after its GPU work completes, never while it is in use.
final class TextureUploader {
    let device: MTLDevice
    let coalesced: Bool
    let writeCombined:Bool
    private(set) var lastBlitCount=0
    private(set) var texture: MTLTexture?
    private var lastSequence: UInt64 = 0
    private let poolLock = NSLock()
    private var available: [MTLBuffer] = []
    init(device: MTLDevice, coalesced: Bool = !LaunchOptions.has("--tile-blits"),writeCombined:Bool = !LaunchOptions.has("--cached-upload")) { self.device = device;self.coalesced=coalesced;self.writeCombined=writeCombined }
    func encode(_ frame: Frame, into command: MTLCommandBuffer) throws -> MTLTexture {
        guard frame.sequence == lastSequence+1 else { throw LinkError.invalid("Frame sequence mismatch") }
        if texture == nil || texture?.width != frame.width || texture?.height != frame.height {
            guard frame.keyframe else { throw LinkError.invalid("A complete first frame is required") }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bc7_rgbaUnorm_srgb,width:frame.width,height:frame.height,mipmapped:false)
            descriptor.usage = .shaderRead; descriptor.storageMode = .private
            texture = device.makeTexture(descriptor:descriptor)
        }
        guard let texture = texture else { throw LinkError.invalid("5K texture allocation failed") }
        let length = frame.tiles.reduce(0) { $0 + $1.bytes.count }
        lastBlitCount=0
        if length > 0 {
            poolLock.lock(); let reused = available.popLast(); poolLock.unlock()
            let options:MTLResourceOptions=writeCombined ? [.storageModeShared,.cpuCacheModeWriteCombined]:.storageModeShared
            guard let staging = (reused != nil && reused!.length >= length ? reused : device.makeBuffer(length:frame.width*frame.height,options:options)),
                  let blit = command.makeBlitCommandEncoder() else { throw LinkError.invalid("Texture upload allocation failed") }
            var tiles=frame.tiles
            if coalesced && zip(tiles,tiles.dropFirst()).contains(where:{$0.id>$1.id}) {tiles.sort {$0.id<$1.id}}
            var offset=0,index=0
            let columns=(frame.width+127)/128
            let destination=staging.contents()
            while index<tiles.count {
                let first=Frame.dimensions(tiles[index].id,frame.width,frame.height)
                var end=index+1,runWidth=first.w
                if coalesced {
                    while end<tiles.count && tiles[end].id==tiles[end-1].id+1 && tiles[end].id/columns==tiles[index].id/columns {
                        runWidth += Frame.dimensions(tiles[end].id,frame.width,frame.height).w;end += 1
                    }
                }
                let stride=runWidth*4,runBytes=runWidth*first.h
                if end==index+1 {
                    tiles[index].bytes.withUnsafeBytes {_ = memcpy(destination.advanced(by:offset),$0.baseAddress!,runBytes)}
                } else {
                    // Repack adjacent BC7 block rows into one rectangular upload.
                    // Never bridge an unchanged tile or a tile-row boundary.
                    var x=0
                    for i in index..<end {
                        let tile=tiles[i],rowBytes=Frame.dimensions(tile.id,frame.width,frame.height).w*4
                        tile.bytes.withUnsafeBytes { bytes in
                            for row in 0..<(first.h/4) {
                                memcpy(destination.advanced(by:offset+row*stride+x),bytes.baseAddress!.advanced(by:row*rowBytes),rowBytes)
                            }
                        }
                        x += rowBytes
                    }
                }
                blit.copy(from:staging,sourceOffset:offset,sourceBytesPerRow:stride,sourceBytesPerImage:runBytes,
                          sourceSize:MTLSize(width:runWidth,height:first.h,depth:1),to:texture,destinationSlice:0,destinationLevel:0,
                          destinationOrigin:MTLOrigin(x:first.x,y:first.y,z:0))
                lastBlitCount += 1;offset += runBytes;index=end
            }
            blit.endEncoding()
            command.addCompletedHandler { [weak self,staging] _ in
                guard let self = self else { return }
                self.poolLock.lock(); defer { self.poolLock.unlock() }
                if self.available.count < 3 { self.available.append(staging) }
            }
        }
        lastSequence = frame.sequence
        return texture
    }
}

final class DisplayView: NSView {
    let traceID=UUID().uuidString
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let renderQueue = DispatchQueue(label:"retinalink.render",qos:.userInteractive)
    let uploader: TextureUploader
    private let surface = CAMetalLayer()
    private let redrawLock = NSLock()
    private var redrawPending = false
    var onFrame: ((RenderTiming) -> Void)?
    var onPresentation: ((Int, Int, Double) -> Void)?
    var onActualPresent: ((Double) -> Void)?
    var onError: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override func makeBackingLayer() -> CALayer { surface }
    var metalLayer: CAMetalLayer { surface }
    init(viewer: Bool) throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { throw LinkError.invalid("Metal GPU unavailable") }
        guard supportsBC(d) else { throw LinkError.invalid("This GPU/driver does not report BC texture support") }
        device = d; commandQueue = q; uploader = TextureUploader(device:d)
        let library = try shaderLibrary(d), descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name:"screenVertex")
        descriptor.fragmentFunction = library.makeFunction(name:"screenFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeline = try d.makeRenderPipelineState(descriptor:descriptor)
        super.init(frame:NSRect(x:0,y:0,width:960,height:540))
        wantsLayer = true; metalLayer.device = d; metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.colorspace = CGColorSpace(name:CGColorSpace.sRGB); metalLayer.framebufferOnly = true
        metalLayer.displaySyncEnabled = true; metalLayer.maximumDrawableCount = LaunchOptions.has("--two-drawables") ? 2 : 3
        metalLayer.backgroundColor = NSColor.black.cgColor
        updateDrawableSize()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDrawableSize() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawableSize() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateDrawableSize() }
    private func updateDrawableSize() {
        guard let layer = layer as? CAMetalLayer else { return }
        let scale = window?.backingScaleFactor ?? 2
        layer.contentsScale = scale; layer.drawableSize = CGSize(width:max(1,bounds.width*scale),height:max(1,bounds.height*scale))
        // A static desktop still needs redrawing after entering full screen or resizing.
        redrawLock.lock()
        if redrawPending { redrawLock.unlock(); return }
        redrawPending = true; redrawLock.unlock()
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            self.redrawLock.lock(); self.redrawPending = false; self.redrawLock.unlock()
            guard let texture = self.uploader.texture, let command = self.commandQueue.makeCommandBuffer(),
                  let drawable = self.surface.nextDrawable() else { return }
            do { try self.draw(texture,into:command,drawable:drawable); self.present(drawable,on:command,sequence:0); command.commit() }
            catch { self.onError?(String(describing:error)) }
        }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        else { super.keyDown(with:event) }
    }
    func receive(_ data: Data) {
        let arrival = ProcessInfo.processInfo.systemUptime
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            autoreleasepool { do {
                let start = ProcessInfo.processInfo.systemUptime
                let frame = try Frame.parse(data)
                FrameTrace.shared.event("decoded",sequence:frame.sequence,fields:["view":self.traceID,"arrival":arrival,"render_start":start])
                let unpacked = ProcessInfo.processInfo.systemUptime
                guard let command = self.commandQueue.makeCommandBuffer() else { throw LinkError.invalid("GPU command allocation failed") }
                let texture = try self.uploader.encode(frame,into:command)
                let uploaded = ProcessInfo.processInfo.systemUptime
                guard let drawable = self.surface.nextDrawable() else { throw LinkError.invalid("Display is unavailable; keep the viewer window visible") }
                let acquired = ProcessInfo.processInfo.systemUptime
                try self.draw(texture,into:command,drawable:drawable)
                let dw = drawable.texture.width, dh = drawable.texture.height
                // Upload has copied all tile bytes into GPU-owned staging. Keep
                // only identity in callbacks, not an entire decoded 5K frame.
                let sequence=frame.sequence, width=frame.width, height=frame.height
                if #available(macOS 10.15.4, *) {
                    drawable.addPresentedHandler { [weak self] drawable in
                        FrameTrace.shared.event("presented",sequence:sequence,fields:["view":self?.traceID ?? "closed","presented_time":drawable.presentedTime])
                        self?.onPresentation?(dw, dh, drawable.presentedTime)
                    }
                }
                let beforePresent=ProcessInfo.processInfo.systemUptime
                FrameTrace.shared.event("present_begin",sequence:sequence,fields:["view":self.traceID])
                self.present(drawable,on:command,sequence:sequence)
                let submitted=ProcessInfo.processInfo.systemUptime
                command.addCompletedHandler { [weak self] command in
                    let completed=ProcessInfo.processInfo.systemUptime
                    FrameTrace.shared.event("gpu_callback",sequence:sequence,fields:["view":self?.traceID ?? "closed","gpu_start":command.gpuStartTime,"gpu_end":command.gpuEndTime])
                    guard let self = self else { return }
                    if let error = command.error { self.onError?(String(describing:error)); return }
                    let timing = RenderTiming(sequence:sequence,width:width,height:height,
                        queueMS:(start-arrival)*1000,unpackMS:(unpacked-start)*1000,uploadMS:(uploaded-unpacked)*1000,
                        drawableMS:(acquired-uploaded)*1000,gpuMS:max(0,command.gpuEndTime-command.gpuStartTime)*1000,
                        totalMS:(completed-arrival)*1000,submissionMS:max(0,command.gpuStartTime-submitted)*1000,
                        callbackMS:max(0,completed-command.gpuEndTime)*1000,presentMS:(submitted-beforePresent)*1000)
                    self.onFrame?(timing)
                }
                FrameTrace.shared.event("gpu_commit",sequence:sequence,fields:["view":self.traceID,"uploaded":uploaded,"acquired":acquired,"blits":self.uploader.lastBlitCount])
                command.commit()
                FrameTrace.shared.event("commit_return",sequence:sequence,fields:["view":self.traceID])
            } catch { self.onError?(String(describing:error)) } }
        }
    }
    private func present(_ drawable: CAMetalDrawable, on command: MTLCommandBuffer, sequence: UInt64) {
        guard LaunchOptions.has("--trace-actual-present") else {command.present(drawable);return}
        // Match Metal's convenience method: present the drawable after scheduling,
        // without waiting for completion. Time the deferred handoff itself.
        command.addScheduledHandler { [weak self] _ in
            let began=ProcessInfo.processInfo.systemUptime
            FrameTrace.shared.event("drawable_present_begin",sequence:sequence,fields:["view":self?.traceID ?? "closed"])
            drawable.present()
            let ms=(ProcessInfo.processInfo.systemUptime-began)*1000
            FrameTrace.shared.event("drawable_present_end",sequence:sequence,fields:["view":self?.traceID ?? "closed","duration_ms":ms])
            self?.onActualPresent?(ms)
        }
    }
    private func draw(_ texture: MTLTexture, into command: MTLCommandBuffer, drawable: CAMetalDrawable) throws {
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor:pass) else { throw LinkError.invalid("Could not create render pass") }
        let dw = Double(drawable.texture.width), dh = Double(drawable.texture.height)
        let scale = min(dw/Double(texture.width),dh/Double(texture.height))
        let w = Double(texture.width)*scale, h = Double(texture.height)*scale
        encoder.setViewport(MTLViewport(originX:(dw-w)/2,originY:(dh-h)/2,width:w,height:h,znear:0,zfar:1))
        encoder.setRenderPipelineState(pipeline); encoder.setFragmentTexture(texture,index:0)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); encoder.endEncoding()
    }
}
