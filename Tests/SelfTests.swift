import Foundation
import AppKit
import Network
import Metal
import CoreVideo

func check(_ condition: @autoclosure () throws -> Bool, _ reason: String) throws {
    if try !condition() { throw LinkError.invalid(reason) }
}
func expectInvalid(_ block: () throws -> Void) throws {
    do { try block() } catch { return }
    throw LinkError.invalid("Malformed input was accepted")
}
func pump(until condition: () -> Bool, timeout: Double = 10) throws {
    let deadline = Date(timeIntervalSinceNow:timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.01)) }
    try check(condition(),"Timed out waiting for network test")
}
func runSelfTests() throws {
    let legacy = try JSONDecoder().decode(Hello.self,from:Data("{\"version\":1,\"bc7\":true,\"name\":\"legacy\"}".utf8))
    try check(try legacy.frameLimit()==2,"Legacy Viewer must retain two credits")
    let modern = Hello(version:1,bc7:true,name:"new",maxFramesInFlight:3,chunkedPacking:true)
    try check(legacy.chunkedPacking == nil,"Legacy peer must not negotiate chunked compression")
    try check(try modern.frameLimit()==3 && modern.frameLimit(requested:2)==2,"Negotiated frame credits")
    try check(try Hello(version:1,bc7:true,name:"future",maxFramesInFlight:1000).frameLimit()==3,"Frame credits must remain bounded")
    try check(try Hello(version:1,bc7:true,name:"single",maxFramesInFlight:1).frameLimit()==1,"Receiver capacity must be respected")
    try expectInvalid { _ = try Hello(version:1,bc7:true,name:"invalid",maxFramesInFlight:0).frameLimit() }
    struct LegacyHello: Decodable {let version:Int;let bc7:Bool;let name:String}
    let compatible = try JSONDecoder().decode(LegacyHello.self,from:JSONEncoder().encode(modern))
    try check(compatible.version==1 && compatible.bc7,"Legacy Host greeting compatibility")
    print("PASS: negotiated credits, legacy defaults, bounded capacity and backwards-compatible greeting")
    var rate = RateWindow(now:0)
    rate.frames = 60; rate.bytes = 1_000_000
    let moving = rate.take(now:1), idle = rate.take(now:2)
    rate.frames = 60
    let resumed = rate.take(now:3)
    try check(moving.fps == 60 && moving.mbps == 8 && idle.fps == 0 && idle.mbps == 0 && resumed.fps == 60,"Idle time contaminated the next measurement window")
    print("PASS: active, idle and resumed one-second counter windows")
    let statistics=ViewerStatistics()
    func measured(_ delay:Double)->RenderTiming {
        RenderTiming(sequence:1,width:5120,height:2880,queueMS:0,unpackMS:1,uploadMS:1,drawableMS:0,gpuMS:4,totalMS:delay+6,submissionMS:delay,callbackMS:0.1,presentMS:0.02)
    }
    statistics.completed(measured(1));statistics.completed(measured(99))
    statistics.receivedBody(in:2);statistics.receivedBody(in:80)
    let burst=statistics.report()
    try check(burst.contains("GPU start delay 50.00 ms · max 99.00 ms") && burst.contains("assembly 41.0 ms · max 80.0 ms"),"Brief stalls were hidden by average timings")
    statistics.completed(measured(1));statistics.receivedBody(in:2)
    let reset=statistics.report()
    try check(reset.contains("GPU start delay 1.00 ms · max 1.00 ms") && reset.contains("assembly 2.0 ms · max 2.0 ms"),"Worst-case timing counters did not reset")
    print("PASS: short stall maxima, independent stage averages and per-interval reset")
    try runPairingTests()
    let bytes = Data(repeating:0x40,count:128*128)
    let frame = Frame(sequence:7,width:2560,height:1440,keyframe:false,tiles:[TileUpdate(id:0,bytes:bytes)])
    let packed = frame.serialize(), decoded = try Frame.parse(packed)
    let packer = FramePacker()
    let reusablePacket = try packer.serialize(frame)
    try check(reusablePacket==packed,"Reusable frame packer changed compressed bytes")
    var retainedPackets:[Data]=[], expectedPackets:[Data]=[]
    for i in 0..<20 {
        let value = Data((0..<(i%2==0 ? 16_384:256)).map {UInt8(truncatingIfNeeded:($0 &* 1664525) ^ i)})
        let input = Frame(sequence:UInt64(i+1),width:2560,height:1440,keyframe:false,tiles:[TileUpdate(id:0,bytes:value)])
        retainedPackets.append(try packer.serialize(input));expectedPackets.append(input.serialize())
    }
    try check(retainedPackets==expectedPackets && reusablePacket==packed,"Reusable packer overwrote retained packets or changed encoding")
    print("PASS: reusable packing matches baseline packets and retains independent output across scratch-buffer reuse")
    try testChunkedPacking()
    try check(decoded.sequence == 7 && decoded.tiles[0].bytes == bytes,"Frame round trip")
    let padded = Data([0xFF]) + packed
    for copy in [false,true] {
        let sliced = try Frame.parse(padded.dropFirst(),copyBuffers:copy)
        try check(sliced.sequence==7 && sliced.tiles[0].bytes==bytes,"Frame backing-buffer offsets or lifetime changed")
        try check(try Frame.parse(sliced.serialize()).tiles[0].bytes==bytes,"Shared tile view serialization changed")
    }
    var raw = Data(); raw.put64(7); raw.put32(2560); raw.put32(1440); raw.put32(0); raw.put32(1); raw.put32(0); raw.append(bytes)
    var plain = Data([0]); plain.put32(UInt32(raw.count)); plain.put32(UInt32(raw.count)); plain.append(raw)
    let retained = try Frame.parse(plain)
    plain[plain.count-1] = 0x41
    try check(retained.tiles[0].bytes==bytes,"Uncompressed shared tile storage changed after input mutation")
    print("PASS: copied/shared frame buffers, nonzero Data indices, retained tile contents and reserialization")
    for length in [0,1,4,5,packed.count-1] { try expectInvalid { _ = try Frame.parse(packed.prefix(length)) } }
    let dup = Frame(sequence:1,width:2560,height:1440,keyframe:false,tiles:[TileUpdate(id:0,bytes:bytes),TileUpdate(id:0,bytes:bytes)])
    try expectInvalid { _ = try Frame.parse(dup.serialize()) }
    let badKey = Frame(sequence:1,width:2560,height:1440,keyframe:true,tiles:[TileUpdate(id:0,bytes:bytes)])
    try expectInvalid { _ = try Frame.parse(badKey.serialize()) }
    let badID = Frame(sequence:1,width:2560,height:1440,keyframe:false,tiles:[TileUpdate(id:99999,bytes:bytes)])
    try expectInvalid { _ = try Frame.parse(badID.serialize()) }
    print("PASS: compressed-frame round trip, malformed frames, bounds, duplicate tiles and incomplete keyframes")
    try testTextureUpload()
    #if HOST
    try testGPU()
    try testFlatBlockFastPath()
    try testCaptureMailbox()
    try testCaptureProbe()
    #else
    if let device = MTLCreateSystemDefaultDevice() { print("GPU: \(device.name); BC textures: \(supportsBC(device))") }
    #endif
    print("ALL SELF-TESTS PASSED")
}

