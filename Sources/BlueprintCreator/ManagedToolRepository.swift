import Foundation
actor ManagedToolRepository {
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true) }
    static var jamfCLI: URL { directory.appendingPathComponent("jamf-cli") }
    static var converter: URL { directory.appendingPathComponent("blueprint-profile-convert") }
    func validatedConverter() throws -> URL {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if !FileManager.default.isExecutableFile(atPath: Self.converter.path) {
            guard let bundled = Bundle.main.url(forResource:"blueprint-profile-convert",withExtension:nil,subdirectory:"bin") else { throw AppFailure.message("Bundled profile conversion helper is missing.") }
            try install(bundled, to: Self.converter)
        }
        if !FileManager.default.isExecutableFile(atPath: Self.jamfCLI.path), let bundled = Bundle.main.url(forResource:"jamf-cli",withExtension:nil,subdirectory:"bin") { try install(bundled, to: Self.jamfCLI) }
        guard FileManager.default.isExecutableFile(atPath: Self.converter.path) else { throw AppFailure.message("Managed helper is unavailable at \(Self.converter.path).") }
        return Self.converter
    }
    private func install(_ source:URL,to destination:URL)throws{let fm=FileManager.default;let staging=destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).new-\(UUID().uuidString)");defer{try? fm.removeItem(at:staging)};try fm.copyItem(at:source,to:staging);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:staging.path);if fm.fileExists(atPath:destination.path){try fm.removeItem(at:destination)};try fm.moveItem(at:staging,to:destination)}
}
