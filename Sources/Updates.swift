import AppKit
import Sparkle

struct SoftwareUpdateStatus: Codable {
    var version: String
    var build: String
    var automatic: Bool
    var configured: Bool
    var phase: String
    var message: String
    var targetBuild: String? = nil
    var targetVersion: String? = nil
    var viaHost: Bool? = nil
    var fullscreen: Bool? = nil
}

struct SoftwareUpdateCommand: Codable {
    var action: String
    var automatic: Bool?
    // Local integration tests only. Peer messages cannot change public feeds.
    var testBaseURL: String?
    var relayVersion: Int? = nil
}

enum UpdateSettings {
    static func isNoUpdate(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == SUSparkleErrorDomain && value.code == SUError.noUpdateError.rawValue
    }
    static let testKey = "RetinaLink.localUpdateTestBaseURL"
    static let relaunchKey = "RetinaLink.updateRelaunchPending"
    static var automatic: Bool { UserDefaults.standard.object(forKey:"SUEnableAutomaticChecks") as? Bool ?? true }
    static func validTestBase(_ text: String) -> Bool {
        guard let url = URLComponents(string:text) else { return false }
        return url.scheme == "http" && url.host == "127.0.0.1" && url.port != nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil && (url.path.isEmpty || url.path == "/")
    }
    static var testBase: String? {
        guard let value = UserDefaults.standard.string(forKey:testKey), validTestBase(value) else { return nil }
        return value.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
    }
    static var role: String {
        #if HOST
        return "Host"
        #else
        return "Viewer"
        #endif
    }
    static var feed: URL? {
        if let base = testBase { return URL(string:base+"/"+role.lowercased()+"/appcast.xml") }
        guard let value = Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String,
              let url = URL(string:value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func applyLaunchOptions() {
        if let url = LaunchOptions.value("--test-update-base-url"), validTestBase(url) {
            UserDefaults.standard.set(url,forKey:testKey)
        }
        if LaunchOptions.has("--clear-update-test-base-url") { UserDefaults.standard.removeObject(forKey:testKey) }
    }
    // Sparkle relaunches via Launch Services. Return to our existing login
    // agent so later crashes still recover, without changing its arguments.
    static func returnToStartupAgentIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey:relaunchKey) else { return false }
        defaults.removeObject(forKey:relaunchKey); defaults.synchronize()
        let label = "local.retinalink."+role.lowercased()+".startup"
        guard ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != label,
              let data = try? Data(contentsOf:StartupAgent.path(role:role)),
              let agent = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
              let arguments = agent["ProgramArguments"] as? [String],
              arguments.first == Bundle.main.executablePath else { return false }
        let target = "gui/\(getuid())/"+label
        var result = try? SystemTask.run("/bin/launchctl",["kickstart",target],timeout:10)
        if result?.status != 0 {
            result = try? SystemTask.run("/bin/launchctl",["bootstrap","gui/\(getuid())",StartupAgent.path(role:role).path],timeout:10)
        }
        guard result?.status == 0 else { return false }
        DiagnosticLog.shared.record("update","Returning updated app to its existing startup agent")
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
}

final class AutomaticUpdater: NSObject, SPUUpdaterDelegate {
    private var updater: SPUUpdater?
    private var driver: QuietUpdateDriver?
    private var started = false
    private var manualInstall = false
    private var pendingInstall: (() -> Void)?
    private var queuedCheck: Bool?
    private var retryCheck: DispatchWorkItem?
    private var targetBuild: String?, targetVersion: String?
    #if !HOST
    private(set) var relay: ViewerUpdateRelay?
    private var relayFeed: URL?
    private var relayStarting = false
    private var requiresRelay = false
    func attachRelay(_ peer: Link) {
        detachRelay(); requiresRelay = true; relayStarting = true
        let relay = ViewerUpdateRelay(peer:peer); self.relay = relay
        relay.onReady = { [weak self,weak relay] url in
            guard let self = self, self.relay === relay else { return }
            self.relayFeed = url; self.relayStarting = false; self.start()
            if UserDefaults.standard.bool(forKey:"RetinaLink.resumeViewerUpdate") { self.check(installNow:true) }
            else if UpdateSettings.automatic { self.check() }
        }
        relay.onProgress = { [weak self,weak relay] fraction in
            guard let self = self, self.relay === relay else { return }
            self.publish("transferring","Receiving from your main Mac · \(Int(fraction * 100))%")
        }
        do { try relay.start() } catch { relayStarting = false; failed(error) }
    }
    func detachRelay() { relay?.stop(); relay = nil; relayFeed = nil; relayStarting = false }
    func confirmDisplayReconnected(fullscreen: Bool) {
        publish("reconnected","RetinaLink \(LaunchOptions.version) (\(LaunchOptions.build)) · display reconnected.",fullscreen:fullscreen)
    }
    #endif
    var onChange: ((SoftwareUpdateStatus) -> Void)?
    private(set) var status = SoftwareUpdateStatus(version:LaunchOptions.version,build:LaunchOptions.build,
        automatic:UpdateSettings.automatic,configured:false,phase:"starting",message:"Preparing automatic updates…")