func testChunkedPacking() throws {
    let packer = FramePacker()
    var retained:[Data] = [], expected:[Frame] = []
    for (w,h) in [(2560,1440),(3840,2160),(5120,2880)] {
        let total=((w+127)/128)*((h+127)/128)
        let tiles=(0..<total).map { id -> TileUpdate in
            let d=Frame.dimensions(id,w,h)
            return TileUpdate(id:id,bytes:Data((0..<(d.w*d.h)).map {UInt8(truncatingIfNeeded:($0/7) ^ id)}))
        }
        let frame=Frame(sequence:UInt64(w),width:w,height:h,keyframe:true,tiles:tiles)
        let packet=try packer.serialize(frame,parallel:true)
        try check(packet.first==2,"Compressible frame did not exercise chunked packing")
        retained.append(packet);expected.append(frame)
    }
    for (packet,frame) in zip(retained,expected) {
        for copy in [false,true] {
            let decoded=try Frame.parse((Data([0xFF])+packet).dropFirst(),copyBuffers:copy)
            try check(decoded.sequence==frame.sequence && decoded.width==frame.width && decoded.height==frame.height && decoded.keyframe,"Chunked frame identity changed")
            try check(decoded.tiles.count==frame.tiles.count && zip(decoded.tiles,frame.tiles).allSatisfy {$0.id==$1.id && $0.bytes==$1.bytes},"Chunked packing changed tile bytes or retained packet storage")
        }
    }
    // Unique pseudorandom bytes exercise uncompressed chunks and whole-frame fallback.
    var state:UInt64=0x1234567890abcdef
    func noise(_ n:Int)->Data {
        var bytes=Data(count:n)
        bytes.withUnsafeMutableBytes { (p:UnsafeMutableRawBufferPointer) in
            for i in stride(from:0,to:n,by:8) {state ^= state<<13;state ^= state>>7;state ^= state<<17;p.storeBytes(of:state,toByteOffset:i,as:UInt64.self)}
        }
        return bytes
    }
    for mixed in [false,true] {
        let tiles=(0..<80).map {TileUpdate(id:$0,bytes:mixed && $0<40 ? Data(repeating:0x40,count:16384):noise(16384))}
        let frame=Frame(sequence:mixed ? 2:1,width:2560,height:1440,keyframe:false,tiles:tiles)
        let packet=try packer.serialize(frame,parallel:true), decoded=try Frame.parse(packet)
        try check(packet.first==(mixed ? 2:0),"Compression fallback was not exercised")
        try check(zip(decoded.tiles,tiles).allSatisfy {$0.id==$1.id && $0.bytes==$1.bytes},"Raw or mixed compression chunks changed bytes")
    }
    func envelope(_ payload:Data,_ count:UInt32=24)->Data {
        var d=Data([2]);d.put32(count);d.put32(UInt32(payload.count));d.append(payload);return d
    }
    for n in [UInt32(0),1,5,UInt32.max] {var d=Data();d.put32(n);try expectInvalid {_ = try Frame.parse(envelope(d))}}
    let invalidSizes:[(UInt32,UInt32)] = [(0,0),(25,1),(12,13),(12,0),(UInt32.max,1)]
    for (raw,stored) in invalidSizes {
        var d=Data();d.put32(2);d.put32(raw);d.put32(stored);d.append(0)
        try expectInvalid {_ = try Frame.parse(envelope(d))}
    }
    let packet=retained[2]
    for n in [9,12,20,packet.count-1] {try expectInvalid {_ = try Frame.parse(packet.prefix(n))}}
    var invalidLZ4=Data();invalidLZ4.put32(2)
    for _ in 0..<2 {invalidLZ4.put32(12);invalidLZ4.put32(1);invalidLZ4.append(0)}
    try expectInvalid {_ = try Frame.parse(envelope(invalidLZ4))}
    print("PASS: parallel lossless packing preserves every tile at 1440p/4K/5K, owned output, raw/mixed chunks, legacy negotiation and malformed-input rejection")
}

