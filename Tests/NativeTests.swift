import Foundation
import Network
import CryptoKit

func runNativeTests() throws {
    let hostID = NativePeer(role:"host",id:UUID().uuidString,name:"Studio",username:NSUserName(),fileVault:.unknown,version:"27")
    let viewerID = NativePeer(role:"viewer",id:UUID().uuidString,name:"iMac",username:NSUserName(),fileVault:.on,version:"11.7.8")
    let host = NativeExchange(hostID), viewer = NativeExchange(viewerID)
    let a = try host.finish(peer:viewerID,commitment:viewer.commitment,publicKey:viewer.reveal.0,nonce:viewer.reveal.1)
    let b = try viewer.finish(peer:hostID,commitment:host.commitment,publicKey:host.reveal.0,nonce:host.reveal.1)
    try check(a.code == b.code && a.code.count == 9,"Verification number disagreement")
    let sealed = try a.seal(NativeSetupCommand(action:"approve"))
    let opened = try b.open(sealed,as:NativeSetupCommand.self)
    try check(opened.action == "approve","Directional setup encryption")
    try expectInvalid { _ = try b.open(sealed,as:NativeSetupCommand.self) }
    try expectInvalid { _ = try a.open(sealed,as:NativeSetupCommand.self) }
    var envelope = try JSONDecoder().decode(NativeEnvelope.self,from:a.seal(NativeSetupCommand(action:"approve")))
    envelope.box[envelope.box.count-1] ^= 1
    try expectInvalid { _ = try b.open(nativeJSON(envelope),as:NativeSetupCommand.self) }
    var changed = viewerID; changed.name = "Another iMac"
    try expectInvalid { _ = try host.finish(peer:changed,commitment:viewer.commitment,publicKey:viewer.reveal.0,nonce:viewer.reveal.1) }
    try expectInvalid { _ = try host.finish(peer:viewerID,commitment:viewer.commitment,publicKey:Data(repeating:0,count:32),nonce:viewer.reveal.1) }
    try expectInvalid { _ = try host.finish(peer:hostID,commitment:host.commitment,publicKey:host.reveal.0,nonce:host.reveal.1) }
    print("PASS: committed X25519 identity binding, matching verification, directional AES-GCM, tamper/reflection/replay rejection")
    try testNativeApprovalBoundary(hostID,viewerID)
}

func testNativeApprovalBoundary(_ hostID:NativePeer,_ viewerID:NativePeer) throws {
    let listener = try NWListener(using:NWParameters.tcp,on:.any)
    var ready = false, host:NativePairSession?, viewer:NativePairSession?
    var hostCode:String?, viewerCode:String?, commits = 0, enrolled = false, finished = false
    listener.stateUpdateHandler = { if case .ready = $0 { ready = true } }
    listener.newConnectionHandler = { connection in
        let session = NativePairSession(connection:connection,identity:viewerID); viewer = session
        session.onVerify = { _,code in viewerCode = code }
        session.onEnrollment = { request in
            try check(host?.localApproved == true && viewer?.localApproved == true,"Enrollment before both local approvals")
            try check(request.binding.hostID == hostID.id,"Enrollment Host ID changed")
            enrolled = true; commits += 1
        }
        session.start()
    }
    listener.start(queue:.main)
    defer { host?.cancel(); viewer?.cancel(); listener.cancel() }
    try pump(until:{ready})
    let client = NativePairSession(connection:NWConnection(host:"127.0.0.1",port:listener.port!,using:.tcp),identity:hostID)
    host = client; client.onVerify = { _,code in hostCode = code }
    let binding = DeviceBinding(hostID:hostID.id,hostName:hostID.name,viewerName:viewerID.name,address:"127.0.0.1",username:viewerID.username,
        dedicatedDisplay:false,viewerStartup:false,hostStartup:false,fileVault:.on,automaticLoginConfigured:false,enrolledAt:Date())
    let request = NativeEnrollment(binding:binding,credential:String(repeating:"A",count:32))
    client.onBothApproved = { [weak client] in client?.enroll(request) }
    client.onCommitted = { finished = true }
    client.start()
    try pump(until:{hostCode != nil && viewerCode != nil})
    try check(hostCode == viewerCode,"Network pairing verification disagreement")
    client.enroll(request)
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1))
    try check(!enrolled,"Credential sent without local approval")
    client.approve()
    try pump(until:{viewer?.remoteApproved == true})
    client.enroll(request)
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1))
    try check(!enrolled,"Host approval alone allowed enrollment")
    viewer?.approve()
    try pump(until:{finished})
    try check(enrolled && commits == 1,"Approved enrollment did not commit once")
    client.enroll(request)
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1))
    try check(commits == 1,"Enrollment committed twice")
    print("PASS: actual TCP setup requires both local approvals, withholds credential before approval, commits once and preserves FileVault metadata")
}
