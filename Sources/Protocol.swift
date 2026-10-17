import Foundation
import Network
import Security
import CryptoKit
import Compression

let serviceType = "_retinalink._tcp"
let defaultPort: UInt16 = 58473
let tileSize = 128
let maxPacket = 20 * 1024 * 1024
enum LinkError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { if case .invalid(let s) = self { return s }; return "Invalid data" }
}
extension Data {
    mutating func put32(_ x: UInt32) { var v = x.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    mutating func put64(_ x: UInt64) { var v = x.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
}
struct Reader {
    let data: Data
    var offset = 0
    mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, n <= data.count - offset else { throw LinkError.invalid("Truncated message") }
        let start = data.startIndex + offset
        defer { offset += n }; return data.subdata(in: start..<(start+n))
    }
    mutating func sliceBytes(_ n: Int) throws -> Data {
        guard n >= 0, n <= data.count - offset else { throw LinkError.invalid("Truncated message") }
        let start = data.startIndex + offset
        defer { offset += n }; return data[start..<(start+n)]
    }
    mutating func u32() throws -> UInt32 { try bytes(4).reduce(0) { ($0 << 8) | UInt32($1) } }
    mutating func u64() throws -> UInt64 { try bytes(8).reduce(0) { ($0 << 8) | UInt64($1) } }
    var atEnd: Bool { offset == data.count }
}
struct Hello: Codable {
    let version: Int
    let bc7: Bool
    let name: String
    var maxFramesInFlight: Int? = nil
    func frameLimit(requested: Int = 3) throws -> Int {
        // Missing capability means an older Viewer with the original two credits.
        let capacity = maxFramesInFlight ?? 2
        guard capacity > 0 else { throw LinkError.invalid("Invalid Viewer frame capacity") }
        return min(3, max(1, requested), capacity)
    }
}
struct TileUpdate {
    let id: Int
    let bytes: Data
}
struct Frame {
    let sequence: UInt64
    let width: Int
    let height: Int
    let keyframe: Bool
    let tiles: [TileUpdate]
    static func supported(_ w: Int, _ h: Int) -> Bool {
        [(2560,1440), (3840,2160), (5120,2880)].contains { $0.0 == w && $0.1 == h }
    }
    static func dimensions(_ id: Int, _ w: Int, _ h: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        let columns = (w + tileSize - 1) / tileSize
        let x = (id % columns) * tileSize, y = (id / columns) * tileSize
        return (x,y,min(tileSize,w-x),min(tileSize,h-y))
    }
    func serialize() -> Data {
        var raw = Data(); raw.put64(sequence); raw.put32(UInt32(width)); raw.put32(UInt32(height))
        raw.put32(keyframe ? 1 : 0); raw.put32(UInt32(tiles.count))
        for t in tiles { raw.put32(UInt32(t.id)); raw.append(t.bytes) }
        var encoded = [UInt8](repeating: 0, count: raw.count + 1024)
        let size = raw.withUnsafeBytes { src in
            compression_encode_buffer(&encoded, encoded.count, src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_LZ4)
        }
        var result = Data([size > 0 && size < raw.count ? 1 : 0]); result.put32(UInt32(raw.count))
        result.put32(UInt32(result[0] == 1 ? size : raw.count))
        if result[0] == 1 { result.append(contentsOf: encoded.prefix(size)) } else { result.append(raw) }
        return result
    }
    static func parse(_ packet: Data, copyBuffers: Bool = LaunchOptions.has("--copy-frame-buffers")) throws -> Frame {
        var outer = Reader(data: packet)
        let encoding = try outer.bytes(1)[0], count = Int(try outer.u32()), encodedCount = Int(try outer.u32())
        guard count >= 24, count <= maxPacket, encoding <= 1 else { throw LinkError.invalid("Invalid frame envelope") }
        guard encodedCount == packet.count-outer.offset else { throw LinkError.invalid("Truncated encoded frame") }
        let payload = try copyBuffers ? outer.bytes(packet.count - outer.offset) : outer.sliceBytes(packet.count - outer.offset)
        guard !payload.isEmpty else { throw LinkError.invalid("Missing frame payload") }
        let raw: Data
        if encoding == 1 {
            if copyBuffers {
                var decoded = [UInt8](repeating:0,count:count)
                let size = payload.withUnsafeBytes { src in
                    compression_decode_buffer(&decoded,count,src.bindMemory(to:UInt8.self).baseAddress!,payload.count,nil,COMPRESSION_LZ4)
                }
                guard size == count else { throw LinkError.invalid("Invalid compressed frame") }; raw = Data(decoded)
            } else {
                // Decode directly into its final backing buffer. Tile views retain
                // that buffer until the ordered GPU staging upload has copied them.
                var decoded = Data(count:count)
                let size = decoded.withUnsafeMutableBytes { dst in payload.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,count,src.bindMemory(to:UInt8.self).baseAddress!,payload.count,nil,COMPRESSION_LZ4)
                } }
                guard size == count else { throw LinkError.invalid("Invalid compressed frame") }; raw = decoded
            }
        } else { guard payload.count == count else { throw LinkError.invalid("Invalid frame size") }; raw = payload }
        var r = Reader(data: raw)
        let sequence = try r.u64(), width = Int(try r.u32()), height = Int(try r.u32())
        let flags = try r.u32(), n = Int(try r.u32())
        guard supported(width,height), flags <= 1 else { throw LinkError.invalid("Unsupported frame dimensions") }
        let total = ((width+tileSize-1)/tileSize) * ((height+tileSize-1)/tileSize)
        guard n <= total, flags == 0 || n == total else { throw LinkError.invalid("Invalid tile count") }
        var seen = Set<Int>(), tiles: [TileUpdate] = []; tiles.reserveCapacity(n)
        for _ in 0..<n {
            let id = Int(try r.u32())
            guard id < total, seen.insert(id).inserted else { throw LinkError.invalid("Invalid or duplicate tile") }
            let d = dimensions(id,width,height)
            let bytes = try copyBuffers ? r.bytes(d.w*d.h) : r.sliceBytes(d.w*d.h)
            tiles.append(TileUpdate(id: id, bytes: bytes)) // BC7 = one byte/pixel.
        }
        guard r.atEnd else { throw LinkError.invalid("Trailing frame data") }
        return Frame(sequence: sequence, width: width, height: height, keyframe: flags == 1, tiles: tiles)
    }
}

