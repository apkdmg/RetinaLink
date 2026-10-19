import Foundation
import Network
import Sparkle

func runUpdateRelayTests() throws {
    try check(UpdateSettings.isNoUpdate(NSError(domain:SUSparkleErrorDomain,code:Int(SUError.noUpdateError.rawValue))),"Normal no-update outcome was classified as failure")
    try check(!UpdateSettings.isNoUpdate(NSError(domain:"AnotherErrorDomain",code:Int(SUError.noUpdateError.rawValue))),"Unrelated error was hidden as no-update")
    try check(!UpdateSettings.isNoUpdate(NSError(domain:SUSparkleErrorDomain,code:4005)),"Signature failure was hidden as no-update")
    let good = URL(string:"https://github.com/apkdmg/RetinaLink/releases/download/v0.8.3/RetinaLink-Viewer-0.8.3-64.zip")!
    try check(UpdateRelayPolicy.archiveAllowed(good,testBase:nil),"Pinned Viewer archive rejected")
    for text in [
        "http://github.com/apkdmg/RetinaLink/releases/download/v0.8.3/RetinaLink-Viewer-0.8.3-64.zip",
        "https://github.com/another/RetinaLink/releases/download/v0.8.3/RetinaLink-Viewer-0.8.3-64.zip",
        "https://github.com/apkdmg/RetinaLink/releases/download/v0.8.3/RetinaLink-Host-0.8.3-64.zip",
        good.absoluteString+"?redirect=evil", good.absoluteString+"#fragment",
        "http://127.0.0.1:1234/viewer/RetinaLink-Viewer-0.8.3-64.zip",
        "https://example.com/RetinaLink-Viewer-0.8.3-64.zip", "file:///tmp/RetinaLink-Viewer-0.8.3-64.zip"
    ] { try check(!UpdateRelayPolicy.archiveAllowed(URL(string:text)!,testBase:nil),"Untrusted relay archive accepted: "+text) }
    try check(UpdateRelayPolicy.archiveAllowed(URL(string:"http://127.0.0.1:1234/viewer/RetinaLink-Viewer-0.8.3-64.zip")!,testBase:"http://127.0.0.1:1234"),"Explicit loopback fixture rejected")
    try check(!UpdateRelayPolicy.redirectAllowed(URL(string:"http://127.0.0.1/private")!,original:good),"Redirect reached a private or plaintext address")
    try check(!UpdateRelayPolicy.redirectAllowed(URL(string:"https://example.com/file")!,original:good),"Redirect reached an arbitrary site")
    try check(UpdateRelayPolicy.redirectAllowed(URL(string:"https://release-assets.githubusercontent.com/file?signature=fixture")!,original:good),"GitHub asset redirect rejected")
    for (installed,target,full,expected) in [("64","64",true,true),("65","64",true,true),("63","64",true,false),("64","64",false,false),("invalid","64",true,false),("64","-1",true,false)] {
        try check(UpdateRelayPolicy.confirmed(installed:installed,target:target,fullscreen:full)==expected,"Unconfirmed Viewer update reported as completed")
    }
    try check(UpdateRelayPacket.decode(Data("{\"action\":\"fetch\",\"id\":\"invalid\"}".utf8)) == nil,"Non-UUID transfer accepted")
    try check(UpdateRelayPacket.decode(Data(repeating:0,count:100_000)) == nil,"Oversized relay control accepted")
    let legacy = try JSONDecoder().decode(Hello.self,from:Data("{\"version\":1,\"bc7\":true,\"name\":\"legacy\"}".utf8))
    try check(legacy.updateRelay == nil,"Legacy peer acquired relay capability")
    print("PASS: relay origin/redirect allowlists, bounded controls, legacy negotiation and actual-version/fullscreen completion")
    #if !HOST
    try testUpdateRelayRoundTrip()
    #endif
}

#if !HOST
func testUpdateRelayRoundTrip() throws {
    let fixture = Data((0..<700_000).map { UInt8($0 % 251) })
    let http = try NWListener(using:.tcp,on:.any)
    var httpReady = false, ready = false, host: Link?, relayHost: HostUpdateRelay?, relayViewer: ViewerUpdateRelay?
    var sourceRequests = 0, responses: [Data] = [], codes: [Int] = []
    http.stateUpdateHandler = { if case .ready = $0 { httpReady = true } }
    http.newConnectionHandler = { connection in
        connection.start(queue:.main)
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) { _,_,_,_ in DispatchQueue.main.async {
            sourceRequests += 1
            var data = Data("HTTP/1.1 200 OK\r\nContent-Length: \(fixture.count)\r\nConnection: close\r\n\r\n".utf8); data.append(fixture)
            connection.send(content:data,completion:.contentProcessed { _ in connection.cancel() })
        } }
    }
    http.start(queue:.main); defer { http.cancel() }
    try pump(until:{httpReady})
    let source = URL(string:"http://127.0.0.1:\(http.port!.rawValue)/appcast.xml")!
    let code = UUID().uuidString
    let listener = try NWListener(using:networkParameters(code),on:.any)
    listener.stateUpdateHandler = { if case .ready = $0 { ready = true } }
    listener.newConnectionHandler = { connection in
        let peer = Link(connection); host = peer
        relayHost = HostUpdateRelay(peer:peer,feed:source)
        peer.onMessage = { type,data in if type == UpdateRelayPolicy.message { relayHost?.receive(data) } }
        peer.start()
    }
    listener.start(queue:.main); defer { listener.cancel(); host?.cancel(); relayHost?.stop(); relayViewer?.stop() }
    try pump(until:{ready})
    let peer = Link(NWConnection(host:"127.0.0.1",port:listener.port!,using:try networkParameters(code)))
    peer.onMessage = { type,data in if type == UpdateRelayPolicy.message { relayViewer?.receive(data) } }
    var url: URL?
    peer.onReady = { DispatchQueue.main.async {
        let relay = ViewerUpdateRelay(peer:peer); relayViewer = relay
        relay.onReady = { url = $0 }; try? relay.start()
    } }
    peer.start(); defer { peer.cancel() }
    try pump(until:{url != nil})
    let session = URLSession(configuration:.ephemeral); defer { session.invalidateAndCancel() }
    func get(_ target: URL) {
        session.dataTask(with:target) { data,response,_ in DispatchQueue.main.async {
            responses.append(data ?? Data()); codes.append((response as? HTTPURLResponse)?.statusCode ?? 0)
        } }.resume()
    }
    get(url!); try pump(until:{responses.count==1},timeout:30)
    try check(responses[0] == fixture && codes[0] == 200 && sourceRequests == 1,"Relay changed signed bytes or lost chunk order")
    let bad = url!.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("wrong-token/appcast.xml")
    get(bad); try pump(until:{responses.count==2})
    try check(codes[1]==502 && sourceRequests==1,"Unauthenticated loopback request reached Host")
    print("PASS: exact 700 KB signed-byte fixture over encrypted display link, pull-based 64 KiB chunks, token rejection and loopback HTTP")
}
#endif
