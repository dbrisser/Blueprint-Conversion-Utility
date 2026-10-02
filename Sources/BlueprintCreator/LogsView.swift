import SwiftUI
import AppKit

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var interval = "1h"
    @State private var category = "All"
    @State private var logText = "Loading the last hour of application logs..."
    @State private var loading = false

    private let categories = [
        "All", "Connections", "Profiles", "Scope",
        "Groups", "Blueprint", "Deployment", "Errors"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Blueprint Conversion Utility Logs").font(.title.bold())
                Spacer()
                Picker("Period", selection: $interval) {
                    Text("1 hour").tag("1h")
                    Text("4 hours").tag("4h")
                    Text("24 hours").tag("24h")
                    Text("7 days").tag("7d")
                }.frame(width: 150)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }.frame(width: 150)
            }

            Text("Predicate: \(predicate)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            TextEditor(text: $logText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            HStack {
                if loading { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await refresh() } }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                Button("Export") { exportLogs() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 620)
        .task { await refresh() }
    }

    private var predicate: String {
        var value = "subsystem == \"\(AppLogger.subsystem)\""
        if category != "All" { value += " AND category == \"\(category)\"" }
        return value
    }

    @MainActor
    private func refresh() async {
        loading = true
        defer { loading = false }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--style", "compact", "--last", interval,
            "--predicate", predicate
        ]
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8) ?? ""
            let failure = String(data: errorData, encoding: .utf8) ?? ""
            logText = result.isEmpty ? (failure.isEmpty ? "No matching log entries." : failure) : result
        } catch {
            logText = "Unable to query unified logging: \(error.localizedDescription)"
        }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlueprintConversionUtility-Logs.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? logText.write(to: url, atomically: true, encoding: .utf8)
    }
}
