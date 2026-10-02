import SwiftUI
import AppKit

private enum KBTopic: String, CaseIterable, Identifiable {
    case overview = "Application Overview"
    case workflow = "Conversion Workflow"
    case platform = "Platform API"
    case cli = "jamf-cli"
    case payloads = "Payload Compatibility"
    case deployment = "Deployment and Unscoping"
    case groups = "Device Groups"
    case troubleshooting = "Troubleshooting"
    case updates = "Updates and Support"
    var id: String { rawValue }
}

struct KnowledgeBaseView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: KBTopic? = .overview

    var body: some View {
        NavigationSplitView {
            List(KBTopic.allCases, selection: $selection) { topic in
                Label(topic.rawValue, systemImage: icon(for: topic)).tag(topic)
            }
            .navigationTitle("Knowledge Base")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    article(selection ?? .overview)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Project on GitHub") {
                    NSWorkspace.shared.open(AppUpdateService.repositoryURL)
                }
                Button("Check for Updates") { Task { await model.checkForAppUpdates(manual: true) } }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(14)
            .background(.bar)
        }
        .frame(width: 980, height: 700)
    }

    @ViewBuilder
    private func article(_ topic: KBTopic) -> some View {
        switch topic {
        case .overview:
            heading("Application Overview", "What Blueprint Conversion Utility does")
            paragraph("Blueprint Conversion Utility migrates computer and mobile-device configuration profiles into Jamf Platform Blueprints. All network operations use Platform OAuth against the regional api.jamfcloud.com host.")
            bullets([
                "Loads source profiles through the Platform-published /proclassic profile gateway.",
                "Uses the bundled Jamf profileconvert engine to produce native DDM and compatible legacy components.",
                "Creates and distributes Blueprints with native Platform endpoints.",
                "Optionally removes all active scope from the source profile only after Blueprint creation and distribution succeed.",
                "Reads the source profile back and verifies that no active scope remains."
            ])
            note("The /proclassic path describes the resource family exposed by Jamf Platform. The app does not use a separate Jamf Pro URL, credential, or token.")

        case .workflow:
            heading("Conversion Workflow", "The phases executed for each profile")
            numbered([
                "Choose Computers or Mobile Devices and select a source profile.",
                "The app retrieves XML and payload content through the Platform profile gateway.",
                "blueprint-profile-convert reconstructs and converts the mobileconfig locally.",
                "Select a device group that matches the active device family.",
                "Review generated JSON, conversion mappings, and warnings.",
                "Choose create only, create and distribute, or create, distribute, and unscope.",
                "The app reports complete success, failure, or partial completion with the returned Blueprint ID and error snippet."
            ])
            note("Every destructive phase is gated. A creation failure prevents distribution. A distribution failure prevents source-profile modification.")

        case .platform:
            heading("Platform API", "Connection and permissions")
            paragraph("Connections requires the regional Platform URL, client ID, client secret, and exactly one Environment ID or Tenant ID. The client secret is stored in macOS Keychain.")
            bullets([
                "OAuth token endpoint: /auth/token",
                "Mobile profiles: /proclassic/mobiledeviceconfigurationprofiles",
                "Computer profiles: /proclassic/osxconfigurationprofiles",
                "Platform groups: /device-groups/v1/device-groups",
                "Blueprint operations: /blueprints/v1/blueprints"
            ])
            subsection("Connection test")
            paragraph("The Platform test validates OAuth plus access to both computer and mobile configuration-profile collections. A successful token alone is not treated as a complete test.")
            subsection("Scope header")
            paragraph("The app sends either X-Environment-Id or X-Tenant-Id. Supplying both is blocked because requests must have one unambiguous Platform scope.")

        case .cli:
            heading("jamf-cli", "How Jamf conversion code is used")
            paragraph("The application ships Jamf Concepts jamf-cli and a dedicated blueprint-profile-convert helper. The helper is compiled inside the Jamf CLI Go module so it can use internal/profileconvert directly.")
            bullets([
                "Managed binary location: ~/.local/bin/jamf-cli",
                "Managed converter location: ~/.local/bin/blueprint-profile-convert",
                "Bundled fallback location: the app's Contents/Resources/bin directory",
                "Passcode payloads can become com.jamf.ddm.passcode-settings.",
                "Supported Safari and software-update settings can become native DDM components.",
                "Compatible remaining payloads are wrapped in com.jamf.ddm-configuration-profile."
            ])
            subsection("Diagnostic tab")
            paragraph("Connections > jamf-cli runs only jamf-cli --version. The contained output shows the exact query, executable, stdout, stderr, exit code, and duration. The test sends no credentials and makes no API request.")
            subsection("Security")
            paragraph("Conversion uses a private temporary directory and mobileconfig file. Credentials are never passed to the helper. Temporary data is deleted after conversion.")

        case .payloads:
            heading("Payload Compatibility", "Native, legacy, and disabled payloads")
            paragraph("The converter promotes mappings supported by Jamf's profileconvert engine and filters payload types that Blueprints explicitly disables.")
            bullets([
                "Native mappings are emitted as dedicated DDM components.",
                "Compatible legacy payloads remain in the configuration-profile component.",
                "Disabled payloads are excluded and surfaced as conversion warnings.",
                "Examples of disabled payloads include com.apple.security.root, com.apple.security.pkcs1, and com.apple.vpn.managed.",
                "If no components remain after filtering, Blueprint creation is blocked and the source profile is not modified."
            ])
            warning("Review all conversion warnings before unscoping the source profile. An excluded payload is not deployed by the resulting Blueprint.")

        case .deployment:
            heading("Deployment and Unscoping", "Safe migration actions")
            bullets([
                "Create Blueprint Only creates the Blueprint and leaves distribution and the source profile unchanged.",
                "Create and Distribute Blueprint creates and deploys the Blueprint but leaves the source profile unchanged.",
                "Create and Distribute Blueprint and Unscope Configuration Profile deploys first, then clears source scope."
            ])
            subsection("Scope removal")
            paragraph("Unscoping sets all-device and all-user flags to false and clears devices, groups, buildings, departments, users, user groups, limitations, and exclusions. The Platform response may return empty self-closing or nested containers; verification checks semantic assignments rather than XML formatting.")
            subsection("Partial completion")
            paragraph("If the Blueprint was deployed but profile cleanup fails, the result is marked partially completed. The Blueprint is retained and the source profile is not reported as modified.")

        case .groups:
            heading("Device Groups", "Family-aware target selection")
            paragraph("The device-group picker is filtered by the selected source type.")
            bullets([
                "Computers shows confirmed computer or macOS groups only.",
                "Mobile Devices shows confirmed mobile, iOS, or iPadOS groups only.",
                "Switching device family clears incompatible selections.",
                "Automatic matching compares the source scope with compatible Platform groups.",
                "No Platform group matched is informational; select a compatible target manually."
            ])

        case .troubleshooting:
            heading("Troubleshooting", "Common failures and next steps")
            subsection("HTTP 400 configuration validation")
            paragraph("Inspect the reported component path and conversion warnings. Disabled or unsupported payloads must not remain in the legacy component.")
            subsection("No Platform group matched")
            paragraph("Choose a compatible target group manually. This message does not mean profile conversion or unscoping failed.")
            subsection("Profile cleanup verification")
            paragraph("The result includes active scope indicators and a bounded XML snippet only when an all-device flag or assigned object ID/name remains.")
            subsection("Diagnostic information")
            bullets([
                "Open Logs from the application menu.",
                "Use Connections > jamf-cli > Test jamf-cli.",
                "Include Platform trace IDs and the failed phase in support reports.",
                "Do not repeat a completed create-and-distribute operation solely to retry cleanup."
            ])

        case .updates:
            heading("Updates and Support", "GitHub release checks")
            paragraph("The app checks the latest release from github.com/jawheelr/Blueprint-Conversion-Utility on first launch and then no more than once every seven days. If a newer semantic version exists, an Update Available window shows release notes and opens the official GitHub release page.")
            bullets([
                "No update is installed silently.",
                "No GitHub credentials are required for public releases.",
                "Use Blueprint Conversion Utility > Check for Updates to run a manual check.",
                "A failed weekly background check is logged without blocking startup. The next automatic attempt occurs after the seven-day interval.",
                "Manual checks report whether the current version is up to date."
            ])
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }
    private func subsection(_ value: String) -> some View { Text(value).font(.title2.bold()) }
    private func paragraph(_ value: String) -> some View { Text(value).textSelection(.enabled) }
    private func bullets(_ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                HStack(alignment: .top) { Text("•").bold(); Text(value).textSelection(.enabled) }
            }
        }
    }
    private func numbered(_ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(alignment: .top) { Text("\(index + 1).").bold().frame(width: 24, alignment: .trailing); Text(value) }
            }
        }
    }
    private func note(_ value: String) -> some View {
        Label(value, systemImage: "info.circle.fill").padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func warning(_ value: String) -> some View {
        Label(value, systemImage: "exclamationmark.triangle.fill").padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func icon(for topic: KBTopic) -> String {
        switch topic {
        case .overview: "app.badge"
        case .workflow: "arrow.triangle.2.circlepath"
        case .platform: "network"
        case .cli: "terminal"
        case .payloads: "shippingbox"
        case .deployment: "paperplane"
        case .groups: "person.3"
        case .troubleshooting: "wrench.and.screwdriver"
        case .updates: "arrow.down.circle"
        }
    }
}
