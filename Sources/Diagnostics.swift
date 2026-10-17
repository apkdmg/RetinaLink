import Foundation
import QuartzCore

enum LaunchOptions {
    static func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }
    static func value(_ flag: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }
    static let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
    static let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development"
}

// Opt-in metadata trace. Batches are written once per second off all hot queues.
// No pixels, credentials, addresses, window titles or packet contents are saved.
final class FrameTrace {
    static let shared = FrameTrace()
    let enabled: Bool
    private let queue = DispatchQueue(label:"retinalink.trace",qos:.utility)
    private var file: FileHandle?, timer: DispatchSourceTimer?
    private var pending: [[String:Any]] = [], count = 0
    private let limit = 250_000
    init() {
        guard let path = LaunchOptions.value("--trace-path") else {enabled=false;return}
        do {
            let url=URL(fileURLWithPath:path)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            FileManager.default.createFile(atPath:path,contents:nil,attributes:[.posixPermissions:0o600])
            file=try FileHandle(forWritingTo:url);file?.truncateFile(atOffset:0)
            enabled=true
            let timer=DispatchSource.makeTimerSource(queue:queue)
            timer.schedule(deadline:.now()+1,repeating:1)
            timer.setEventHandler {[weak self] in self?.flush()};self.timer=timer;timer.resume()
        } catch {enabled=false;fputs("RetinaLink trace unavailable: \(error)\n",stderr);return}
        event("trace_start",fields:["version":LaunchOptions.version,"build":LaunchOptions.build,"pid":ProcessInfo.processInfo.processIdentifier])
    }
    func event(_ name:String,sequence:UInt64?=nil,fields:@autoclosure ()->[String:Any]=[:]) {
        guard enabled else{return}
        var item=fields()
        for (key,value) in item {if let number=value as? Double,!number.isFinite {item[key]=NSNull()}}
        item["event"]=name;item["t"]=CACurrentMediaTime();item["wall"]=Date().timeIntervalSince1970
        if let sequence=sequence {item["seq"]=sequence}
        queue.async {[self] in
            guard count<limit else{return};count += 1;pending.append(item)
            if count==limit {pending.append(["event":"trace_limit","t":CACurrentMediaTime()]);flush()}
        }
    }
    private func flush() {
        guard !pending.isEmpty,let file=file else{return}
        if var bytes=try? JSONSerialization.data(withJSONObject:pending,options:[.sortedKeys]) {bytes.append(10);file.write(bytes)}
        pending.removeAll(keepingCapacity:true)
    }
}

// Timing/state only: no pairing credentials, screen pixels, window titles or addresses.
// A bounded snapshot is written off the capture/render queues and can be fetched over SSH.
final class DiagnosticLog {
    static let shared = DiagnosticLog()
    private let queue = DispatchQueue(label: "retinalink.diagnostics", qos: .utility)
    private var samples: [[String: Any]] = []
    private let path: String
    init() {
        let role = Bundle.main.bundleIdentifier?.hasSuffix("Host") == true ? "Host" : "Viewer"
        path = LaunchOptions.value("--diagnostics-path") ?? NSHomeDirectory() + "/Library/Logs/RetinaLink/" + role + ".json"
    }
    func record(_ kind: String, _ text: String) {
        let now = Date().timeIntervalSince1970, uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            samples.append(["time": now, "uptime": uptime, "kind": kind, "text": text])
            if samples.count > 120 { samples.removeFirst(samples.count - 120) }
            let snapshot: [String: Any] = ["version": LaunchOptions.version, "build": LaunchOptions.build,
                "os": ProcessInfo.processInfo.operatingSystemVersionString, "pid": ProcessInfo.processInfo.processIdentifier,
                "samples": samples]
            do {
                let url = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            } catch { fputs("RetinaLink diagnostics write failed: \(error)\n", stderr) }
        }
    }
}

final class StreamingActivity {
    private var token: NSObjectProtocol?
    init() {
        if !LaunchOptions.has("--no-streaming-activity") {
            var options: ProcessInfo.ActivityOptions = [.userInitiatedAllowingIdleSystemSleep,.idleDisplaySleepDisabled]
            #if HOST
            // This live capture/encode session needs precise timer and I/O scheduling.
            if !LaunchOptions.has("--standard-activity") { options.insert(.latencyCritical) }
            #else
            if LaunchOptions.has("--latency-critical") { options.insert(.latencyCritical) }
            #endif
            token = ProcessInfo.processInfo.beginActivity(options: options, reason: "Interactive extended display")
        }
    }
    deinit { if let token = token { ProcessInfo.processInfo.endActivity(token) } }
}