func runPairingTests() throws {
    try check(try normalizedCode("0123-4567-89AB-CDEF-0123-4567-89AB-CDEF") == "0123456789ABCDEF0123456789ABCDEF","Long code normalization")
    try check(try PairingMode.shortCode.credential(from:" 01234 ") == "01234","Leading zero in five-digit code")
    try check(try PairingMode.noCode.credential(from:"ignored") == nil,"Explicit no-code mode")
    for invalid in ["", "1234", "123456", "abcde", "１２３４５"] { try expectInvalid { _ = try normalizedCode(invalid) } }
    try expectInvalid { _ = try networkParameters("") }
    try expectInvalid { _ = try PairingMode.longCode.credential(from:"01234") }
    try expectInvalid { _ = try PairingMode.shortCode.credential(from:randomPairingCode()) }
    var saved: String?
    let first = savedShortCode(saved) { saved = $0 }
    let reopened = savedShortCode(saved) { _ in preconditionFailure("Valid saved PIN was replaced") }
    try check(first == reopened && first.count == 5,"Short code did not survive simulated reopen")
    try check(savedShortCode("00123") { _ in preconditionFailure("Leading zeros were discarded") } == "00123","Saved leading-zero code")
    var replacement: String?
    _ = savedShortCode("invalid") { replacement = $0 }
    try check(replacement?.count == 5,"Invalid saved PIN was not regenerated")
    print("PASS: five-digit and long codes, explicit no-code mode, saved PIN reuse, leading zeros and invalid-code rejection")
    try testNetwork(code:randomPairingCode())
    try testNetwork(code:"01234")
    try testNetwork(code:nil)
    try testPlaintextAgainstPairedHost()
    print("ALL PAIRING TESTS PASSED")
}

func testNetwork(code: String?) throws {
    let listener = try NWListener(using:networkParameters(code),on:.any)
    var ready = false, received = false, failure: String?, server: Link?, wrong: Link?
    var wrongReady = false, wrongRejected = false, acceptWrong = false, acknowledged = false
    let payload = Data((0..<65536).map { UInt8($0 % 251) })
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready = true }
        if case .failed(let error) = state { failure = String(describing:error); ready = true }
    }
    listener.newConnectionHandler = { connection in
        let link = Link(connection)
        if acceptWrong { wrong = link } else { server = link }
        link.onMessage = { type,data in link.send(type,data) }
        link.start()
    }
    listener.start(queue:.main); defer { listener.cancel(); server?.cancel(); wrong?.cancel() }
    try pump(until:{ready}); if let failure = failure { throw LinkError.invalid(failure) }
    guard let port = listener.port else { throw LinkError.invalid("Missing listener port") }
    let client = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(code)))
    defer { client.cancel() }
    client.onReady = { client.send(99,payload) }
    client.onMessage = { type,data in if type == 99 { DispatchQueue.main.async { received = data == payload } } }
    client.onClose = { reason in DispatchQueue.main.async { if !received { failure = reason; received = true } } }
    client.start(); try pump(until:{received}); if let failure = failure { throw LinkError.invalid(failure) }
    client.setAcknowledgementHandler { data in DispatchQueue.main.async { acknowledged = data == Data([1,2,3]) } }
    client.send(3,Data([1,2,3])); try pump(until:{acknowledged})
    acceptWrong = true
    let wrongCode = code == nil || code?.count == 5 ? "56789" : randomPairingCode()
    let badClient = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(wrongCode)))
    defer { badClient.cancel() }
    badClient.onReady = { DispatchQueue.main.async { wrongReady = true; wrongRejected = true } }
    badClient.onClose = { _ in DispatchQueue.main.async { wrongRejected = true } }
    badClient.start(); try pump(until:{wrongRejected},timeout:18)
    try check(!wrongReady,"Wrong pairing code unexpectedly connected")
    print("PASS: \(code == nil ? "no-code TCP" : (code!.count == 5 ? "five-digit TLS" : "long-code TLS")) loopback transfer, direct acknowledgement dispatch and rejection of mismatched pairing")
}

func testPlaintextAgainstPairedHost() throws {
    let listener = try NWListener(using:networkParameters("01234"),on:.any)
    var ready = false, closed = false, applicationDataAccepted = false, server: Link?, failure: String?
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready = true }
        if case .failed(let error) = state { failure = String(describing:error); ready = true }
    }
    listener.newConnectionHandler = { connection in
        let peer = Link(connection); server = peer
        peer.onMessage = { _,_ in DispatchQueue.main.async { applicationDataAccepted = true; closed = true } }
        peer.start()
    }
    listener.start(queue:.main); defer { listener.cancel(); server?.cancel() }
    try pump(until:{ready}); if let failure = failure { throw LinkError.invalid(failure) }
    guard let port = listener.port else { throw LinkError.invalid("Missing test listener port") }
    let client = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(nil)))
    defer { client.cancel() }
    client.onReady = { client.send(99,Data(repeating:0x42,count:64)) }
    client.onClose = { _ in DispatchQueue.main.async { closed = true } }
    client.start(); try pump(until:{closed},timeout:18)
    try check(!applicationDataAccepted,"Paired Host accepted a no-code connection")
    print("PASS: a code-protected Host rejects a plaintext no-code client; no automatic downgrade")
}

func runTransportTests() throws {
    try check(try networkParameters("01234").serviceClass == .bestEffort,"Baseline encrypted transport must use default service class")
    try check(try networkParameters(nil).serviceClass == .bestEffort,"Baseline plaintext transport must use default service class")
    print("PASS: baseline best-effort service class in encrypted and plaintext modes")
    try runPairingTests()
    for code: String? in ["01234",nil] { try testLargeTransport(code:code) }
    try testFragmentedTransport()
    print("ALL TRANSPORT TESTS PASSED")
}