// Confined to Host's serial encoder queue. Returned packets own their bytes;
// neither packet nor tile views can reference these reusable scratch buffers.
final class FramePacker {
    private let raw = UnsafeMutableRawPointer.allocate(byteCount:maxPacket,alignment:16)
    private let packed = UnsafeMutableRawPointer.allocate(byteCount:maxPacket+1024,alignment:16)
    private let scratch = UnsafeMutableRawPointer.allocate(byteCount:max(1,compression_encode_scratch_buffer_size(COMPRESSION_LZ4)),alignment:16)
    deinit { raw.deallocate(); packed.deallocate(); scratch.deallocate() }
    func serialize(_ frame: Frame) throws -> Data {
        var count = 24
        for tile in frame.tiles {
            guard tile.bytes.count <= maxPacket-count-4 else {throw LinkError.invalid("Frame packing capacity exceeded")}
            count += 4+tile.bytes.count
        }
        var offset = 0
        func put32(_ x:UInt32) {raw.storeBytes(of:x.bigEndian,toByteOffset:offset,as:UInt32.self);offset += 4}
        func put64(_ x:UInt64) {raw.storeBytes(of:x.bigEndian,toByteOffset:offset,as:UInt64.self);offset += 8}
        put64(frame.sequence);put32(UInt32(frame.width));put32(UInt32(frame.height));put32(frame.keyframe ? 1:0);put32(UInt32(frame.tiles.count))
        for tile in frame.tiles {
            put32(UInt32(tile.id))
            tile.bytes.withUnsafeBytes { bytes in if bytes.count > 0 {_ = memcpy(raw.advanced(by:offset),bytes.baseAddress!,bytes.count)} }
            offset += tile.bytes.count
        }
        let n = compression_encode_buffer(packed.assumingMemoryBound(to:UInt8.self),maxPacket+1024,raw.assumingMemoryBound(to:UInt8.self),count,scratch,COMPRESSION_LZ4)
        let compressed = n > 0 && n < count, payload = compressed ? n:count
        var result = Data();result.reserveCapacity(9+payload)
        result.append(compressed ? 1:0);result.put32(UInt32(count));result.put32(UInt32(payload))
        result.append((compressed ? packed:raw).assumingMemoryBound(to:UInt8.self),count:payload)
        return result
    }
}

