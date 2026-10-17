import Foundation
import Network
import CryptoKit
import Security

let nativePairingType = "_retina-pair._tcp"
let nativePairingPort: UInt16 = 58477

// Discovery is only a hint. Existing devices authenticate with their original
// random TLS PSK. First pairing uses committed X25519 keys and an eight-digit
// short authentication string that the owner must compare on BOTH displays.
// No credential is released until both local approvals are received.
struct NativePeer: Codable, Equatable {
    var role: String
    var id: String
    var name: String
    var username: String
    var fileVault: FileVaultState
    var version: String
    func validate(role expected:String) throws {
        guard role == expected, UUID(uuidString:id) != nil,
              !name.isEmpty, name.utf8.count <= 160,
              !name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),
              DeviceBinding.validUsername(username), version.utf8.count <= 40 else {
            throw LinkError.invalid("Invalid setup identity.")
        }
    }
    static func current(role:String,fileVault:FileVaultState = .unknown) -> NativePeer {
        let id: String
        if role == "host" { id = DeviceSettings.hostID }
        else if let saved = DeviceSettings.defaults.string(forKey:"nativeViewerID"), UUID(uuidString:saved) != nil { id = saved }
        else { id = UUID().uuidString; DeviceSettings.defaults.set(id,forKey:"nativeViewerID") }
        let name = String((Host.current().localizedName ?? (role == "host" ? "Mac" : "iMac"))
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(120))
        return NativePeer(role:role,id:id,name:name,username:NSUserName(),fileVault:fileVault,
                          version:ProcessInfo.processInfo.operatingSystemVersionString)
    }
}

func nativeJSON<T:Encodable>(_ item:T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try encoder.encode(item)
}

final class NativeExchange {
    let identity: NativePeer
    private let key = Curve25519.KeyAgreement.PrivateKey()
    private let nonce: Data
    var publicKey: Data { key.publicKey.rawRepresentation }
    var commitment: Data { Data(SHA256.hash(data:try! nativeJSON(identity)+publicKey+nonce)) }
    var reveal: (Data,Data) { (publicKey,nonce) }
    init(_ identity:NativePeer) {
        self.identity = identity
        var bytes = [UInt8](repeating:0,count:32)
        precondition(SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess)
        nonce = Data(bytes)
    }
    func finish(peer:NativePeer,commitment:Data,publicKey:Data,nonce:Data) throws -> NativeCipher {
        try peer.validate(role:identity.role == "host" ? "viewer" : "host")
        guard commitment.count == 32, publicKey.count == 32, nonce.count == 32,
              Data(SHA256.hash(data:try nativeJSON(peer)+publicKey+nonce)) == commitment else {
            throw LinkError.invalid("The setup identity changed. Cancel and try again.")
        }
        let own = try nativeJSON(identity)+self.publicKey+self.nonce
        let other = try nativeJSON(peer)+publicKey+nonce
        var transcript = Data("RetinaLink approved setup v1".utf8)
        for part in (identity.role == "host" ? [own,other] : [other,own]) {
            transcript.put32(UInt32(part.count)); transcript.append(part)
        }
        let hash = Data(SHA256.hash(data:transcript))
        let secret = try key.sharedSecretFromKeyAgreement(with:Curve25519.KeyAgreement.PublicKey(rawRepresentation:publicKey))
        func derived(_ label:String) -> SymmetricKey {
            secret.hkdfDerivedSymmetricKey(using:SHA256.self,salt:hash,sharedInfo:Data(label.utf8),outputByteCount:32)
        }
        let sas = Data(HMAC<SHA256>.authenticationCode(for:hash,using:derived("verification")))
        let number = sas.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 100_000_000
        return NativeCipher(send:derived(identity.role == "host" ? "host to viewer" : "viewer to host"),
            receive:derived(identity.role == "host" ? "viewer to host" : "host to viewer"),
            transcript:hash,code:String(format:"%04d %04d",number/10_000,number%10_000))
    }
}

