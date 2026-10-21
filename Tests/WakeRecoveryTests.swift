import Foundation
import Network

// No OS lock/sleep, production pairing, Keychain, capture or UI helpers. A real
// disposable TLS stream verifies orderly close versus transport failures.
func runWakeRecoveryTests() throws {
    var retry = ViewerReconnectPolicy()
    try check([retry.nextDelay(),retry.nextDelay(),retry.nextDelay(),retry.nextDelay()] == [0.25,0.75,1.5,3],
              "Brief interruptions retain the fixed first three-second wait")
    for _ in 0..<100 { try check(retry.nextDelay() == 3,"Sustained loss caused an unbounded fast-retry loop") }
    retry.resumed()
    try check(retry.nextDelay() == 0.25,"Rendered recovery/wake did not restore the bounded quick retry")

    let routes:[(key:String,rank:Int)] = [("working-usb",0),("untried-lan",10)]
    var policy = DirectLinkRoutePolicy()
    try check(policy.selectKey(from:routes,now:100) == "working-usb","Preferred cable was not selected")
    policy.succeeded("working-usb")
    policy.streamEnded("working-usb",wasStreaming:true)
    try check(policy.eligible("working-usb",now:100.25) && policy.selectKey(from:routes,now:100.25) == "working-usb",
              "A normal Host close delayed the healthy cable or selected an untried fallback first")
    policy.failed("working-usb",now:101)
    policy.streamEnded("working-usb",wasStreaming:true)
    try check(!policy.eligible("working-usb",now:101.25) && policy.selectKey(from:routes,now:101.25) == "untried-lan",
              "Orderly-close recovery erased an independently recorded transport failure")
    try check(policy.eligible("working-usb",now:131),"An actual failure's cooldown became indefinite")
    var stalled = DirectLinkRoutePolicy()
    _ = stalled.selectKey(from:routes,now:100)
    stalled.succeeded("working-usb"); stalled.streamEnded("working-usb",wasStreaming:false)
    try check(stalled.selectKey(from:routes,now:100.25) == "untried-lan",
              "A peer that closes before delivering frames starved every fallback route")
    print("PASS: bounded fast retry, reset after recovery, healthy-cable preference and retained physical-failure cooldown")

    let key = String(repeating:"A",count:32)
    let listener = try NWListener(using:networkParameters(key),on:.any)
    var listening = false, servers:[Link] = [], connections:[Link] = []
    var received = 0
    listener.stateUpdateHandler = { state in if case .ready = state { listening = true } }
    listener.newConnectionHandler = { connection in
        let peer = Link(connection); servers.append(peer)
        peer.onMessage = { [weak peer] type,data in
            if type == 77 { peer?.cancel() }
            else if type == 78 { peer?.send(type,data) }
        }
        peer.start()
    }
    listener.start(queue:.main)
    defer { listener.cancel(); servers.forEach {$0.cancel()}; connections.forEach {$0.cancel()} }
    try pump(until:{listening})

    let first = Link(NWConnection(host:"127.0.0.1",port:listener.port!,using:try networkParameters(key)))
    connections.append(first)
    var firstCause:Link.CloseCause?
    first.onReady = { [weak first] in first?.send(77,Data("close fixture".utf8)) }
    first.onClose = { [weak first] _ in
        let cause = first?.closeCause
        DispatchQueue.main.async { firstCause = cause }
    }
    first.start()
    try pump(until:{firstCause != nil})
    try check(firstCause == .peerClosed && firstCause?.penalizesRoute == false,
              "A real TLS peer's orderly close was classified as a bad network route")

    let second = Link(NWConnection(host:"127.0.0.1",port:listener.port!,using:try networkParameters(key)))
    connections.append(second)
    let token = Data(UUID().uuidString.utf8)
    second.onReady = { [weak second] in second?.send(78,token) }
    second.onMessage = { type,data in DispatchQueue.main.async { if type == 78 && data == token { received += 1 } } }
    second.start()
    try pump(until:{received == 1})
    var cancelled:Link.CloseCause?
    second.onClose = { [weak second] _ in
        let cause = second?.closeCause
        DispatchQueue.main.async { cancelled = cause }
    }
    second.cancel(reason:"Simulated confirmed USB removal",cause:.transportFailure)
    try pump(until:{cancelled != nil})
    try check(cancelled == .transportFailure && cancelled?.penalizesRoute == true,
              "A real local transport loss lost its route cooldown")

    // Retry still uses the saved-key TLS boundary, never an unencrypted fallback.
    let wrong = Link(NWConnection(host:"127.0.0.1",port:listener.port!,using:try networkParameters(String(repeating:"B",count:32))))
    connections.append(wrong)
    var wrongReady = false, wrongClosed = false
    wrong.onReady = { DispatchQueue.main.async { wrongReady = true } }
    wrong.onClose = { _ in DispatchQueue.main.async { wrongClosed = true } }
    wrong.start()
    try pump(until:{wrongClosed},timeout:18)
    try check(!wrongReady,"Reconnection accepted an untrusted TLS credential")
    print("PASS: actual TLS orderly-close classification, fresh encrypted reconnection, typed transport failure and wrong-key rejection")
}
