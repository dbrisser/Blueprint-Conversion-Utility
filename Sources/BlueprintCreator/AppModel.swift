import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var platformSecret: String
    @Published var platformTested = false
    @Published var profiles: [JamfProfile] = []
    @Published var groups: [DeviceGroup] = []
    @Published private(set) var allGroups: [DeviceGroup] = []
    @Published var conversionPlanSummary = "No conversion plan generated."
    @Published var conversionReady = false
    @Published var showSourceDispositionPrompt = false
    @Published var pendingDistributionChoice: SourceProfileDisposition?
    @Published var operationResult: OperationResult?
    @Published var selectedProfile: JamfProfile?
    @Published var selectedProfileID: String?
    @Published var loadingProfileID: String?
    @Published var selectedGroup: DeviceGroup?
    @Published var originalMatchedGroup: DeviceGroup?
    @Published var mobile = false
    @Published var json = "Configure and test the Platform API to begin."
    @Published var status = "Platform API connection is required."
    @Published var scopeNotice = ""
    @Published var busy = false
    @Published var alert: String?
    @Published var showConnections = false
    @Published var showAbout = false
    @Published var showKB = false
    @Published var showLogs = false
    @Published var showDeploymentReview = false
    @Published var showUpdateAvailable = false
    @Published var availableUpdate: AppUpdate?
    @Published var unscopingAcknowledged = false
    @Published var conversionWarnings: [String] = []
    private let profileConvertService = ProfileConvertService()
    private let appUpdateService = AppUpdateService()
    private var profileLoadGeneration = 0

    var complete: Bool {
        !settings.platformURL.isEmpty &&
        !settings.platformClientID.isEmpty &&
        !platformSecret.isEmpty &&
        ((!settings.environmentID.isEmpty) != (!settings.tenantID.isEmpty))
    }
    var ready: Bool { complete && platformTested }


    init() {
        LegacyIdentityMigration.runIfNeeded()
        if let data = UserDefaults.standard.data(forKey: "BlueprintCreator.Settings"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        platformSecret = KeychainStore.readSecret() ?? ""
    }


    func launch() async {
        Task { await checkForAppUpdatesIfDue() }
        status = "Validating saved Platform API connection..."
        guard complete else {
            status = "Platform API configuration is incomplete."
            showConnections = true
            return
        }

        busy = true
        alert = nil
        platformTested = false
        defer { busy = false }
        do {
            try await makePlatform().test()
            try await makeSourceProfiles().test()
            platformTested = true
            showConnections = false
            status = "Platform API ready. Loading workspace..."
            await load()
        } catch {
            status = "Platform API connection test failed."
            alert = error.localizedDescription
            showConnections = true
        }
    }

    func save() throws {
        guard complete else {
            throw AppFailure.message(
                "Complete the Platform API settings and specify exactly one Environment ID or Tenant ID."
            )
        }
        try KeychainStore.saveSecret(platformSecret)
        UserDefaults.standard.set(
            try JSONEncoder().encode(settings),
            forKey: "BlueprintCreator.Settings"
        )
        status = ready ? "Platform API connection passed." : "Saved. Test the Platform API."
        AppLogger.connections.info("Platform API connection settings saved")
    }

    func testPlatform() async {
        await run("Testing Platform API and Platform profile gateway...") {
            try await self.makePlatform().test()
            try await self.makeSourceProfiles().test()
            self.platformTested = true
            self.status = "Platform API connection and configuration-profile access passed."
            AppLogger.connections.info("Platform API test passed")
        }
    }

    func load() async {
        guard ready else { showConnections = true; return }

        // Groups must be ready before a selected profile's source scope is
        // evaluated so the Deployment picker can auto-select its target.
        await run("Loading Platform device groups...") {
            self.allGroups = try await self.makePlatform().groups()
            self.applyGroupFilter()
            let familyName = self.mobile ? "mobile" : "computer"
            AppLogger.groups.info(
                "Loaded \(self.allGroups.count) Platform groups; family=\(familyName, privacy: .public); compatible=\(self.groups.count)"
            )
        }
        guard alert == nil else { return }
        await refreshSelectedProfileType()
        if alert == nil {
            status = "Loaded \(profiles.count) profiles and \(groups.count) compatible groups."
        }
    }

    func refreshSelectedProfileType() async {
        guard ready else { showConnections = true; return }
        profileLoadGeneration += 1
        applyGroupFilter()
        selectedProfileID = nil
        loadingProfileID = nil
        selectedProfile = nil
        selectedGroup = nil
        originalMatchedGroup = nil
        profiles.removeAll()
        scopeNotice = ""
        json = "Loading configuration profiles..."
        await run(mobile ? "Loading mobile device profiles..." : "Loading computer profiles...") {
            self.profiles = try await self.makeSourceProfiles().profiles(mobile: self.mobile)
            AppLogger.profiles.info(
                "Profile list backend: Platform API /proclassic gateway"
            )
            AppLogger.profiles.info("Loaded \(self.profiles.count) profiles; mobile=\(self.mobile)")
        }
        if alert == nil {
            status = "Loaded \(profiles.count) \(mobile ? "mobile device" : "computer") profiles."
            json = "Select a configuration profile to generate a blueprint."
        }
    }

    func select(_ profile: JamfProfile) async {
        profileLoadGeneration += 1
        let generation = profileLoadGeneration
        let selectedID = profile.id

        // Retain the lightweight list object immediately so the row remains
        // highlighted while full profile details and conversion data load.
        selectedProfileID = selectedID
        selectedProfile = profile
        loadingProfileID = selectedID
        conversionReady = false
        conversionPlanSummary = "Loading profile and conversion data..."
        json = "Loading and converting \(profile.name)..."
        status = "Loading \(profile.name)..."
        alert = nil

        do {
            let detail = try await makeSourceProfiles().profileDetail(
                profile,
                mobile: mobile
            )
            guard generation == profileLoadGeneration,
                  selectedProfileID == selectedID else { return }

            selectedProfile = detail
            applyScope(detail)
            await generateHybrid()
        } catch {
            guard generation == profileLoadGeneration,
                  selectedProfileID == selectedID else { return }
            conversionReady = false
            conversionPlanSummary = "Unable to load profile."
            json = "Profile loading failed.\n\n\(error.localizedDescription)"
            status = "Unable to load \(profile.name)."
            alert = error.localizedDescription
            AppLogger.errors.error("\(error.localizedDescription, privacy: .public)")
        }

        if generation == profileLoadGeneration,
           selectedProfileID == selectedID {
            loadingProfileID = nil
        }
    }

    private func applyGroupFilter() {
        let expected: DeviceGroupFamily = mobile ? .mobile : .computer
        groups = allGroups.filter { $0.family == expected }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let selectedGroup, !groups.contains(where: { $0.id == selectedGroup.id }) {
            self.selectedGroup = nil
        }
    }

    private func applyScope(_ profile: JamfProfile) {
        AppLogger.profiles.info("Selected profile ID=\(profile.id, privacy: .public) name=\(profile.name, privacy: .public)")
        AppLogger.scope.info("Scope groups=\(profile.scope.groupNames.count) devices=\(profile.scope.individualDeviceCount) limitations=\(profile.scope.limitationCount) exclusions=\(profile.scope.exclusionCount)")

        let sourceGroups = profile.scope.groupNames
        let expectedFamily: DeviceGroupFamily = mobile ? .mobile : .computer
        let compatibleGroups = groups.filter { $0.family == expectedFamily }

        let exactMatch = compatibleGroups.first { candidate in
            sourceGroups.contains {
                $0.compare(candidate.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        let normalizedMatch = compatibleGroups.first { candidate in
            let candidateName = normalize(candidate.name)
            return sourceGroups.contains { normalize($0) == candidateName }
        }
        let match = exactMatch ?? normalizedMatch
        originalMatchedGroup = match
        selectedGroup = match

        if let match {
            let method = exactMatch != nil ? "exact name" : "normalized name"
            let sourceGroupSummary = sourceGroups.joined(separator: ", ")
            AppLogger.scope.info(
                "Matched source group to Platform group: source=\(sourceGroupSummary, privacy: .public), target=\(match.name, privacy: .public), family=\(expectedFamily.rawValue, privacy: .public), method=\(method, privacy: .public)"
            )
        }

        var messages: [String] = [
            "\(profile.name) (Profile ID \(profile.id)) — Scoped to: \(profile.scope.summary)"
        ]
        if !profile.scope.allDevices && profile.scope.groupNames.isEmpty && profile.scope.individualDeviceCount == 0 {
            messages.append("ⓘ Source profile has 0 associated devices and groups. Conversion is allowed; choose a Platform device group before submission.")
        }
        if let selectedGroup {
            messages.append("✓ Auto-selected matching group: \(selectedGroup.name)")
            AppLogger.scope.info("Auto-selected Platform group ID=\(selectedGroup.id, privacy: .public) name=\(selectedGroup.name, privacy: .public)")
        } else if !profile.scope.groupNames.isEmpty {
            messages.append("⚠ No Platform group matched the profile scope.")
            AppLogger.scope.warning("No Platform group matched profile ID=\(profile.id, privacy: .public)")
        }
        if profile.scope.individualDeviceCount == 1 {
            let deviceType = mobile ? "mobile device" : "computer"
            messages.append("⚠ Profile is scoped directly to 1 \(deviceType); direct device scope cannot be mapped to a Platform group.")
            AppLogger.scope.warning("Profile ID=\(profile.id, privacy: .public) is scoped directly to one \(deviceType, privacy: .public)")
        }
        scopeNotice = messages.joined(separator: "\n")
    }

    private func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let scalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        return scalars
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    func generate() { Task { await generateHybrid() } }
    private func generateHybrid() async {
        guard let profile = selectedProfile else { return }
        do {
            let result = try await profileConvertService.convert(profile)
            let components = (result.components ?? []).map(\.dictionary)
            guard !components.isEmpty else { throw AppFailure.message("profileconvert produced no components.") }
            conversionReady = true; conversionWarnings = result.warnings ?? []
            conversionPlanSummary = (result.conversions ?? []).isEmpty ? "jamf-cli profileconvert: legacy component ready" : (result.conversions ?? []).map { "jamf-cli profileconvert: \($0)" }.joined(separator: "\n")
            let name = result.displayName?.isEmpty == false ? result.displayName! : profile.name
            let object:[String:Any] = ["name":"\(name) (from Configuration Profile #\(profile.id))","description":profile.description.isEmpty ? "Converted from configuration profile ID \(profile.id)." : profile.description,"scope":["deviceGroups":selectedGroup.map{[$0.id]} ?? []],"steps":[["name":name,"components":components]]]
            let data=try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]);json=String(data:data,encoding:.utf8) ?? "";status="Hybrid jamf-cli conversion preflight passed."
        } catch { conversionReady=false;conversionPlanSummary="jamf-cli profileconvert failed: \(error.localizedDescription)";json="Conversion failed before Platform submission.\n\n\(error.localizedDescription)";status="Conversion failed." }
    }

    func requestCreate() {
        guard ready, selectedProfile != nil else {
            alert = "Select a configuration profile first."
            return
        }
        guard conversionReady else {
            alert = "This profile contains payloads without a verified conversion strategy. Review the Conversion Plan."
            return
        }
        showDeploymentReview = true
    }

    func requestCreateDistributeAndUnscope() {
        pendingDistributionChoice = nil; showDeploymentReview = false; showSourceDispositionPrompt = false
        Task { @MainActor in try? await Task.sleep(nanoseconds: 250_000_000); self.showSourceDispositionPrompt = true }
    }

    func confirmSourceDisposition(_ disposition: SourceProfileDisposition) {
        pendingDistributionChoice = disposition; showSourceDispositionPrompt = false; showDeploymentReview = false
        Task { @MainActor in try? await Task.sleep(nanoseconds: 150_000_000); await self.performDeployment(.createDistributeAndUnscope) }
    }

    func performDeployment(_ choice: DeploymentChoice) async {
        guard conversionReady else { alert="Conversion is not ready.";return }; guard let profile=selectedProfile,selectedGroup != nil else { alert="Select a Platform device group.";return }
        if choice == .createDistributeAndUnscope && pendingDistributionChoice == nil { showSourceDispositionPrompt=true;return }
        showSourceDispositionPrompt=false;showDeploymentReview=false;busy=true;alert=nil;defer{busy=false}
        var blueprintID:String?;var created=false;var distributed=false;var sourceModified=false;var phase="Blueprint creation"
        do { await Task.yield();guard let data=json.data(using:.utf8) else{throw AppFailure.message("Invalid blueprint JSON.")};let platform=try makePlatform();blueprintID=try await platform.createBlueprint(data);created=true;if choice != .createOnly{phase="Blueprint distribution";try await platform.deployBlueprint(id:blueprintID!);distributed=true};if choice == .createDistributeAndUnscope{phase="Configuration profile update";switch pendingDistributionChoice{case .distributeToAll:try await makeSourceProfiles().unscopeProfile(id:profile.id,mobile:mobile);case .doNotDistribute:try await makeSourceProfiles().unscopeProfile(id:profile.id,mobile:mobile);case .none:throw AppFailure.message("No source profile action selected.")};sourceModified=true};pendingDistributionChoice=nil;operationResult=OperationResult(title:"Blueprint Operation Completed",details:"Blueprint created: Yes\nBlueprint ID: \(blueprintID ?? "Unknown")\nBlueprint distributed: \(distributed ? "Yes":"No")\nConfiguration profile modified: \(sourceModified ? "Yes":"No")")
        } catch { let snippet=String(error.localizedDescription.prefix(1800));operationResult=OperationResult(title:created && distributed ? "Blueprint Operation Partially Completed":"Blueprint Operation Failed",details:"Failed phase: \(phase)\nBlueprint created: \(created ? "Yes":"No")\nBlueprint ID: \(blueprintID ?? "Not created")\nBlueprint distributed: \(distributed ? "Yes":"No")\nConfiguration profile modified: \(sourceModified ? "Yes":"No")\n\nReturn log snippet:\n\(snippet)") }
    }

    private func makeSourceProfiles() throws -> PlatformProfileClient {
        try PlatformProfileClient(
            url: settings.platformURL,
            clientID: settings.platformClientID,
            clientSecret: platformSecret,
            environmentID: settings.environmentID,
            tenantID: settings.tenantID
        )
    }


    private func makePlatform() throws -> PlatformClient {
        try PlatformClient(
            url: settings.platformURL,
            clientID: settings.platformClientID,
            clientSecret: platformSecret,
            environmentID: settings.environmentID,
            tenantID: settings.tenantID
        )
    }

    func checkForAppUpdatesIfDue() async {
        let defaults = UserDefaults.standard
        let key = "BlueprintCreator.LastAppUpdateCheck"
        let weeklyInterval: TimeInterval = 7 * 24 * 60 * 60
        let lastCheck = defaults.object(forKey: key) as? Date

        guard lastCheck == nil || Date().timeIntervalSince(lastCheck!) >= weeklyInterval else {
            AppLogger.connections.debug("Automatic application update check is not due")
            return
        }

        // Persist the attempt before the network request so an unavailable
        // network does not cause a GitHub request on every application launch.
        defaults.set(Date(), forKey: key)
        await checkForAppUpdates(manual: false)
    }

    func checkForAppUpdates(manual: Bool) async {
        if manual {
            UserDefaults.standard.set(
                Date(),
                forKey: "BlueprintCreator.LastAppUpdateCheck"
            )
        }
        let current = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        do {
            let update = try await appUpdateService.check(currentVersion: current)
            if let update {
                availableUpdate = update
                showUpdateAvailable = true
                AppLogger.connections.notice(
                    "Application update available: current=\(current, privacy: .public), latest=\(update.latestVersion, privacy: .public)"
                )
            } else if manual {
                alert = "Blueprint Conversion Utility \(current) is up to date."
            }
        } catch {
            AppLogger.connections.error(
                "Application update check failed: \(error.localizedDescription, privacy: .public)"
            )
            if manual {
                alert = "Unable to check for updates.\n\n\(error.localizedDescription)"
            }
        }
    }

    private func run(_ message: String,
                     operation: @escaping @MainActor () async throws -> Void) async {
        busy = true
        status = message
        alert = nil
        defer { busy = false }
        do { try await operation() }
        catch {
            alert = error.localizedDescription
            status = "Operation failed."
            AppLogger.errors.error("\(error.localizedDescription, privacy: .public)")
        }
    }
}
