import Foundation
import Network
import Darwin

// Throwing FileHandle read/write APIs require 10.15.4. Use checked POSIX I/O
// so the Viewer retains its existing macOS 10.15.0 deployment target.
private func relayWrite(_ handle: FileHandle, _ data: Data) throws {
    try data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(handle.fileDescriptor,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw LinkError.invalid("Update staging write failed") }
            offset += count
        }
    }
}
private func relayRead(_ handle: FileHandle, _ limit: Int) throws -> Data {
    var data = Data(count:limit)
    let count: Int = try data.withUnsafeMutableBytes { bytes in
        while true {
            let count = Darwin.read(handle.fileDescriptor,bytes.baseAddress!,limit)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw LinkError.invalid("Update staging read failed") }
            return count
        }
    }
    data.count = count; return data
}

// Update bytes use the already authenticated display link. Neither peer can
// supply a new public feed or turn the Host into a general-purpose HTTP proxy.
enum UpdateRelayPolicy {
    static let version = 1
    static let message: UInt8 = 10
    static let chunk = 64 * 1024
    static let feedLimit = 1024 * 1024
    static let archiveLimit = 64 * 1024 * 1024
    static func confirmed(installed: String, target: String, fullscreen: Bool) -> Bool {
        guard fullscreen, let current = Int(installed), let expected = Int(target), current > 0, expected > 0 else { return false }
        return current >= expected
    }
    static func feedURL() -> URL? {
        if let base = UpdateSettings.testBase { return URL(string:base+"/viewer/appcast.xml") }
        guard let text = Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String,
              let url = URL(string:text), url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        #if HOST
        guard url.path.hasSuffix("/host/appcast.xml") else { return nil }
        return url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("viewer/appcast.xml")
        #else
        return url
        #endif
    }
    static func archiveAllowed(_ url: URL, testBase: String? = UpdateSettings.testBase) -> Bool {
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        let file = url.lastPathComponent
        guard file.range(of:"^RetinaLink-Viewer-[0-9]+(?:\\.[0-9]+)*-[1-9][0-9]*\\.zip$",options:.regularExpression) != nil else { return false }
        if let base = testBase, UpdateSettings.validTestBase(base), let origin = URL(string:base),
           url.scheme == "http", url.host == "127.0.0.1", url.port == origin.port {
            return url.path == "/viewer/"+file
        }
        guard url.scheme == "https", url.host == "github.com", url.port == nil || url.port == 443 else { return false }
        return url.path.range(of:"^/apkdmg/RetinaLink/releases/download/v[0-9]+(?:\\.[0-9]+)*/"+NSRegularExpression.escapedPattern(for:file)+"$",options:.regularExpression) != nil
    }
    static func redirectAllowed(_ url: URL, original: URL) -> Bool {
        if url == original { return true }
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return false }
        if original.host == "github.com" {
            return ["github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"].contains(url.host ?? "")
        }
        return url.host == original.host && url.path == original.path
    }
}

struct UpdateRelayPacket: Codable {
    var action: String
    var id: String
    var url: String? = nil
    var offset: Int? = nil
    var total: Int? = nil
    var bytes: Data? = nil
    var error: String? = nil
    static func decode(_ data: Data) -> UpdateRelayPacket? {
        guard data.count <= 96 * 1024, let value = try? JSONDecoder().decode(Self.self,from:data),
              UUID(uuidString:value.id) != nil else { return nil }
        return value
    }
}