// Exercise the real streaming pattern: two multi-megabyte messages may be in
// flight, and each receiver acknowledgement releases exactly one credit.
func testLargeTransport(code: String?) throws {
    let payload = Data((0..<(2*1024*1024)).map { UInt8($0 % 251) })
    let listener = try NWListener(using:networkParameters(code),on:.any)
    var ready = false, finished = false, failure: String?, server: Link?
    var sent = 0, received = 0, acknowledged = 0, completedSends = 0
    let messages = 20
    func fill() {
        while sent < messages && sent-acknowledged < 2 {
            sent += 1
            var data = Data(); data.put64(UInt64(sent)); data.append(payload)
            server?.send(99,data) { DispatchQueue.main.async { completedSends += 1 } }
        }
    }
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready = true }
        if case .failed(let e) = state { failure = "\(e)"; ready = true }
    }
    listener.newConnectionHandler = { connection in
        let peer = Link(connection); server = peer
        peer.onReady = { DispatchQueue.main.async { fill() } }
        peer.setAcknowledgementHandler { data in DispatchQueue.main.async {
            do {
                var r = Reader(data:data); let sequence = try r.u64()
                try check(r.atEnd && sequence == UInt64(acknowledged+1),"Acknowledgements reordered")
                acknowledged += 1; fill(); finished = acknowledged == messages
            } catch { failure = "\(error)"; finished = true }
        } }
        peer.onClose = { reason in DispatchQueue.main.async { if !finished { failure = reason; finished = true } } }
        peer.start()
    }
    listener.start(queue:.main); defer { listener.cancel(); server?.cancel() }
    try pump(until:{ready}); if let failure = failure { throw LinkError.invalid(failure) }
    guard let port = listener.port else { throw LinkError.invalid("Missing test port") }
    let client = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(code)))
    defer { client.cancel() }
    client.onMessage = { type, data in DispatchQueue.main.async {
        do {
            var r = Reader(data:data); let sequence = try r.u64()
            try check(type == 99 && sequence == UInt64(received+1),"Large messages reordered")
            try check(try r.bytes(data.count-r.offset) == payload,"Large message corrupted")
            received += 1; var ack = Data(); ack.put64(sequence); client.send(3,ack)
        } catch { failure = "\(error)"; finished = true }
    } }
    client.onClose = { reason in DispatchQueue.main.async { if !finished { failure = reason; finished = true } } }
    client.start(); try pump(until:{finished},timeout:30)
    if let failure = failure { throw LinkError.invalid(failure) }
    try pump(until:{completedSends == messages})
    try check(received == messages && acknowledged == messages,"Lost large messages")
    print("PASS: \(code == nil ? "plaintext" : "encrypted") 40 MiB transfer, two messages in flight, ordered acknowledgements, exact payloads and send completions")
}

// An independent byte-stream producer splits both the header and body, then
// coalesces the end of one message with the next. The production receiver must
// retain its framing regardless of TCP/TLS chunk boundaries.
func testFragmentedTransport() throws {
    let listener = try NWListener(using:networkParameters(nil),on:.any)
    var ready = false, finished = false, failure: String?, server: NWConnection?, received = 0
    let payload = Data((0..<131_077).map { UInt8($0 % 251) })
    func packet(_ type: UInt8,_ data: Data) -> Data {
        var result = Data(); result.put32(UInt32(data.count+1)); result.append(type); result.append(data); return result
    }
    var bytes = packet(77,payload); bytes.append(packet(78,Data([1,2,3])))
    // Invalid zero-length header after the two valid messages must close Link.
    bytes.put32(0)
    let splits = [1,3,5,8191,65537,bytes.count]
    var chunks: [Data] = [], offset = 0
    for end in splits { chunks.append(bytes.subdata(in:offset..<end)); offset = end }
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready = true }
        if case .failed(let e) = state { failure = "\(e)"; ready = true }
    }
    listener.newConnectionHandler = { connection in
        server = connection
        func write(_ index: Int) {
            guard index < chunks.count else { return }
            connection.send(content:chunks[index],completion:.contentProcessed { error in
                if let error = error { failure = "\(error)"; finished = true; return }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.002) { write(index+1) }
            })
        }
        connection.stateUpdateHandler = { state in if case .ready = state { write(0) } }
        connection.start(queue:.main)
    }
    listener.start(queue:.main); defer { listener.cancel(); server?.cancel() }
    try pump(until:{ready}); if let failure = failure { throw LinkError.invalid(failure) }
    guard let port = listener.port else { throw LinkError.invalid("Missing test port") }
    let client = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(nil)))
    defer { client.cancel() }
    client.onMessage = { type,data in DispatchQueue.main.async {
        if (received == 0 && type == 77 && data == payload) || (received == 1 && type == 78 && data == Data([1,2,3])) {
            received += 1
        } else { failure = "Fragmented/coalesced stream corrupted"; finished = true }
    } }
    client.onClose = { reason in DispatchQueue.main.async {
        if received != 2 || reason != "Invalid packet length" { failure = "Unexpected framing close: \(reason)" }
        finished = true
    } }
    client.start(); try pump(until:{finished})
    if let failure = failure { throw LinkError.invalid(failure) }
    print("PASS: fragmented headers/bodies, coalesced messages and invalid-length rejection")
}