struct NativeEnvelope: Codable { var counter:UInt64; var box:Data }
final class NativeCipher {
    let code:String
    private let sendKey:SymmetricKey, receiveKey:SymmetricKey, transcript:Data
    private var sent:UInt64 = 0, received:UInt64 = 0
    init(send:SymmetricKey,receive:SymmetricKey,transcript:Data,code:String) {
        sendKey = send; receiveKey = receive; self.transcript = transcript; self.code = code
    }
    private func aad(_ counter:UInt64)->Data { var data = transcript; data.put64(counter); return data }
    func seal<T:Encodable>(_ item:T) throws -> Data {
        guard sent < 16 else { throw LinkError.invalid("Setup message limit reached.") }
        sent += 1
        let box = try AES.GCM.seal(nativeJSON(item),using:sendKey,authenticating:aad(sent))
        return try nativeJSON(NativeEnvelope(counter:sent,box:box.combined!))
    }
    func open<T:Decodable>(_ data:Data,as:T.Type) throws -> T {
        guard data.count <= 16_384, received < 16 else { throw LinkError.invalid("Setup message limit reached.") }
        let envelope = try JSONDecoder().decode(NativeEnvelope.self,from:data)
        guard envelope.counter == received+1 else { throw LinkError.invalid("Replayed or unordered setup message.") }
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined:envelope.box),using:receiveKey,authenticating:aad(envelope.counter))
        let value = try JSONDecoder().decode(T.self,from:plain); received += 1; return value
    }
}

struct NativeSetupMessage: Codable {
    var step:String
    var identity:NativePeer? = nil
    var commitment:Data? = nil
    var publicKey:Data? = nil
    var nonce:Data? = nil
    var encrypted:Data? = nil
}
struct NativeEnrollment: Codable {
    var binding:DeviceBinding
    var credential:String
}
struct NativeSetupCommand: Codable {
    var action:String
    var enrollment:NativeEnrollment? = nil
}

// A tiny independent setup channel: limits apply BEFORE allocation or decoding.
// All state and callbacks live on the main queue. It never accepts file paths,
// shell commands, credentials for an OS account, or software uploads.
final class NativeSetupWire {
    let connection:NWConnection
    var onReady:(()->Void)?, onMessage:((NativeSetupMessage)->Void)?, onClose:((String)->Void)?, onWaiting:((String)->Void)?
    private(set) var closed = false
    private var count = 0
    init(_ connection:NWConnection) { self.connection = connection }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.closed else { return }
            switch state {
            case .ready: self.onReady?(); self.read()
            case .failed: self.cancel("Setup connection failed. Check the local network.")
            case .waiting:
                self.onWaiting?("Waiting for the local network. Allow Local Network access for RetinaLink if macOS asks, and keep Viewer open.")
            case .cancelled: self.cancel("Setup cancelled.")
            default: break
            }
        }
        connection.start(queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+120) { [weak self] in self?.cancel("Setup expired. Please try again.") }
    }
    func send(_ message:NativeSetupMessage,completion:(()->Void)? = nil) {
        guard !closed, let data = try? nativeJSON(message), data.count <= 16_384 else { return }
        var packet = Data(); packet.put32(UInt32(data.count)); packet.append(data)
        connection.send(content:packet,completion:.contentProcessed { [weak self] error in
            if error != nil { self?.cancel("Setup connection ended.") } else { completion?() }
        })
    }
    private func exact(_ count:Int,_ callback:@escaping(Data)->Void) {
        connection.receive(minimumIncompleteLength:count,maximumLength:count) { [weak self] data,_,_,error in
            guard let self = self, !self.closed else { return }
            guard error == nil, let data = data, data.count == count else { self.cancel("Setup connection ended."); return }
            callback(data)
        }
    }
    private func read() {
        exact(4) { [weak self] bytes in
            guard let self = self else { return }
            let length = bytes.reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= 16_384, self.count < 24 else { self.cancel("Invalid setup message."); return }
            self.count += 1
            self.exact(length) { [weak self] data in
                guard let self = self else { return }
                do { self.onMessage?(try JSONDecoder().decode(NativeSetupMessage.self,from:data)); if !self.closed { self.read() } }
                catch { self.cancel("Invalid setup message.") }
            }
        }
    }
    func cancel(_ reason:String) {
        guard !closed else { return }; closed = true
        connection.stateUpdateHandler = nil; connection.cancel(); onClose?(reason)
        onReady = nil; onMessage = nil; onClose = nil; onWaiting = nil
    }
}

