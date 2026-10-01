import Foundation
import OSLog

struct JamfCLIStatus: Equatable, Sendable {
    let available: Bool
    let path: String
    let version: String
    let detail: String
    let supportsBlueprintCreation: Bool
}

struct JamfCLIUpdate: Equatable, Sendable {
    let currentVersion: String
    let latestVersion: String
    let assetName: String
    let assetURL: URL
    var updateAvailable: Bool { normalized(currentVersion) != normalized(latestVersion) }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV \n\t"))
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    let tagName: String
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct CLIResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

actor JamfCLIService {
    static let releasesPage = URL(string: "https://github.com/Jamf-Concepts/jamf-cli/releases")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Jamf-Concepts/jamf-cli/releases/latest")!

    static var managedDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blueprint Conversion Utility/CLI", isDirectory: true)
    }

    static var managedExecutable: URL {
        managedDirectory.appendingPathComponent("jamf-cli", isDirectory: false)
    }

    static let commonPaths = [
        "/opt/homebrew/bin/jamf-cli",
        "/usr/local/bin/jamf-cli",
        "/opt/homebrew/bin/jamf",
        "/usr/local/bin/jamf"
    ]

    func discover(configuredPath: String) -> JamfCLIStatus {
        var candidates = [Self.managedExecutable.path]
        if !configuredPath.isEmpty { candidates.append(configuredPath) }
        candidates.append(contentsOf: Self.commonPaths.filter { !candidates.contains($0) })

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            guard let versionResult = try? run(executable: path, arguments: ["--version"]),
                  versionResult.exitCode == 0 else { continue }
            let version = (versionResult.stdout.isEmpty ? versionResult.stderr : versionResult.stdout)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let help = (try? run(executable: path, arguments: ["--help"]))
            let helpText = ((help?.stdout ?? "") + "\n" + (help?.stderr ?? "")).lowercased()
            let supportsBlueprints = helpText.contains("blueprint")
            return JamfCLIStatus(
                available: true,
                path: path,
                version: version,
                detail: path == Self.managedExecutable.path
                    ? "Application-managed jamf-cli"
                    : "External jamf-cli",
                supportsBlueprintCreation: supportsBlueprints
            )
        }

        return JamfCLIStatus(
            available: false,
            path: Self.managedExecutable.path,
            version: "Not installed",
            detail: "Native API backend is active.",
            supportsBlueprintCreation: false
        )
    }

    func test(configuredPath: String) throws -> JamfCLIStatus {
        let status = discover(configuredPath: configuredPath)
        guard status.available else {
            throw AppFailure.message("jamf-cli is not installed or could not be validated.")
        }
        return status
    }

    func checkForUpdate(configuredPath: String) async throws -> JamfCLIUpdate {
        let current = discover(configuredPath: configuredPath)
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BlueprintConversionUtility/2.5.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data, operation: "jamf-cli update check")
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = selectMacAsset(release.assets) else {
            throw AppFailure.message("The latest jamf-cli release does not contain a recognized macOS download asset.")
        }
        return JamfCLIUpdate(
            currentVersion: current.available ? current.version : "Not installed",
            latestVersion: release.tagName,
            assetName: asset.name,
            assetURL: asset.browserDownloadURL
        )
    }

    func downloadAndInstall(_ update: JamfCLIUpdate) async throws -> JamfCLIStatus {
        var request = URLRequest(url: update.assetURL)
        request.setValue("BlueprintConversionUtility/2.5.1", forHTTPHeaderField: "User-Agent")
        let (downloadURL, response) = try await URLSession.shared.download(for: request)
        try validateHTTP(response, data: Data(), operation: "jamf-cli download")

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("jamf-cli-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let downloaded = work.appendingPathComponent(update.assetName)
        try FileManager.default.moveItem(at: downloadURL, to: downloaded)
        let candidate = try extractCandidate(downloaded, workDirectory: work)
        return try install(from: candidate)
    }

    func install(from source: URL) throws -> JamfCLIStatus {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AppFailure.message("Select a regular jamf-cli executable.")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: Self.managedDirectory, withIntermediateDirectories: true)
        let backup = Self.managedDirectory.appendingPathComponent("jamf-cli.previous")
        try? fm.removeItem(at: backup)
        if fm.fileExists(atPath: Self.managedExecutable.path) {
            try fm.moveItem(at: Self.managedExecutable, to: backup)
        }

        do {
            try fm.copyItem(at: source, to: Self.managedExecutable)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.managedExecutable.path)
            let status = discover(configuredPath: Self.managedExecutable.path)
            guard status.available else {
                throw AppFailure.message("The downloaded executable failed jamf-cli validation.")
            }
            try? fm.removeItem(at: backup)
            return status
        } catch {
            try? fm.removeItem(at: Self.managedExecutable)
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: Self.managedExecutable)
            }
            throw error
        }
    }

    func removeManagedCLI() throws {
        if FileManager.default.fileExists(atPath: Self.managedExecutable.path) {
            try FileManager.default.removeItem(at: Self.managedExecutable)
        }
    }

    private func selectMacAsset(_ assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        let mac = assets.filter {
            let name = $0.name.lowercased()
            return name.contains("darwin") || name.contains("macos") || name.contains("apple")
        }
        return mac.first {
            let name = $0.name.lowercased()
            return name.contains("arm64") || name.contains("aarch64") || name.contains("universal")
        } ?? mac.first
    }

    private func extractCandidate(_ downloaded: URL, workDirectory: URL) throws -> URL {
        let lower = downloaded.lastPathComponent.lowercased()
        if lower.hasSuffix(".zip") {
            try execute("/usr/bin/ditto", ["-x", "-k", downloaded.path, workDirectory.path])
        } else if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            try execute("/usr/bin/tar", ["-xzf", downloaded.path, "-C", workDirectory.path])
        } else {
            return downloaded
        }

        let enumerator = FileManager.default.enumerator(
            at: workDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            let name = file.lastPathComponent.lowercased()
            if values?.isRegularFile == true && (name == "jamf-cli" || name == "jamf") {
                return file
            }
        }
        throw AppFailure.message("The downloaded archive did not contain a jamf-cli executable.")
    }

    private func execute(_ executable: String, _ arguments: [String]) throws {
        let result = try run(executable: executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw AppFailure.message(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    private func run(executable: String, arguments: [String]) throws -> CLIResult {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        return CLIResult(
            stdout: String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private func validateHTTP(_ response: URLResponse, data: Data, operation: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppFailure.message("\(operation) returned no HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response details"
            throw AppFailure.message("\(operation) failed with HTTP \(http.statusCode): \(body.prefix(500))")
        }
    }
}
