import Foundation

// Keep identifiers and the Keychain namespace stable across Developer ID
// releases. Do not pin one certificate hash: Apple may renew it for the team.
enum DistributionTrust {
    static let namespace = "local.retinalink.device-trust"
    static func validTeam(_ team: String) -> Bool {
        team.utf8.count == 10 && team.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }
    static var team: String? {
        guard let team = Bundle.main.object(forInfoDictionaryKey:"RetinaLinkSigningTeam") as? String,
              validTeam(team), DeviceVault.service == namespace else { return nil }
        return team
    }
    static func requirement(team: String, role: String) throws -> String {
        guard validTeam(team), ["Host","Viewer"].contains(role) else { throw LinkError.invalid("Invalid release signing identity.") }
        return "anchor apple generic and identifier \"local.retinalink.\(role)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
    }
}

struct DeviceSoftwareStatus: Codable {
    var hostID: String?
    var namespace: String
    var team: String?
    var version: String
    var build: String
    var startupAtLogin: Bool
    static func current() -> DeviceSoftwareStatus {
        DeviceSoftwareStatus(hostID:DeviceSettings.binding?.hostID,namespace:DeviceVault.service,team:DistributionTrust.team,
            version:LaunchOptions.version,build:LaunchOptions.build,
            startupAtLogin:FileManager.default.fileExists(atPath:StartupAgent.path(role:"Viewer").path))
    }
    func validateUpdate(hostID: String, team: String) throws {
        guard DistributionTrust.validTeam(team), self.team == team, namespace == DistributionTrust.namespace else {
            throw LinkError.invalid("This display uses a development build or a different developer identity. Complete Display Setup once to move it to signed releases. Future signed updates preserve pairing.")
        }
        guard self.hostID == hostID else { throw LinkError.invalid("This display is not paired with this Host. Use Display Setup instead.") }
    }
}