enum PairingMode: Int, CaseIterable {
    case shortCode = 0, longCode, noCode
    var title: String {
        switch self {
        case .shortCode: return "5-digit code"
        case .longCode: return "Long code"
        case .noCode: return "No code — testing (unencrypted)"
        }
    }
    var connectionLabel: String {
        switch self {
        case .shortCode: return "Encrypted · 5-digit code"
        case .longCode: return "Encrypted · long code"
        case .noCode: return "No code · unencrypted"
        }
    }
    func credential(from text: String) throws -> String? {
        if self == .noCode { return nil }
        let normalized = try normalizedCode(text)
        guard normalized.count == (self == .shortCode ? 5 : 32) else {
            throw LinkError.invalid(self == .shortCode ? "Enter the Host’s five-digit code, or choose the same pairing mode as Host." : "Enter the Host’s long code, or choose the same pairing mode as Host.")
        }
        return normalized
    }
}
func randomShortCode() -> String {
    // SystemRandomNumberGenerator supplies uniform random digits, including leading zeros.
    String(format:"%05d",Int.random(in:0..<100_000))
}
func savedShortCode(_ saved: String?, save: (String) -> Void) -> String {
    if let saved = saved, saved.utf8.count == 5, saved.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) { return saved }
    let created = randomShortCode(); save(created); return created
}
func randomPairingCode() -> String {
    var b = [UInt8](repeating: 0, count: 16)
    precondition(SecRandomCopyBytes(kSecRandomDefault, b.count, &b) == errSecSuccess)
    return stride(from: 0, to: 16, by: 2).map { String(format: "%02X%02X", b[$0], b[$0+1]) }.joined(separator: "-")
}
func normalizedCode(_ code: String) throws -> String {
    let s = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    let short = s.utf8.count == 5 && s.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
    let long = s.count == 32 && s.allSatisfy({ "0123456789ABCDEF".contains($0) })
    guard short || long else {
        throw LinkError.invalid("Enter five digits or the complete long code shown on the Host. For no-code testing, select No code on both Macs.")
    }
    return s
}
func networkParameters(_ code: String?, preference: Int = 0) throws -> NWParameters {
    let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.connectionTimeout = 10
    let tls: NWProtocolTLS.Options?
    if let code = code {
    let normalized = try normalizedCode(code), options = NWProtocolTLS.Options()
    tls = options
    let key = SymmetricKey(data: Data(normalized.utf8))
    let psk = Data(HMAC<SHA256>.authenticationCode(for: Data("RetinaLink v1 local display".utf8), using: key))
    let identity = Data("RetinaLink-v1".utf8)
    let pskDispatch = psk.withUnsafeBytes { DispatchData(bytes: $0) }
    let idDispatch = identity.withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(options.securityProtocolOptions, pskDispatch as __DispatchData, idDispatch as __DispatchData)
    sec_protocol_options_append_tls_ciphersuite(options.securityProtocolOptions, tls_ciphersuite_t(rawValue:0x00A8)!)
    sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
    } else { tls = nil } // Explicit test mode only. An empty/invalid code never disables pairing.
    let p = NWParameters(tls: tls, tcp: tcp)
    p.includePeerToPeer = true
    if preference == 1 { p.requiredInterfaceType = .wifi }
    if preference == 2 { p.requiredInterfaceType = .wiredEthernet }
    return p
}