// Exercise the exact uploader used by Viewer: two queued delta updates must
// preserve unchanged tiles, including the partial-height bottom row at 5K.
func testTextureUpload() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw LinkError.invalid("GPU unavailable for upload test") }
    for (w,h) in [(2560,1440),(3840,2160),(5120,2880)] {for (coalesced,writeCombined) in [(false,false),(true,false),(true,true)] {
        let columns=(w+127)/128,total=columns*((h+127)/128)
        func tile(_ id:Int,_ value:UInt8)->TileUpdate {
            let d=Frame.dimensions(id,w,h)
            return TileUpdate(id:id,bytes:Data((0..<(d.w*d.h)).map {UInt8(truncatingIfNeeded:($0/13) ^ Int(value))}))
        }
        let ids=[total-1,total-3,total-2,3,1,2,columns,columns-1,columns+2]
        let frames=[
            Frame(sequence:1,width:w,height:h,keyframe:true,tiles:(0..<total).map {tile($0,UInt8($0%251))}),
            Frame(sequence:2,width:w,height:h,keyframe:false,tiles:ids.map {tile($0,253)}),
            Frame(sequence:3,width:w,height:h,keyframe:false,tiles:[tile(0,254)])]
        let uploader=TextureUploader(device:device,coalesced:coalesced,writeCombined:writeCombined)
        var readbacks:[(MTLCommandBuffer,MTLBuffer)]=[]
        func submit(_ frame:Frame) throws -> (MTLCommandBuffer,MTLBuffer) {
            guard let command=queue.makeCommandBuffer(),let output=device.makeBuffer(length:w*h,options:.storageModeShared) else {throw LinkError.invalid("Upload test allocation failed")}
            let texture=try uploader.encode(Frame.parse(frame.serialize()),into:command)
            try check(texture.storageMode == .private,"Receiver texture is not GPU private")
            guard let blit=command.makeBlitCommandEncoder() else {throw LinkError.invalid("Readback encoder failed")}
            blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:w,height:h,depth:1),to:output,destinationOffset:0,destinationBytesPerRow:w*4,destinationBytesPerImage:w*h)
            blit.endEncoding();command.commit();return (command,output)
        }
        for frame in frames {readbacks.append(try submit(frame))}
        var expected=Data(repeating:0,count:w*h)
        func validate(_ frame:Frame,_ readback:(MTLCommandBuffer,MTLBuffer)) throws {
            let (command,output)=readback;command.waitUntilCompleted();if let error=command.error {throw error}
            for tile in frame.tiles {
                let d=Frame.dimensions(tile.id,w,h)
                for row in 0..<(d.h/4) {
                    let start=(d.y/4+row)*w*4+d.x*4,source=row*d.w*4
                    expected.replaceSubrange(start..<(start+d.w*4),with:tile.bytes[source..<(source+d.w*4)])
                }
            }
            try check(Data(bytes:output.contents(),count:w*h)==expected,"Upload changed BC7 bytes at \(w)×\(h), sequence \(frame.sequence), coalesced \(coalesced)")
        }
        for (frame,result) in zip(frames,readbacks) {try validate(frame,result)}
        let fourth=Frame(sequence:4,width:w,height:h,keyframe:false,tiles:(0..<total).reversed().map {tile($0,241)})
        let result=try submit(fourth);try validate(fourth,result)
        try check(uploader.lastBlitCount == (coalesced ? (h+127)/128:total),"Unexpected full-frame upload grouping")
        guard let command=queue.makeCommandBuffer() else {throw LinkError.invalid("Command allocation failed")}
        try expectInvalid {_ = try uploader.encode(fourth,into:command)}
    }}
    print("PASS: baseline/coalesced private BC7 uploads in cached/write-combined memory match every byte at 1440p/4K/5K; queued deltas, unsorted runs, holes, row boundaries, bottom edges, staging reuse and sequence checks")
}

// A synthetic on-screen test of the production renderer. Does not capture any
// other window or screen, and closes its own temporary window when finished.
func testViewerPresentation() throws {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    let view = try DisplayView(viewer:true)
    let window = NSWindow(contentRect:NSRect(x:100,y:100,width:960,height:540),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.title = "RetinaLink synthetic rendering test"; window.isReleasedWhenClosed = false
    window.contentView = view; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true)
    defer { window.orderOut(nil); window.contentView = nil; window.close() }
    var completed = 0, failure: String?, times: [Double] = []
    view.onFrame = { timing in DispatchQueue.main.async { completed += 1; times.append(timing.totalMS) } }
    view.onError = { text in DispatchQueue.main.async { failure = text } }
    let w = 5120, h = 2880
    for i in 1...60 {
        try pump(until:{i-completed <= 2 || failure != nil})
        if let failure = failure { throw LinkError.invalid(failure) }
        let ids = i == 1 ? Array(0..<920) : [0,919]
        let tiles = ids.map { id -> TileUpdate in
            let d = Frame.dimensions(id,w,h)
            var bytes = Data(repeating:UInt8((i*3)%256),count:d.w*d.h)
            for offset in stride(from:0,to:bytes.count,by:16) { bytes[offset] = 64 }
            return TileUpdate(id:id,bytes:bytes)
        }
        view.receive(Frame(sequence:UInt64(i),width:w,height:h,keyframe:i == 1,tiles:tiles).serialize())
    }
    try pump(until:{completed == 60 || failure != nil})
    if let failure = failure { throw LinkError.invalid(failure) }
    let steady = Array(times.dropFirst())
    print(String(format:"PASS: 60 synthetic 5K frames through the production asynchronous renderer; receiver mean %.1f ms (excludes first frame).",steady.reduce(0,+)/Double(steady.count)))
    print("Windowed local test only; does not measure the Intel iMac, Ethernet or input-to-photon latency.")
}

