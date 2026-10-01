import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var filteredProfiles: [JamfProfile] {
        search.isEmpty
            ? model.profiles
            : model.profiles.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            workspace
        }
        .sheet(isPresented: $model.showConnections) {
            ConnectionsView().environmentObject(model)
        }
        .sheet(isPresented: $model.showAbout) { AboutView() }
        .sheet(isPresented: $model.showKB) { KnowledgeBaseView() }
        .sheet(isPresented: $model.showLogs) { LogsView() }
        .sheet(isPresented: $model.showDeploymentReview) {
            DeploymentReviewView().environmentObject(model)
        }
        .confirmationDialog("Configuration Profile Distribution", isPresented: $model.showSourceDispositionPrompt, titleVisibility: .visible) {
            Button("Distribute Removal to All Previously Assigned Devices") { model.confirmSourceDisposition(.distributeToAll) }
            Button("Apply Removal to Newly Assigned Devices Only") { model.confirmSourceDisposition(.doNotDistribute) }
            Button("Cancel", role: .cancel) { model.pendingDistributionChoice = nil }
        } message: { Text("Both choices remove every device and group from the source profile. The selection controls Jamf redistribution behavior for the saved removal.") }
        .alert(item: $model.operationResult) { result in Alert(title: Text(result.title), message: Text(result.details), dismissButton: .default(Text("OK"))) }
        .alert(
            "Blueprint Conversion Utility",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alert ?? "")
        }
        .task { await model.launch() }
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            Picker("Profile type", selection: $model.mobile) {
                Text("Computers").tag(false)
                Text("Mobile Devices").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.mobile) { _ in
                Task { await model.refreshSelectedProfileType() }
            }

            TextField("Search profiles", text: $search)

            List(
                filteredProfiles,
                selection: Binding(
                    get: { model.selectedProfile },
                    set: { profile in
                        if let profile { Task { await model.select(profile) } }
                    }
                )
            ) { profile in
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                    Text("Profile ID \(profile.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(profile)
            }

            Button("Refresh Workspace") { Task { await model.load() } }
                .disabled(!model.ready || model.busy)
        }
        .padding()
        .navigationTitle("Profiles")
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            header
            if !model.scopeNotice.isEmpty {
                scopeBanner
            }
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Generated Blueprint").font(.headline)
                        Spacer()
                        Button("Regenerate") { model.generate() }
                            .disabled(model.selectedProfile == nil)
                    }
                    TextEditor(text: $model.json)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(18)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Deployment").font(.headline)
                    Picker("Device group", selection: $model.selectedGroup) {
                        Text("Select a group").tag(DeviceGroup?.none)
                        ForEach(model.groups) { group in
                            Text(group.name).tag(Optional(group))
                        }
                    }
                    .onChange(of: model.selectedGroup) { _ in model.generate() }

                    GroupBox("Conversion Plan") {
                        Text(model.conversionPlanSummary)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()
                    Button("Create Blueprint") { model.requestCreate() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(
                            !model.ready || model.selectedProfile == nil || model.busy
                        )
                }
                .padding(18)
                .frame(width: 320)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            statusBar
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView().frame(width: 52, height: 52)
            VStack(alignment: .leading) {
                Text("Blueprint Conversion Utility").font(.title.bold())
                Text("Configuration profiles to Jamf blueprints")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                model.ready ? "APIs ready" : "Setup required",
                systemImage: model.ready
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(model.ready ? .green : .orange)
            Button("View Logs") { model.showLogs = true }
            Button("Connections") { model.showConnections = true }
        }
        .padding(18)
    }

    private var scopeBanner: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(model.scopeNotice.split(separator: "\n").enumerated()), id: \.offset) {
                _, line in
                Text(String(line))
                    .font(line.hasPrefix("✓") || line.hasPrefix("⚠") ? .headline : .subheadline.bold())
                    .foregroundStyle(line.hasPrefix("✓") ? .green : line.hasPrefix("⚠") ? .orange : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.status).font(.caption)
            Spacer()
            Text("Creator: Jarred Wheeler")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(.bar)
    }
}

struct AppIconView: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "AppMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "ruler").resizable().scaledToFit().foregroundStyle(.blue)
        }
    }
}