// All callbacks execute on one serial connection queue; application code owns its own state queues.
final class Link {
    let connection: NWConnection
    let queue = DispatchQueue(label: "retinalink.connection", qos: .userInteractive)
    var onReady: (() -> Void)?
    var onMessage: ((UInt8, Data) -> Void)?
    var onClose: ((String) -> Void)?
    private var closed = false
    private var acknowledgementHandler: ((Data) -> Void)?
    private var sendTimingHandler: ((UInt8,Double) -> Void)?
    var onReceiveTiming: ((UInt8,Double) -> Void)?
    init(_ c: NWConnection) { connection = c }
    var pathLabel: String {
        guard let p = connection.currentPath else { return "Connecting" }
        if p.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if p.usesInterfaceType(.wiredEthernet) { return "Wired network" }
        if p.usesInterfaceType(.loopback) { return "Local test" }
        return "IP network"
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready: self.onReady?(); self.readHeader()
            case .failed(let e): self.finish("Connection failed: \(e). Match pairing mode and code on both Macs, and check the network.")
            case .cancelled: self.finish("Disconnected")
            case .waiting(let e): self.finish("Network unavailable: \(e)")
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now()+15) { [weak self] in
            guard let self = self, self.connection.state != .ready, !self.closed else { return }
            self.finish("Connection timed out. Check the address, pairing mode/code and Local Network permission.")
        }
    }
    func send(_ type: UInt8, _ payload: Data = Data(), completion: (() -> Void)? = nil) {
        let enqueued = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            guard let self = self, !self.closed, payload.count+1 <= maxPacket else { return }
            var packet = Data(); packet.put32(UInt32(payload.count+1)); packet.append(type); packet.append(payload)
            self.connection.send(content: packet, completion: .contentProcessed { [weak self] e in
                if let e = e { self?.finish("Send failed: \(e)") } else {
                    self?.sendTimingHandler?(type,(ProcessInfo.processInfo.systemUptime-enqueued)*1000)
                    completion?()
                }
            })
        }
    }
    func setSendTimingHandler(_ handler: @escaping (UInt8,Double) -> Void) {
        queue.async { [weak self] in self?.sendTimingHandler = handler }
    }
    func setAcknowledgementHandler(_ handler: @escaping (Data) -> Void) {
        queue.async { [weak self] in self?.acknowledgementHandler = handler }
    }
    func cancel(reason: String = "Disconnected") { queue.async { [weak self] in self?.finish(reason) } }
    private func finish(_ reason: String) {
        guard !closed else { return }; closed = true
        connection.stateUpdateHandler = nil; connection.cancel(); onClose?(reason)
        onReady = nil; onMessage = nil; onClose = nil; acknowledgementHandler = nil
        sendTimingHandler = nil; onReceiveTiming = nil
    }
    private func exact(_ count: Int, _ completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, done, error in
            guard let self = self, !self.closed else { return }
            if let e = error { self.finish("Receive failed: \(e)"); return }
            guard let d = data, d.count == count else { self.finish(done ? "Peer disconnected" : "Incomplete packet"); return }
            completion(d)
        }
    }
    private func readHeader() {
        exact(4) { [weak self] data in
            guard let self = self else { return }
            let n = data.reduce(0) { ($0 << 8) | Int($1) }
            guard n > 0, n <= maxPacket else { self.finish("Invalid packet length"); return }
            let bodyStarted = ProcessInfo.processInfo.systemUptime
            self.exact(n) { [weak self] body in
                guard let self = self else { return }
                let payload = body.subdata(in:1..<body.count)
                self.onReceiveTiming?(body[0],(ProcessInfo.processInfo.systemUptime-bodyStarted)*1000)
                if body[0] == 3, let handler = self.acknowledgementHandler { handler(payload) }
                else { self.onMessage?(body[0], payload) }
                self.readHeader()
            }
        }
    }
}