#if HOST
func testCaptureMailbox() throws {
    var first: CVPixelBuffer?, second: CVPixelBuffer?
    CVPixelBufferCreate(nil,16,16,kCVPixelFormatType_32BGRA,nil,&first)
    CVPixelBufferCreate(nil,16,16,kCVPixelFormatType_32BGRA,nil,&second)
    let mailbox=CaptureMailbox(); mailbox.start()
    try check(mailbox.offer(first!),"First frame did not schedule work")
    try check(!mailbox.offer(second!),"Pending frame scheduled duplicate work")
    try check(mailbox.take() === second!,"Mailbox did not preserve latest frame")
    try check(mailbox.take()==nil,"Mailbox retained an already consumed frame")
    let counts=mailbox.counts(); try check(counts.complete==2 && counts.replaced==1,"Incorrect coalescing counters")
    try check(mailbox.offer(first!),"Mailbox failed to reschedule after draining")
    mailbox.stop(); try check(mailbox.take()==nil && !mailbox.offer(second!),"Stopped mailbox accepted a frame")
    mailbox.start();try check(mailbox.offer(first!,id:41,displayTime:1.25),"Trace input failed to schedule")
    try check(!mailbox.offer(second!,id:42,displayTime:1.5),"Trace input scheduled duplicate work")
    let input=mailbox.takeInput()
    try check(input?.image === second! && input?.id==42 && input?.displayTime==1.5,"Coalescing lost capture identity/time")
    mailbox.stop()
    print("PASS: bounded latest-frame mailbox, coalescing, scheduling and stop cleanup")
}

func testFlatBlockFastPath() throws {
    let fast = try TextureEncoder(baseline:false), baseline = try TextureEncoder(baseline:true,atomicStore:false)
    let w=2560, h=1440
    var image: CVPixelBuffer?
    let attrs: [String:Any] = [kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
    guard CVPixelBufferCreate(nil,w,h,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&image) == kCVReturnSuccess, let image=image else { throw LinkError.invalid("Test surface allocation") }
    CVPixelBufferLockBaseAddress(image,[])
    let row=CVPixelBufferGetBytesPerRow(image), p=CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to:UInt8.self)
    for y in 0..<h { for x in 0..<w {
        let block=UInt32((y/4)*(w/4)+x/4), color=block &* 2654435761
        let i=y*row+x*4
        p[i]=UInt8(truncatingIfNeeded:color); p[i+1]=UInt8(truncatingIfNeeded:color>>8); p[i+2]=UInt8(truncatingIfNeeded:color>>16); p[i+3]=255
        if block%8==0 { p[i] &+= UInt8((x%4)+(y%4)*4) }
    } }
    CVPixelBufferUnlockBaseAddress(image,[])
    guard let a=try fast.encode(image,sequence:1,force:true),let b=try baseline.encode(image,sequence:1,force:true) else { throw LinkError.invalid("Missing comparison frame") }
    try check(a.tiles.count==b.tiles.count,"Fast-path tile count")
    for (x,y) in zip(a.tiles,b.tiles) { try check(x.id==y.id && x.bytes==y.bytes,"Flat-block path changed BC7 output") }
    try check(try fast.encode(image,sequence:2,force:false)==nil,"Fast-path static suppression")
    print("PASS: 230400 varied flat/non-flat blocks match the baseline encoder byte for byte; static suppression retained")
    try testTileMajorOutput()
}

func testTileMajorOutput() throws {
    for (w,h) in [(2560,1440),(3840,2160),(5120,2880)] {
        let linear = try TextureEncoder(tileMajor:false), tiled = try TextureEncoder(tileMajor:true)
        var image:CVPixelBuffer?
        let attrs:[String:Any] = [kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
        guard CVPixelBufferCreate(nil,w,h,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&image) == kCVReturnSuccess,let image=image else {throw LinkError.invalid("Layout test allocation")}
        CVPixelBufferLockBaseAddress(image,[])
        let stride=CVPixelBufferGetBytesPerRow(image), bytes=CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to:UInt8.self)
        for y in 0..<h { for x in 0..<w {
            let i=y*stride+x*4, seed=UInt32(y/4*(w/4)+x/4) &* 2654435761
            bytes[i]=UInt8(truncatingIfNeeded:seed);bytes[i+1]=UInt8(truncatingIfNeeded:seed>>8);bytes[i+2]=UInt8(truncatingIfNeeded:seed>>16);bytes[i+3]=255
            if seed%7==0 {bytes[i] &+= UInt8((x%4)+(y%4)*4)}
        } }
        CVPixelBufferUnlockBaseAddress(image,[])
        guard let a=try linear.encode(image,sequence:1,force:true),let b=try tiled.encode(image,sequence:1,force:true) else {throw LinkError.invalid("Layout keyframe missing")}
        try check(a.tiles.count==b.tiles.count,"Layout tile count")
        for (x,y) in zip(a.tiles,b.tiles) {try check(x.id==y.id && x.bytes==y.bytes,"Tile-major keyframe changed compressed bytes at \(w)×\(h), tile \(x.id)")}
        CVPixelBufferLockBaseAddress(image,[])
        for (x,y) in [(0,0),(127,127),(128,128),(w-1,h-1),(128,h-1)] {let i=y*stride+x*4;bytes[i] ^= 255;bytes[i+1] ^= 255;bytes[i+2] ^= 255}
        CVPixelBufferUnlockBaseAddress(image,[])
        guard let c=try linear.encode(image,sequence:2,force:false),let d=try tiled.encode(image,sequence:2,force:false) else {throw LinkError.invalid("Layout delta missing")}
        try check(c.tiles.count==d.tiles.count,"Layout delta tile count")
        for (x,y) in zip(c.tiles,d.tiles) {try check(x.id==y.id && x.bytes==y.bytes,"Tile-major boundary/bottom delta changed bytes")}
        try check(try tiled.encode(image,sequence:3,force:false)==nil,"Tile-major static suppression")
    }
    print("PASS: row-major and tile-major GPU output match byte for byte at 1440p/4K/5K, including boundary/bottom-edge deltas and static suppression")
}

import ScreenCaptureKit