// An ephemeral downloader with a byte limit enforced while receiving, before
// extraction. Private temporary files are removed on every terminal path.
final class RelayDownload: NSObject, URLSessionDataDelegate {
    let original: URL, limit: Int, file: URL
    var session: URLSession?, task: URLSessionDataTask?, handle: FileHandle?
    var count = 0, finished = false
    let completion: (Result<(URL,Int),Error>) -> Void
    init(url: URL, limit: Int, completion: @escaping (Result<(URL,Int),Error>) -> Void) throws {
        self.original = url; self.limit = limit; self.completion = completion
        file = FileManager.default.temporaryDirectory.appendingPathComponent("RetinaLink-update-"+UUID().uuidString)
        super.init()
        guard FileManager.default.createFile(atPath:file.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw LinkError.invalid("Update staging is unavailable") }
        handle = try FileHandle(forWritingTo:file)
    }
    func start() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 180
        session = URLSession(configuration:config,delegate:self,delegateQueue:nil)
        var request = URLRequest(url:original,cachePolicy:.reloadIgnoringLocalCacheData)
        request.setValue("RetinaLink-Update-Relay/1",forHTTPHeaderField:"User-Agent")
        task = session?.dataTask(with:request); task?.resume()
    }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { UpdateRelayPolicy.redirectAllowed($0,original:original) } == true ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(limit) else { completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished, data.count <= limit-count else { task?.cancel(); return }
        do { guard let handle = handle else { throw LinkError.invalid("Update file is closed") }; try relayWrite(handle,data); count += data.count } catch { task?.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }; finished = true
        try? handle?.close(); handle = nil; session.finishTasksAndInvalidate(); self.session = nil
        if let error = error { try? FileManager.default.removeItem(at:file); completion(.failure(error)) }
        else if count == 0 { try? FileManager.default.removeItem(at:file); completion(.failure(LinkError.invalid("Empty update response"))) }
        else { completion(.success((file,count))) }
    }
}

