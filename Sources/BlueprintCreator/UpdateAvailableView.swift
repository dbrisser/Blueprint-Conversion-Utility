import SwiftUI
import AppKit

struct UpdateAvailableView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Available").font(.largeTitle.bold())
                    if let update = model.availableUpdate {
                        Text("Version \(update.latestVersion) is available. You have \(update.currentVersion).")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let update = model.availableUpdate {
                GroupBox("Release Notes") {
                    ScrollView {
                        Text(update.releaseNotes)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    }
                    .frame(minHeight: 220)
                }

                Text("Updates are downloaded from the project's GitHub Releases page. The app does not silently replace itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Skip for Now") { dismiss() }
                    Spacer()
                    Button("Open Release Page") {
                        NSWorkspace.shared.open(update.releaseURL)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(26)
        .frame(width: 650, height: 440)
    }
}