// Simulate denial through the production startup path. This never enumerates
// screens, requests OS permission or starts a capture/virtual display.
func runPermissionTests() throws {
    let denied = NSError(domain:SCStreamErrorDomain,code:SCStreamError.Code.userDeclined.rawValue)
    try check(CaptureAuthorization.isDenied(denied),"Capture denial was not recognized")
    try check(!CaptureAuthorization.isDenied(NSError(domain:SCStreamErrorDomain,code:SCStreamError.Code.failedToStart.rawValue)),"Ordinary capture failure mislabeled as permission")
    try check(!CaptureAuthorization.isDenied(NSError(domain:NSCocoaErrorDomain,code:denied.code)),"Unrelated error mislabeled as permission")
    _ = NSApplication.shared
    let host = HostApp()
    host.retryCaptureButton = NSButton(title:"Retry capture",target:nil,action:nil)
    var attempts = 0
    host.makeCapture = { link in
        let session = try CaptureSession(link:link)
        session.authorize = { attempts += 1; throw denied }
        return session
    }
    let listener = try NWListener(using:networkParameters(nil),on:.any)
    host.listener = listener
    var ready = false, accepted = false, notices = 0, echoed = false, failure: String?
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready = true }
        if case .failed(let error) = state { failure = String(describing:error); ready = true }
    }
    listener.newConnectionHandler = { connection in
        let peer = Link(connection); host.link = peer
        peer.onReady = { DispatchQueue.main.async { accepted = true } }
        peer.onMessage = { type,data in if type == 99 { peer.send(type,data) } }
        peer.start()
    }
    listener.start(queue:.main)
    defer { host.startup?.cancel(); listener.cancel(); host.link?.cancel() }
    try pump(until:{ready}); if let failure = failure { throw LinkError.invalid(failure) }
    guard let port = listener.port else { throw LinkError.invalid("Missing listener port") }
    let viewer = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(nil)))
    defer { viewer.cancel() }
    viewer.onMessage = { type,data in DispatchQueue.main.async {
        if type == 4 { notices += 1 }
        if type == 99 && data == Data([7,8,9]) { echoed = true }
    } }
    viewer.start(); try pump(until:{accepted})
    guard let peer = host.link else { throw LinkError.invalid("No test peer") }
    host.beginCapture(peer)
    try pump(until:{host.waitingForPermission && notices == 1})
    try check(host.listener === listener && host.link === peer && peer.connection.state == .ready,"Permission denial disconnected hosting")
    try check(!host.startingCapture && host.retryCaptureButton.isEnabled && host.capture == nil,"Permission wait did not clean up and enable retry")
    try check(attempts == 1,"Permission request repeated without Retry")
    viewer.send(99,Data([7,8,9])); try pump(until:{echoed})
    host.retryCapture()
    try pump(until:{host.waitingForPermission && notices == 2})
    try check(attempts == 2 && host.link === peer && host.listener === listener && !host.stopping,"Retry did not preserve the connected session")
    print("PASS: simulated permission denial keeps Host listening and Viewer connected, cleans up capture, enables explicit Retry, and retries only when requested")
    print("PASS: real localhost messages still pass after denial; no screen content or OS permission was accessed")
}