final class HostUpdateRelay {
    private weak var peer: Link?
    private let queue = DispatchQueue(label:"retinalink.update-relay.host",qos:.utility)
    private var id: String?, file: URL?, handle: FileHandle?, download: RelayDownload?
    private var offset = 0, total = 0
    private var interruptNextArchive = false
    private var archive = false
    private let feed: URL?
    private let testBase: String?
    var onProgress: ((String) -> Void)?
    init(peer: Link, feed: URL? = UpdateRelayPolicy.feedURL(), testBase: String? = UpdateSettings.testBase) {
        self.peer = peer; self.feed = feed; self.testBase = testBase
    }
    func receive(_ data: Data) { queue.async { [weak self] in self?.consume(data) } }
    // Only the explicit local Host test-control seam calls this; no peer
    // packet can arm interruption or alter download policy.
    func interruptNextArchiveForTesting() { queue.async { [weak self] in self?.interruptNextArchive = true } }
    func stop() { queue.async { [self] in cleanup(); peer = nil } }
    private func send(_ value: UpdateRelayPacket) {
        if let data = try? JSONEncoder().encode(value) { peer?.send(UpdateRelayPolicy.message,data) }
    }
    private func cleanup() {
        download?.cancel(); download = nil; try? handle?.close(); handle = nil
        if let file = file { try? FileManager.default.removeItem(at:file) }
        file = nil; id = nil; offset = 0; total = 0
    }
    private func fail(_ requestID: String) {
        send(UpdateRelayPacket(action:"error",id:requestID,error:"The main Mac could not download the signed update. Check its internet connection and try again.")); cleanup()
    }
    private func consume(_ data: Data) {
        guard let packet = UpdateRelayPacket.decode(data) else { return }
        if packet.action == "cancel", packet.id == id { cleanup(); return }
        if packet.action == "fetch" {
            guard id == nil else { send(UpdateRelayPacket(action:"error",id:packet.id,error:"An update transfer is already in progress.")); return }
            let url: URL?, limit: Int
            if packet.url == nil { url = feed; limit = UpdateRelayPolicy.feedLimit }
            else { url = packet.url.flatMap(URL.init(string:)); limit = UpdateRelayPolicy.archiveLimit }
            guard let source = url, packet.url == nil || UpdateRelayPolicy.archiveAllowed(source,testBase:testBase) else { fail(packet.id); return }
            id = packet.id
            archive = packet.url != nil
            progress(packet.url == nil ? "Checking for an iMac update…" : "Downloading the iMac update on this Mac…")
            do {
                let job = try RelayDownload(url:source,limit:limit) { [weak self] result in
                    guard let self = self else { if case .success(let value) = result { try? FileManager.default.removeItem(at:value.0) }; return }
                    self.queue.async {
                        guard self.id == packet.id else { if case .success(let value) = result { try? FileManager.default.removeItem(at:value.0) }; return }
                        self.download = nil
                        do {
                            let value = try result.get(); self.file = value.0; self.total = value.1
                            self.handle = try FileHandle(forReadingFrom:value.0); self.sendChunk()
                        } catch { self.fail(packet.id) }
                    }
                }
                download = job; job.start()
                queue.asyncAfter(deadline:.now()+210) { [weak self] in if self?.id == packet.id { self?.fail(packet.id) } }
            } catch { fail(packet.id) }
        } else if packet.action == "next", packet.id == id, packet.offset == offset, handle != nil { sendChunk() }
        else if packet.id == id { fail(packet.id) }
    }
    private func sendChunk() {
        guard let id = id, let handle = handle, offset < total else { return }
        do {
            let bytes = try relayRead(handle,min(UpdateRelayPolicy.chunk,total-offset))
            guard !bytes.isEmpty else { fail(id); return }
            let start = offset; offset += bytes.count
            send(UpdateRelayPacket(action:"data",id:id,offset:start,total:total,bytes:bytes))
            if archive && interruptNextArchive {
                interruptNextArchive = false; peer?.cancel(reason:"Local update interruption test")
            }
            if total > UpdateRelayPolicy.feedLimit { progress("Sending to iMac · \(offset * 100 / total)%") }
        } catch { fail(id) }
    }
    private func progress(_ text: String) { DispatchQueue.main.async { [weak self] in self?.onProgress?(text) } }
}
#if !HOST
// Sparkle fetches exact signed bytes from a token-protected loopback server.
// Feed signatures and archive signatures remain mandatory. Only the download
// route changes; appcast contents and its signed enclosure are never rewritten.
final class ViewerUpdateRelay {
    private weak var peer: Link?
    private let queue = DispatchQueue(label:"retinalink.update-relay.viewer",qos:.utility)
    private let token = UUID().uuidString
    private var listener: NWListener?
    private var base: URL?
    private var origins: [String:URL] = [:]
    private var connections: [ObjectIdentifier:NWConnection] = [:]
    private var transfers: [String:Transfer] = [:]
    var onProgress: ((Double) -> Void)?
    var onReady: ((URL) -> Void)?
    private struct Transfer {
        let connection: NWConnection, file: URL, handle: FileHandle, archive: Bool
        var offset = 0, total: Int? = nil
    }
    init(peer: Link) { self.peer = peer }
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener = try NWListener(using:parameters); self.listener = listener
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self, case .ready = state, let port = listener.port,
                  let url = URL(string:"http://127.0.0.1:\(port.rawValue)/\(self.token)") else { return }
            self.base = url
            DispatchQueue.main.async { [weak self] in self?.onReady?(url.appendingPathComponent("appcast.xml")) }
        }
        listener.start(queue:queue)
    }
    func archiveURL(_ source: URL) -> URL? {
        guard UpdateRelayPolicy.archiveAllowed(source) else { return nil }
        return queue.sync {
            guard let base = base else { return nil }
            let url = base.appendingPathComponent(UUID().uuidString).appendingPathComponent(source.lastPathComponent)
            origins[url.path] = source; return url
        }
    }
    func receive(_ data: Data) { queue.async { [weak self] in self?.consume(data) } }
    func stop() { queue.async { [self] in
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        for id in Array(transfers.keys) { finish(id,error:true) }
        for connection in connections.values { connection.cancel() }; connections.removeAll()
        origins.removeAll(); peer = nil; base = nil
    } }
    private func send(_ value: UpdateRelayPacket) {
        if let data = try? JSONEncoder().encode(value) { peer?.send(UpdateRelayPolicy.message,data) }
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 4 else { connection.cancel(); return }
        let key = ObjectIdentifier(connection); connections[key] = connection
        connection.stateUpdateHandler = { [weak self,weak connection] state in
            guard let self = self, let connection = connection else { return }
            if case .cancelled = state { self.remove(connection) }
            if case .failed = state { self.remove(connection) }
        }
        connection.start(queue:queue); readRequest(connection,buffer:Data())
        queue.asyncAfter(deadline:.now()+180) { [weak self,weak connection] in
            guard let self = self, let connection = connection, self.connections[key] != nil else { return }
            self.remove(connection); connection.cancel()
        }
    }
    private func remove(_ connection: NWConnection) {
        connections.removeValue(forKey:ObjectIdentifier(connection))
        for id in transfers.keys.filter({transfers[$0]?.connection === connection}) { finish(id,error:false) }
    }
    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:8192-buffer.count) { [weak self] data,_,done,error in
            guard let self = self else { return }
            var bytes = buffer; bytes.append(data ?? Data())
            if bytes.range(of:Data("\r\n\r\n".utf8)) != nil {
                guard let text = String(data:bytes,encoding:.utf8), let line = text.components(separatedBy:"\r\n").first else { self.respondError(connection); return }
                let parts = line.split(separator:" ")
                guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
                      let path = URLComponents(string:String(parts[1]))?.path,
                      self.base != nil, self.transfers.isEmpty else { self.respondError(connection); return }
                let feed = path == "/\(self.token)/appcast.xml"
                guard feed || self.origins[path] != nil else { self.respondError(connection); return }
                let id = UUID().uuidString
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("RetinaLink-relay-"+id)
                do {
                    guard FileManager.default.createFile(atPath:file.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw LinkError.invalid("Update staging failed") }
                    let handle = try FileHandle(forWritingTo:file)
                    self.transfers[id] = Transfer(connection:connection,file:file,handle:handle,archive:!feed)
                    self.send(UpdateRelayPacket(action:"fetch",id:id,url:feed ? nil : self.origins.removeValue(forKey:path)?.absoluteString))
                } catch { try? FileManager.default.removeItem(at:file); self.respondError(connection) }
            } else if bytes.count < 8192, !done, error == nil { self.readRequest(connection,buffer:bytes) }
            else { self.respondError(connection) }
        }
    }
    private func consume(_ data: Data) {
        guard let packet = UpdateRelayPacket.decode(data), var transfer = transfers[packet.id] else { return }
        guard packet.action == "data", let bytes = packet.bytes, !bytes.isEmpty, bytes.count <= UpdateRelayPolicy.chunk,
              packet.offset == transfer.offset, let total = packet.total, total > 0,
              total <= (transfer.archive ? UpdateRelayPolicy.archiveLimit : UpdateRelayPolicy.feedLimit),
              transfer.total == nil || transfer.total == total, bytes.count <= total-transfer.offset else { finish(packet.id,error:true); return }
        do {
            try relayWrite(transfer.handle,bytes); transfer.offset += bytes.count; transfer.total = total
            transfers[packet.id] = transfer
            if transfer.archive { let fraction = Double(transfer.offset)/Double(total); DispatchQueue.main.async { [weak self] in self?.onProgress?(fraction) } }
            if transfer.offset == total {
                try transfer.handle.close(); transfers.removeValue(forKey:packet.id)
                send(UpdateRelayPacket(action:"cancel",id:packet.id))
                let file = try FileHandle(forReadingFrom:transfer.file)
                let header = "HTTP/1.1 200 OK\r\nContent-Length: \(total)\r\nContent-Type: \(transfer.archive ? "application/zip" : "application/xml")\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                transfer.connection.send(content:Data(header.utf8),completion:.contentProcessed { [weak self] error in
                    guard let self = self else { try? file.close(); try? FileManager.default.removeItem(at:transfer.file); return }
                    if error != nil { self.closeFileResponse(transfer.connection,file:file,url:transfer.file) }
                    else { self.writeFile(transfer.connection,file:file,url:transfer.file) }
                })
            } else { send(UpdateRelayPacket(action:"next",id:packet.id,offset:transfer.offset)) }
        } catch { finish(packet.id,error:true) }
    }
    private func writeFile(_ connection: NWConnection, file: FileHandle, url: URL) {
        do {
            let bytes = try relayRead(file,UpdateRelayPolicy.chunk)
            if bytes.isEmpty { closeFileResponse(connection,file:file,url:url); return }
            connection.send(content:bytes,completion:.contentProcessed { [weak self] error in
                guard let self = self else { try? file.close(); try? FileManager.default.removeItem(at:url); return }
                if error != nil { self.closeFileResponse(connection,file:file,url:url) }
                else { self.writeFile(connection,file:file,url:url) }
            })
        } catch { closeFileResponse(connection,file:file,url:url) }
    }
    private func closeFileResponse(_ connection: NWConnection, file: FileHandle, url: URL) {
        try? file.close(); try? FileManager.default.removeItem(at:url); remove(connection); connection.cancel()
    }
    private func finish(_ id: String, error: Bool) {
        guard let transfer = transfers.removeValue(forKey:id) else { return }
        send(UpdateRelayPacket(action:"cancel",id:id)); try? transfer.handle.close(); try? FileManager.default.removeItem(at:transfer.file)
        if error { respondError(transfer.connection) }
    }
    private func respondError(_ connection: NWConnection) {
        connection.send(content:Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),completion:.contentProcessed { [weak self] _ in self?.remove(connection); connection.cancel() })
    }
}
#endif
