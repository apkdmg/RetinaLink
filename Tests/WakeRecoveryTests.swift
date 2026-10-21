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
    var restarting = DirectLinkRoutePolicy()
    _ = restarting.selectKey(from:[("only-cable",0)],now:100)
    restarting.streamEnded("only-cable",wasStreaming:true)
    let refusal = Link.CloseCause.network(.posix(.ECONNREFUSED))
    if refusal.penalizesRoute { restarting.failed("only-cable",now:100.25) }
    restarting.streamEnded("only-cable",wasStreaming:false)
    try check(refusal == .connectionRefused && restarting.selectKey(from:[("only-cable",0)],now:101) == "only-cable",
              "A quick retry before Host reopened its port blocked the only cable for 30 seconds")
    try check(Link.CloseCause.network(.posix(.ENETDOWN)).penalizesRoute &&
              Link.CloseCause.network(.tls(-9807)).penalizesRoute,
              "Temporary-port recovery removed real network/authentication cooldowns")
    print("PASS: bounded fast retry, reset after recovery, healthy-cable preference and retained physical-failure cooldown")

    let key = String(repeating:"A",count:32)
    let parameters = try networkParameters(key); parameters.allowLocalEndpointReuse = true
    let listener = try NWListener(using:parameters,on:.any)
    var listening = false, stopped = false, servers:[Link] = [], connections:[Link] = []
    var received = 0
    listener.stateUpdateHandler = { state in
        if case .ready = state { listening = true }
        if case .cancelled = state { stopped = true }
    }
    let accept:(NWConnection)->Void = { connection in
        let peer = Link(connection); servers.append(peer)
        peer.onMessage = { [weak peer] type,data in
            if type == 77 { peer?.cancel() }
            else if type == 78 { peer?.send(type,data) }
        }
        peer.start()
    }
    listener.newConnectionHandler = accept
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

    // Reproduce the Host's listener teardown window without sleeping either
    // Mac: the client arrives before the same port starts listening again.
    let port = listener.port!
    listener.cancel(); try pump(until:{stopped})
    let early = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(key)))
    connections.append(early)
    var earlyCause:Link.CloseCause?
    early.onClose = { [weak early] _ in
        let cause = early?.closeCause
        DispatchQueue.main.async { earlyCause = cause }
    }
    early.start(); try pump(until:{earlyCause != nil},timeout:18)
    try check(earlyCause == .connectionRefused && earlyCause?.penalizesRoute == false,
              "A real connection refused by a restarting listener was treated as a bad cable")
    let restartParameters = try networkParameters(key); restartParameters.allowLocalEndpointReuse = true
    let restarted = try NWListener(using:restartParameters,on:port)
    var restartedReady = false, resumed = false
    restarted.stateUpdateHandler = { if case .ready = $0 { restartedReady = true } }
    restarted.newConnectionHandler = accept
    restarted.start(queue:.main); defer { restarted.cancel() }
    try pump(until:{restartedReady})
    let recovered = Link(NWConnection(host:"127.0.0.1",port:port,using:try networkParameters(key)))
    connections.append(recovered)
    recovered.onReady = { [weak recovered] in recovered?.send(78,token) }
    recovered.onMessage = { type,data in DispatchQueue.main.async { if type == 78 && data == token { resumed = true } } }
    recovered.start(); try pump(until:{resumed})
    print("PASS: actual refused connection during listener restart, same-port encrypted recovery and no spurious 30-second cooldown")
}