    func start() {
        #if !HOST
        if relayStarting { return }
        #endif
        guard DistributionTrust.team != nil else { publish("unavailable","Automatic updates require the signed release."); return }
        guard UpdateSettings.feed != nil else { publish("not-configured","Update service will be available after release hosting is configured."); return }
        guard !started else { return }
        let driver = QuietUpdateDriver(owner:self); self.driver = driver
        let updater = SPUUpdater(hostBundle:Bundle.main,applicationBundle:Bundle.main,userDriver:driver,delegate:self)
        self.updater = updater
        do {
            try updater.start(); started = true
            publish("ready",UpdateSettings.automatic ? "Automatic updates are on. Both Macs stay paired." : "Automatic updates are off.")
        } catch { failed(error) }
    }
    func setAutomatic(_ enabled: Bool) {
        let changed = UpdateSettings.automatic != enabled
        UserDefaults.standard.set(enabled,forKey:"SUEnableAutomaticChecks")
        UserDefaults.standard.set(enabled,forKey:"SUAutomaticallyUpdate")
        updater?.automaticallyChecksForUpdates = enabled
        updater?.automaticallyDownloadsUpdates = enabled
        if enabled { start() }
        if changed || status.phase == "starting" {
            if UpdateSettings.feed == nil { publish("not-configured","Update service will be available after release hosting is configured.") }
            else if updater?.sessionInProgress != true { publish("ready",enabled ? "Automatic updates are on. Both Macs stay paired." : "Automatic updates are off.") }
        }
    }
    func configureTestBase(_ value: String?) {
        if let value = value, UpdateSettings.validTestBase(value) { UserDefaults.standard.set(value,forKey:UpdateSettings.testKey) }
        else if value == "" { UserDefaults.standard.removeObject(forKey:UpdateSettings.testKey) }
        UserDefaults.standard.synchronize()
        if UpdateSettings.feed == nil { updater?.automaticallyChecksForUpdates = false }
        start()
        publish(UpdateSettings.feed == nil ? "not-configured" : "ready",UpdateSettings.feed == nil ? "Update hosting is not configured." : "Update service is ready.")
    }
    func check(installNow: Bool = false) {
        #if !HOST
        if installNow { UserDefaults.standard.set(true,forKey:"RetinaLink.resumeViewerUpdate") }
        if relayStarting { queuedCheck = (queuedCheck ?? false) || installNow; return }
        #endif
        start()
        guard let updater = updater, started, UpdateSettings.feed != nil else { return }
        guard !updater.sessionInProgress else {
            queuedCheck = (queuedCheck ?? false) || installNow
            if installNow { manualInstall = true }
            scheduleQueuedCheck(); return
        }
        retryCheck?.cancel(); retryCheck = nil; queuedCheck = nil
        manualInstall = installNow
        publish("checking","Checking for signed updates…")
        if installNow { updater.checkForUpdates() }
        else { updater.checkForUpdatesInBackground() }
    }
    private func scheduleQueuedCheck() {
        retryCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let install = self.queuedCheck else { return }
            if self.updater?.sessionInProgress == true { self.scheduleQueuedCheck() }
            else { self.check(installNow:install) }
        }
        retryCheck = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
    }
    func publish(_ phase: String, _ message: String, fullscreen: Bool? = nil) {
        status = SoftwareUpdateStatus(version:LaunchOptions.version,build:LaunchOptions.build,
            automatic:UpdateSettings.automatic,configured:UpdateSettings.feed != nil,phase:phase,message:message,
            targetBuild:targetBuild,targetVersion:targetVersion,viaHost:usingRelay,fullscreen:fullscreen)
        #if !HOST
        if phase == "up-to-date" { UserDefaults.standard.removeObject(forKey:"RetinaLink.resumeViewerUpdate") }
        #endif
        DiagnosticLog.shared.record("update",phase+": "+message)
        if let data = try? JSONEncoder().encode(status) {
            let path = NSHomeDirectory()+"/Library/Logs/RetinaLink/"+UpdateSettings.role+"-updates.json"
            try? data.write(to:URL(fileURLWithPath:path),options:.atomic)
            try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path)
        }
        onChange?(status)
    }
    fileprivate var mayInstall: Bool { UpdateSettings.automatic || manualInstall }
    fileprivate func failed(_ error: Error) {
        // Sparkle also delivers the normal "already up to date" outcome to
        // abort/user-driver callbacks. Never present it as an update failure.
        if UpdateSettings.isNoUpdate(error) { publish("up-to-date","RetinaLink is up to date."); return }
        pendingInstall = nil
        publish("error","Update could not finish. Your current version and pairing are kept; it will retry later.")
        DiagnosticLog.shared.record("update-error",String(describing:error).prefix(1500).description)
    }
    fileprivate func installing() {
        UserDefaults.standard.set(true,forKey:UpdateSettings.relaunchKey); UserDefaults.standard.synchronize()
        publish("installing","Installing a verified update. Your display will reconnect automatically.")
    }
    private var usingRelay: Bool {
        #if HOST
        return false
        #else
        return requiresRelay
        #endif
    }
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if !HOST
        if requiresRelay { return relayFeed?.absoluteString ?? "http://127.0.0.1:9/unavailable" }
        #endif
        return UpdateSettings.feed?.absoluteString
    }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        #if !HOST
        if requiresRelay {
            // An unrecognized enclosure fails closed on loopback. Sparkle still
            // verifies the original signed item's length/signature afterwards.
            request.url = request.url.flatMap { relay?.archiveURL($0) } ?? URL(string:"http://127.0.0.1:9/unavailable.zip")!
            DiagnosticLog.shared.record("update-route","Viewer archive download uses loopback over the trusted Host connection")
        }
        #endif
    }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
    func updaterShouldPromptForPermission(toCheckForUpdates updater: SPUUpdater) -> Bool { false }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard UpdateSettings.feed != nil else { throw LinkError.invalid("Release hosting is not configured.") }
        #if !HOST
        if requiresRelay && relayFeed == nil { throw LinkError.invalid("Waiting for your main Mac to send the update.") }
        #endif
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        targetBuild = item.versionString; targetVersion = item.displayVersionString
        publish("available","RetinaLink \(item.displayVersionString) is available. Pairing will be preserved.")
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { installing() }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { failed(error) }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock handler: @escaping () -> Void) -> Bool {
        pendingInstall = handler
        publish("downloaded","Verified update ready. Reconnecting your display shortly…")
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in
            guard let self = self, self.mayInstall, let install = self.pendingInstall else { return }
            self.pendingInstall = nil; self.installing(); install()
        }
        return true
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if pendingInstall == nil { manualInstall = false }
        if let error = error {
            if UpdateSettings.isNoUpdate(error) { publish("up-to-date","RetinaLink is up to date.") }
            else { failed(error) }
        }
        if queuedCheck != nil { scheduleQueuedCheck() }
    }
}

// Viewer never requires a mouse or keyboard for updater dialogs. Host exposes
// the shared opt-out and an explicit Update Now action. Sparkle still performs
// feed/archive signature verification, safe extraction and atomic installation.
private final class QuietUpdateDriver: NSObject, SPUUserDriver {
    weak var owner: AutomaticUpdater?
    init(owner: AutomaticUpdater) { self.owner = owner }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks:UpdateSettings.automatic,automaticUpdateDownloading:NSNumber(value:UpdateSettings.automatic),sendSystemProfile:false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !appcastItem.isInformationOnlyUpdate, owner?.mayInstall == true else { reply(.dismiss); return }
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { owner?.publish("up-to-date","RetinaLink is up to date."); acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { owner?.failed(error); acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { owner?.publish("downloading","Downloading a signed RetinaLink update…") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { owner?.publish("verifying","Verifying update before installation…") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard owner?.mayInstall == true else { reply(.dismiss); return }; owner?.installing(); reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
