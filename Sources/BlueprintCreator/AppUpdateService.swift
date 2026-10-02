import Foundation

struct AppUpdate: Identifiable, Sendable {
    let id = UUID()
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseNotes: String
    let releaseURL: URL
    let publishedAt: Date?
}

private struct GitHubAppRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

actor AppUpdateService {
    static let repositoryURL = URL(string: "https://github.com/jawheelr/Blueprint-Conversion-Utility")!
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/jawheelr/Blueprint-Conversion-Utility/releases/latest")!

    func check(currentVersion: String) async throws -> AppUpdate? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BlueprintConversionUtility/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppFailure.message("GitHub returned no HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "No response details"
            throw AppFailure.message("GitHub update check failed with HTTP \(http.statusCode): \(detail.prefix(500))")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubAppRelease.self, from: data)
        let latest = Self.normalized(release.tagName)
        let current = Self.normalized(currentVersion)
        guard Self.compare(latest, current) == .orderedDescending else { return nil }

        return AppUpdate(
            currentVersion: currentVersion,
            latestVersion: latest,
            releaseName: release.name ?? release.tagName,
            releaseNotes: release.body ?? "No release notes were provided.",
            releaseURL: release.htmlURL,
            publishedAt: release.publishedAt
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV \n\t"))
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}