func testGPU() throws {
    let encoder = try TextureEncoder(), w = 5120, h = 2880
    var pixel: CVPixelBuffer?
    let attrs: [String:Any] = [kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
    let code = CVPixelBufferCreate(nil,w,h,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&pixel)
    guard code == kCVReturnSuccess, let pixel = pixel else { throw LinkError.invalid("Test surface allocation failed") }
    CVPixelBufferLockBaseAddress(pixel,[])
    let rowBytes = CVPixelBufferGetBytesPerRow(pixel), base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to:UInt8.self)
    for y in 0..<h { for x in 0..<w { let i=y*rowBytes+x*4; base[i]=UInt8((x/20)%256);base[i+1]=UInt8((y/12)%256);base[i+2]=UInt8(((x+y)/32)%256);base[i+3]=255 } }
    CVPixelBufferUnlockBaseAddress(pixel,[])
    let start = ProcessInfo.processInfo.systemUptime
    guard let first = try encoder.encode(pixel,sequence:1,force:true) else { throw LinkError.invalid("Missing keyframe") }
    let encodeTime = ProcessInfo.processInfo.systemUptime-start
    try check(first.tiles.count == 920,"5K keyframe tile count")
    let serializeStart = ProcessInfo.processInfo.systemUptime
    let packed = try FramePacker().serialize(first)
    let serializeMS = (ProcessInfo.processInfo.systemUptime-serializeStart)*1000
    try check(packed == first.serialize(),"Reusable 5K keyframe packing changed bytes")
    let decoded = try Frame.parse(packed)
    try check(decoded.width == w && decoded.height == h && decoded.tiles.count == 920,"5K frame round trip")
    try check(try encoder.encode(pixel,sequence:2,force:false) == nil,"Unchanged frame was retransmitted")
    CVPixelBufferLockBaseAddress(pixel,[]); base[0]=255;base[1]=0;base[2]=255;CVPixelBufferUnlockBaseAddress(pixel,[])
    guard let change = try encoder.encode(pixel,sequence:2,force:false) else { throw LinkError.invalid("Changed pixel was not detected") }
    try check(change.tiles.count == 1 && change.tiles[0].id == 0,"Dirty-tile detection")
    for tile in first.tiles { for block in stride(from:0,to:tile.bytes.count,by:16) { try check(tile.bytes[block]&127 == 64,"BC7 mode-6 prefix") } }
    // Decode one block independently, checking endpoint/index bit placement and anchor handling.
    let tile = first.tiles[0].bytes
    func decodeBlock(_ data:Data) -> [[Int]] {
        var bit=7
        func take(_ count:Int)->Int { var value=0; for i in 0..<count {value |= Int((data[bit/8] >> (bit%8)) & 1)<<i;bit+=1};return value }
        var a=[Int](repeating:0,count:4),b=a
        for c in 0..<4 {a[c]=take(7);b[c]=take(7)}
        let pa=take(1),pb=take(1);for c in 0..<4 {a[c]=a[c]*2+pa;b[c]=b[c]*2+pb}
        let weights=[0,4,9,13,17,21,26,30,34,38,43,47,51,55,60,64]
        return (0..<16).map { i in let index=take(i == 0 ? 3 : 4),w=weights[index]; return (0..<3).map {c in ((64-w)*a[c]+w*b[c]+32)/64} }
    }
    let black = decodeBlock(tile.prefix(16))
    try check(black.flatMap{$0}.max()! <= 2,"Independent BC7 decode failed")
    // Exercise the actual viewer fragment shader offscreen and compare to an independent CPU decoder.
    let block = first.tiles[321].bytes.subdata(in:160..<176)
    let reference = decodeBlock(block), gpu = encoder.device
    let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bc7_rgbaUnorm,width:4,height:4,mipmapped:false)
    sourceDescriptor.storageMode = .shared; sourceDescriptor.usage = .shaderRead
    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:4,height:4,mipmapped:false)
    targetDescriptor.storageMode = .shared; targetDescriptor.usage = .renderTarget
    guard let source = gpu.makeTexture(descriptor:sourceDescriptor), let target = gpu.makeTexture(descriptor:targetDescriptor),let command = encoder.queue.makeCommandBuffer() else { throw LinkError.invalid("Offscreen texture allocation failed") }
    block.withUnsafeBytes { source.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:16) }
    let library = try shaderLibrary(gpu), descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name:"screenVertex"); descriptor.fragmentFunction = library.makeFunction(name:"screenFragment");descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    let pipeline = try gpu.makeRenderPipelineState(descriptor:descriptor),pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
    guard let renderer = command.makeRenderCommandEncoder(descriptor:pass) else { throw LinkError.invalid("Offscreen renderer failed") }
    renderer.setRenderPipelineState(pipeline);renderer.setFragmentTexture(source,index:0);renderer.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);renderer.endEncoding();command.commit();command.waitUntilCompleted()
    if let error = command.error { throw error }
    var pixels = [UInt8](repeating:0,count:64)
    target.getBytes(&pixels,bytesPerRow:16,from:MTLRegionMake2D(0,0,4,4),mipmapLevel:0)
    for i in 0..<16 { for c in 0..<3 {try check(abs(Int(pixels[i*4+2-c])-reference[i][c]) <= 1,"GPU BC7 output differs from reference decoder")} }
    print("PASS: real GPU BC7 decoding and viewer shader match independent reference")
    let repetitions = 20, benchmarkStart = ProcessInfo.processInfo.systemUptime
    for i in 0..<repetitions { _ = try encoder.encode(pixel,sequence:UInt64(i+3),force:true) }
    let ms = (ProcessInfo.processInfo.systemUptime-benchmarkStart)*1000/Double(repetitions)
    print(String(format:"PASS: 5K GPU compression, 920-tile keyframe, static-frame suppression, changed-tile detection and BC7 reference decode. First encode %.1f ms; warm average %.1f ms on %@.",encodeTime*1000,ms,encoder.device.name))
    print(String(format:"Synthetic gradient keyframe: %.2f MB after lossless packing; packing %.1f ms.",Double(packed.count)/1e6,serializeMS))
    print("Synthetic test only; excludes screen capture, a physical network, the Intel receiver and panel latency.")
}
#endif

#if HOST
func testCaptureProbe() throws {
    let probe=try CaptureProbe(plan:"capture,hold,source,snapshot,pack",period:10)
    try check(probe.index(at:0)==0 && probe.index(at:9.99)==0 && probe.index(at:10)==1 && probe.index(at:1000)==4,"Probe phase bounds")
    try expectInvalid {_ = try CaptureProbe(plan:"capture,invalid")}
    try expectInvalid {_ = try CaptureProbe(plan:"capture",period:0)}
    var pixel:CVPixelBuffer?
    try check(CVPixelBufferCreate(nil,8,8,kCVPixelFormatType_32BGRA,nil,&pixel)==kCVReturnSuccess,"Probe test surface")
    let original=pixel!
    CVPixelBufferLockBaseAddress(original,[])
    let src=CVPixelBufferGetBaseAddress(original)!,stride=CVPixelBufferGetBytesPerRow(original)
    for y in 0..<8 {for x in 0..<32 {src.storeBytes(of:UInt8(y*17+x),toByteOffset:y*stride+x,as:UInt8.self)}}
    CVPixelBufferUnlockBaseAddress(original,[])
    let snapshot=try CaptureProbe.copy(original)
    CVPixelBufferLockBaseAddress(original,[]);memset(CVPixelBufferGetBaseAddress(original)!,0,stride*8);CVPixelBufferUnlockBaseAddress(original,[])
    CVPixelBufferLockBaseAddress(snapshot,.readOnly);defer {CVPixelBufferUnlockBaseAddress(snapshot,.readOnly)}
    let dst=CVPixelBufferGetBaseAddress(snapshot)!,row=CVPixelBufferGetBytesPerRow(snapshot)
    for y in 0..<8 {for x in 0..<32 {try check(dst.load(fromByteOffset:y*row+x,as:UInt8.self)==UInt8(y*17+x),"Probe snapshot aliases source or changed pixels")}}
    print("PASS: bounded diagnostic phase plan and deep independent BGRA snapshot with row-stride handling")
}
#endif
