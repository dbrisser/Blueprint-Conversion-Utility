import Foundation

struct AppSettings: Codable, Equatable {
    var platformURL = "https://us.api.jamfcloud.com"
    var platformClientID = ""
    var environmentID = ""
    var tenantID = ""

    enum CodingKeys: String, CodingKey {
        case platformURL, platformClientID, environmentID, tenantID
    }

    init() { }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        platformURL = try values.decodeIfPresent(String.self, forKey: .platformURL)
            ?? "https://us.api.jamfcloud.com"
        platformClientID = try values.decodeIfPresent(String.self, forKey: .platformClientID) ?? ""
        environmentID = try values.decodeIfPresent(String.self, forKey: .environmentID) ?? ""
        tenantID = try values.decodeIfPresent(String.self, forKey: .tenantID) ?? ""
    }
}


struct ProfileScope: Hashable {
    var allDevices = false
    var groupNames: [String] = []
    var individualDeviceCount = 0
    var limitationCount = 0
    var exclusionCount = 0

    var summary: String {
        var parts: [String] = []
        if allDevices { parts.append("all devices") }
        if !groupNames.isEmpty { parts.append("\(groupNames.count) group(s)") }
        if individualDeviceCount > 0 { parts.append("\(individualDeviceCount) individual device(s)") }
        if limitationCount > 0 { parts.append("\(limitationCount) limitation(s)") }
        if exclusionCount > 0 { parts.append("\(exclusionCount) exclusion(s)") }
        return parts.isEmpty ? "Unscoped" : parts.joined(separator: ", ")
    }
}

struct JamfProfile: Identifiable, Hashable {
    let id: String
    let name: String
    var description = ""
    var payloads: [[String: Any]] = []
    var scope = ProfileScope()

    static func == (lhs: JamfProfile, rhs: JamfProfile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum DeviceGroupFamily: String, Hashable { case computer, mobile, unknown }
struct DeviceGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let family: DeviceGroupFamily
}

enum DeploymentChoice: String, Identifiable {
    case createOnly
    case createAndDistribute
    case createDistributeAndUnscope
    var id: String { rawValue }
}

enum SourceProfileDisposition: String, Identifiable {
    case distributeToAll
    case doNotDistribute
    var id: String { rawValue }
}

struct OperationResult: Identifiable {
    let id = UUID()
    let title: String
    let details: String
}

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return "Unknown error"
    }
}
