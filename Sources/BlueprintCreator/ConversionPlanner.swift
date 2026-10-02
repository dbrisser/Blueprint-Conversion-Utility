import Foundation

enum PayloadStrategy: String, Hashable {
    case legacyVerified = "Legacy configuration-profile component"
    case nativeSchemaRequired = "Native blueprint component required"
    case unsupported = "Unsupported or unverified"
}

struct PayloadPlan: Identifiable, Hashable {
    let id: String
    let payloadType: String
    let strategy: PayloadStrategy
    let status: String
    let canSubmit: Bool
}

struct ConversionPlan {
    let payloads: [PayloadPlan]
    let components: [[String: Any]]
    let warnings: [String]
    var ready: Bool { !payloads.isEmpty && payloads.allSatisfy(\.canSubmit) }

    var summary: String {
        payloads.map { "\($0.payloadType): \($0.strategy.rawValue) | \($0.status)" }
            .joined(separator: "\n")
    }
}

enum ConversionPlanner {
    private static let nativeRequired: Set<String> = [
        "com.apple.mobiledevice.passwordpolicy"
    ]

    private static let verifiedLegacy: Set<String> = [
        "com.apple.applicationaccess",
        "com.apple.wifi.managed",
        "com.apple.notificationsettings",
        "com.apple.security.firewall",
        "com.apple.domains",
        "com.apple.webcontent-filter"
    ]

    static func plan(profile: JamfProfile) throws -> ConversionPlan {
        let sanitized = try BlueprintPayloadSanitizer.sanitize(profile.payloads)
        var plans: [PayloadPlan] = []
        var legacyPayloads: [[String: Any]] = []

        for (index, payload) in sanitized.payloads.enumerated() {
            let type = payload["payloadType"] as? String ?? "unknown"
            if nativeRequired.contains(type) {
                plans.append(PayloadPlan(
                    id: "\(index)-\(type)", payloadType: type,
                    strategy: .nativeSchemaRequired,
                    status: "The Platform rejected this payload in the legacy component. A verified native component schema is required.",
                    canSubmit: false
                ))
            } else if verifiedLegacy.contains(type) {
                legacyPayloads.append(payload)
                plans.append(PayloadPlan(
                    id: "\(index)-\(type)", payloadType: type,
                    strategy: .legacyVerified, status: "Ready", canSubmit: true
                ))
            } else {
                plans.append(PayloadPlan(
                    id: "\(index)-\(type)", payloadType: type,
                    strategy: .unsupported,
                    status: "Compatibility has not been verified. Submission is blocked to protect the source profile.",
                    canSubmit: false
                ))
            }
        }

        var components: [[String: Any]] = []
        if !legacyPayloads.isEmpty {
            components.append([
                "identifier": "com.jamf.ddm-configuration-profile",
                "configuration": [
                    "payloadDisplayName": profile.name,
                    "payloadContent": legacyPayloads
                ]
            ])
        }
        return ConversionPlan(payloads: plans, components: components, warnings: sanitized.warnings)
    }
}