// PairSession drives the same protocol on both roles. UI actions are local
// calls, never network commands. An approved peer cannot enroll until BOTH
// approvals are true; enrollment is single-use and tied to the committed IDs.
final class NativePairSession {
    let wire:NativeSetupWire, exchange:NativeExchange
    private(set) var peer:NativePeer?, cipher:NativeCipher?, localApproved = false, remoteApproved = false
    private var peerCommitment:Data?, stage = "initial", readyNotified = false, enrollmentSent = false
    var onVerify:((NativePeer,String)->Void)?, onBothApproved:(()->Void)?
    var onEnrollment:((NativeEnrollment)throws->Void)?, onCommitted:(()->Void)?, onClose:((String)->Void)?, onStatus:((String)->Void)?
    init(connection:NWConnection,identity:NativePeer) {
        wire = NativeSetupWire(connection); exchange = NativeExchange(identity)
    }
    func start() {
        wire.onReady = { [weak self] in
            guard let self = self, self.exchange.identity.role == "host" else { return }
            self.stage = "challenge"
            self.wire.send(NativeSetupMessage(step:"begin",identity:self.exchange.identity,commitment:self.exchange.commitment))
        }
        wire.onMessage = { [weak self] message in
            do { try self?.receive(message) } catch { self?.wire.cancel("Setup could not be verified. No existing pairing was replaced.") }
        }
        wire.onClose = { [weak self] reason in self?.onClose?(reason) }
        wire.onWaiting = { [weak self] message in self?.onStatus?(message) }
        wire.start()
    }
    private func receive(_ message:NativeSetupMessage) throws {
        let host = exchange.identity.role == "host"
        if !host, stage == "initial", message.step == "begin" {
            guard let identity = message.identity, let commitment = message.commitment, commitment.count == 32 else { throw LinkError.invalid("Missing commitment") }
            try identity.validate(role:"host"); peer = identity; peerCommitment = commitment; stage = "reveal"
            wire.send(NativeSetupMessage(step:"challenge",identity:exchange.identity,commitment:exchange.commitment))
        } else if host, stage == "challenge", message.step == "challenge" {
            guard let identity = message.identity, let commitment = message.commitment, commitment.count == 32 else { throw LinkError.invalid("Missing commitment") }
            try identity.validate(role:"viewer"); peer = identity; peerCommitment = commitment; stage = "reveal"
            wire.send(NativeSetupMessage(step:"reveal",publicKey:exchange.reveal.0,nonce:exchange.reveal.1))
        } else if stage == "reveal", message.step == "reveal" {
            guard let peer = peer, let commitment = peerCommitment, let publicKey = message.publicKey, let nonce = message.nonce else { throw LinkError.invalid("Missing reveal") }
            cipher = try exchange.finish(peer:peer,commitment:commitment,publicKey:publicKey,nonce:nonce)
            if !host { wire.send(NativeSetupMessage(step:"reveal",publicKey:exchange.reveal.0,nonce:exchange.reveal.1)) }
            stage = "verify"; onVerify?(peer,cipher!.code)
        } else if stage == "verify", message.step == "sealed", let encrypted = message.encrypted, let cipher = cipher {
            let command = try cipher.open(encrypted,as:NativeSetupCommand.self)
            switch command.action {
            case "approve":
                guard !remoteApproved, command.enrollment == nil else { throw LinkError.invalid("Duplicate approval") }
                remoteApproved = true; notifyBoth()
            case "enroll":
                guard !host, localApproved, remoteApproved, let request = command.enrollment,
                      request.binding.hostID == peer?.id, request.binding.username == exchange.identity.username,
                      request.binding.hostName == peer?.name, request.binding.viewerName == exchange.identity.name else { throw LinkError.invalid("Enrollment before approval") }
                try request.binding.validate()
                guard request.credential.count == 32, request.credential.allSatisfy({"0123456789ABCDEF".contains($0)}) else { throw LinkError.invalid("Invalid credential") }
                guard let apply = onEnrollment else { throw LinkError.invalid("Viewer enrollment handler unavailable") }
                try apply(request)
                stage = "committed"
                send(NativeSetupCommand(action:"committed")) { [weak self] in self?.onCommitted?() }
            case "committed":
                guard host, localApproved, remoteApproved, readyNotified, enrollmentSent else { throw LinkError.invalid("Unexpected commit") }
                stage = "committed"; onCommitted?()
            default: throw LinkError.invalid("Invalid setup action")
            }
        } else { throw LinkError.invalid("Out of order setup message") }
    }
    func approve() {
        guard stage == "verify", !localApproved else { return }
        localApproved = true; send(NativeSetupCommand(action:"approve")); notifyBoth()
    }
    private func notifyBoth() {
        if localApproved && remoteApproved && !readyNotified { readyNotified = true; onBothApproved?() }
    }
    func enroll(_ request:NativeEnrollment) {
        guard stage == "verify", !enrollmentSent, exchange.identity.role == "host", localApproved, remoteApproved, readyNotified else { return }
        enrollmentSent = true
        send(NativeSetupCommand(action:"enroll",enrollment:request))
    }
    private func send(_ command:NativeSetupCommand,completion:(()->Void)? = nil) {
        do {
            guard let cipher = cipher else { throw LinkError.invalid("No setup key") }
            wire.send(NativeSetupMessage(step:"sealed",encrypted:try cipher.seal(command)),completion:completion)
        } catch { wire.cancel("Secure setup could not finish.") }
    }
    func cancel() { wire.cancel("Setup cancelled. Existing pairing is unchanged.") }
}
