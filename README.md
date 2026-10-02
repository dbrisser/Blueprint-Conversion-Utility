# 🧭 Blueprint Conversion Utility

> Convert Jamf Pro configuration profiles into Jamf Blueprints with scope-aware migration, payload compatibility planning, deployment review, and verified source-profile unscoping.

Blueprint Conversion Utility is a native macOS application for converting Jamf Pro configuration profiles into Jamf Blueprints, reviewing their scope and payload compatibility, deploying the resulting Blueprint to Platform device groups, and optionally removing scope from the original Jamf Pro profile after a successful migration.

The utility provides a Platform-only API architecture, Keychain-backed credentials, adaptive payload conversion planning, managed `jamf-cli` diagnostics, deployment review, verified source-profile unscoping, Apple Unified Logging, and complete `.app` / `.pkg` / `.dmg` build support.

---

## ✨ Highlights

Blueprint Conversion Utility can:

- 📋 List computer and mobile device configuration profiles.
- 🔍 Retrieve and parse complete profile XML.
- 🎯 Read profile scope, limitations, exclusions, and direct device assignments.
- 🔗 Automatically match scoped Jamf groups with Platform device groups.
- 🧠 Build a compatibility plan for every profile before conversion.
- 🧹 Remove payloads explicitly disabled by Jamf Blueprints.
- ⚠️ Identify payloads requiring native Blueprint components.
- ❓ Flag unknown payloads as unverified rather than submitting them blindly.
- 🏗️ Create Jamf Blueprints.
- 🚀 Deploy Blueprints to Platform device groups.
- 🔄 Redistribute converted profiles to original and newly selected groups.
- 🧯 Safely remove scope from source configuration profiles.
- ✅ Verify source-profile unscoping with API read-back.
- 🔐 Store Platform credentials in macOS Keychain.
- 🤖 Integrate with and diagnose `jamf-cli`.
- 📜 Write operational events to Apple Unified Logging.
- 🪵 View, filter, copy, and export application logs.
- 📦 Build `.app`, `.pkg`, and `.dmg` distribution artifacts.

---

# 🎯 Scope-Aware Migration

Profile scope is carried through the migration workflow rather than discarded during conversion.

The utility reads:

- Scoped groups
- Limitations
- Exclusions
- Individual computer assignments
- Individual mobile-device assignments

When a Jamf Pro group in the source profile has a normalized name matching a Platform device group, the corresponding Platform group is automatically preselected.

A scope banner summarizes the source profile's current state.

### ⚠️ Direct Device Scope Warning

The application displays an explicit warning when exactly one computer or mobile device is directly scoped.

This helps prevent a single-device assignment from being overlooked during migration.

---

# 🧠 Adaptive Conversion Planner

Every selected profile receives a per-run payload compatibility plan **before** Blueprint creation.

Payloads are classified into three general categories.

### ✅ Legacy-Compatible

Verified legacy payloads are routed through the legacy configuration-profile Blueprint component.

### ⚠️ Native Component Required

Payloads known to require a native Blueprint component are blocked from inappropriate legacy submission.

For example, the mobile passcode payload is identified as requiring a verified native schema because the Platform rejects it when submitted through the legacy configuration-profile component.

### ❓ Unverified

Unknown payloads are identified as **unverified** rather than being sent to the Platform without validation.

This allows the operator to review unsupported or not-yet-validated payloads before deployment.

---

# 🧹 Disabled Payload Filtering

The bundled Jamf `profileconvert` helper runs with its Blueprints compatibility filter enabled.

Payload types that Jamf Blueprints explicitly disables are removed from the legacy configuration-profile component before Blueprint creation.

Known filtered payloads include:

```text
com.apple.security.root
com.apple.security.pkcs1
com.apple.vpn.managed
```

### 👀 Filtering Is Visible

Filtered payloads are **not silently discarded**.

Converter warnings remain available in the conversion plan so the operator can see which payloads were excluded.

---

# 🌐 Platform-Only API Architecture

Blueprint Conversion Utility uses a unified Jamf Platform API architecture.

All application network operations use:

- 🌐 Jamf Platform API hostname
- 🔑 Platform OAuth client credentials
- 🪪 A single Platform scope header

Computer and mobile configuration-profile operations use the Platform-published Pro Classic gateway resources:

```text
/proclassic/osxconfigurationprofiles
/proclassic/mobiledeviceconfigurationprofiles
```

These resources are used for:

- Profile listing
- Profile detail retrieval
- Profile XML retrieval
- Scope updates
- Source-profile unscoping

Blueprint device groups, Blueprint creation, and Blueprint deployment use native Platform API resources.

The application does not require a separate Jamf Pro URL, client ID, client secret, token cache, API connection test, or Jamf Pro Connections tab.

Existing Platform secrets can be migrated from a previous Keychain payload when available.

---

# 🔐 Credentials & Keychain Storage

Platform credentials are stored using **macOS Keychain** rather than plaintext application preferences.

The application is designed not to expose client secrets or access tokens in:

- `jamf-cli` command-line arguments
- Diagnostic output
- Unified Logging
- User-facing log exports

When credentials must be supplied to a supported CLI subprocess, they are provided through the subprocess environment rather than command-line arguments.

---

# 🔀 Native API + `jamf-cli`

Blueprint Conversion Utility supports native Platform API operations alongside compatible `jamf-cli` operations.

Native API operations remain authoritative where structured profile XML, source-profile scope manipulation, or Platform compatibility requires them.

The application validates `jamf-cli` directly using `Process` and can inspect the executable's supported commands before attempting an operation.

`jamf-cli` releases that do not expose the required Blueprint commands are **not** invoked for Blueprint creation.

In that situation:

> 🛟 **The native Platform API backend remains active.**

No secret or token is placed in `jamf-cli` process arguments.

### 🙌 Kudos

A special shout-out and thanks to **[@Neil Martin](https://github.com/neilmartin83)** for his work on `jamf-cli` and for helping move the Jamf community forward with modern tooling and workflows. 👏

---

## 🧵 Swift Concurrency & CLI Process Safety

The CLI implementation uses a dedicated `Sendable` command-result type.

Subprocess execution occurs within the `JamfCLIService` actor, avoiding unsafe concurrently executed local continuation callbacks.

Unified-log messages emitted by `JamfCLIService` use single `OSLogMessage` interpolations.

---

# 🤖 Managed `jamf-cli`

The application can maintain a validated `jamf-cli` executable within its application context.

The managed CLI workflow can:

1. 🔎 Retrieve official Jamf `jamf-cli` release metadata.
2. 🖥️ Select an appropriate macOS Apple Silicon or universal asset.
3. ⬇️ Download and extract the release.
4. ✅ Validate the executable with:

```bash
jamf-cli --version
```

5. 🔍 Inspect available capabilities with:

```bash
jamf-cli --help
```

6. 🧠 Determine whether the release exposes compatible Blueprint functionality.
7. 🔄 Atomically install the validated executable.
8. 🛟 Restore the previous managed copy if validation or replacement fails.

A CLI release without compatible Blueprint commands is not used for Blueprint creation.

Native Platform API creation remains available in that case.

---

# 🩺 `jamf-cli` Diagnostics

Connections includes a dedicated **jamf-cli** diagnostics tab.

The tab intentionally provides diagnostics rather than CLI configuration or credential management.

Select:

> **🧪 Test jamf-cli**

to perform a non-destructive diagnostic.

The test runs only:

```bash
jamf-cli --version
```

The diagnostic records:

- 📍 Executable path
- 📦 Executable source
- 🔎 Query
- 📤 Standard output
- 📥 Standard error
- 🔢 Exit code
- ⏱️ Execution duration
- 🕐 Timestamp
- ✅ / ❌ Pass/fail result

Diagnostic output appears in a contained, scrollable monospaced view.

Available controls include:

- **Test jamf-cli**
- **Copy Output**
- **Clear**

### 🔒 Intentionally Not Exposed

The diagnostics tab does **not** expose:

- Credentials
- OAuth tokens
- Environment values
- Installation controls
- Update controls
- Executable path controls
- Backend-selection controls

---

# 🧩 Profile XML Parsing

The profile parser preserves the complete configuration-profile information required by the conversion workflow.

`ProfileDetailParser` handles:

- Profile metadata
- Description
- Payload content
- Nested payload dictionaries
- Scope
- Limitations
- Exclusions
- Individual assignments

Nested payload dictionaries are preserved while maintaining the complete description, payload, and scope parsing lifecycle.

---

# 👥 Device Group Matching

Platform device groups retain device-family metadata:

| Family | Status |
|---|---|
| 💻 Computer | Recognized |
| 📱 Mobile | Recognized |
| ❔ Unknown | Retained and labeled |

Groups are filtered according to the active workspace where the device family can be determined.

Groups whose family cannot be determined remain visible and are explicitly labeled rather than silently removed.

When loading a scoped profile, the utility compares its Jamf Pro group names with available Platform groups using normalized names.

A matching Platform group can therefore be automatically selected as the source profile's original deployment group.

---

# 👀 Deployment Review

Before performing deployment actions, Blueprint Conversion Utility presents a deployment review.

The review includes:

- 📄 Source profile information
- 🧭 Target Blueprint information
- 👥 Source and target group information
- 🧩 Payload/conversion status
- 🎯 Current scope state
- 🧯 Unscoping controls
- 🔀 Distribution strategy
- ⚠️ Destructive-action acknowledgement where required

Source and target information is displayed using paired cards, with full-width primary action controls and explicit group status.

Deployment actions are phase protected to prevent incompatible operations from being triggered concurrently.

---

# 🚀 Distribution Strategies

When the source configuration profile currently has scope, the operator can choose between two migration strategies.

## 🔄 Redistribute to Original and New Groups

The Blueprint is scoped to:

1. The automatically matched original Platform group.
2. The newly selected Platform group.

The application then follows the migration sequence:

```text
🏗️ Create Blueprint
       ↓
🎯 Apply Blueprint Scope
       ↓
🚀 Deploy Blueprint
       ↓
🧯 Unscope Source Profile
       ↓
🔍 Read Back Source Profile
       ↓
✅ Verify Empty Scope
```

## ➡️ Distribute to New Group Only

The Blueprint is deployed only to the newly selected Platform group.

After deployment, the application:

1. Unscopes the original source profile.
2. Retrieves the source profile again.
3. Verifies that its scope is empty.

## 🟢 Already-Unscoped Profiles

Profiles with no existing source scope use the standard:

> **Distribute to New Group**

workflow.

---

# 🧯 Safe Source Profile Unscoping

Source-profile unscoping is designed to avoid reconstructing a configuration profile unnecessarily.

The application:

1. 📥 Retrieves the actual source profile XML.
2. 🔎 Locates scope nodes already present in that XML.
3. ✏️ Modifies only applicable scope content.
4. 📤 Sends the update through the Platform Pro Classic gateway.
5. 📥 Retrieves the profile again.
6. ✅ Semantically verifies that the returned scope is empty.

### ✅ Verified, Not Assumed

Success is reported **only after read-back verification confirms that scope has been removed**.

This avoids treating an HTTP success status by itself as proof that the profile was actually unscoped.

Where multiple update strategies are attempted, diagnostic information from failed HTTP responses is retained so Jamf API rejection details can be presented to the operator.

---

# 🏗️ Create Blueprint Actions

Depending on profile state and deployment context, the Create Blueprint workflow can present actions including:

- **Create Only**
- **Create and Deploy**
- **Create / Deploy / Unscope**

Actions that can modify or remove the source profile's existing distribution require appropriate acknowledgement in the UI.

The destructive migration sequence is deliberately ordered:

```text
🏗️ Create Blueprint
       │
       ▼
🚀 Deploy Blueprint
       │
       ▼
🔍 Verify Deployment Phase
       │
       ▼
🧯 Unscope Source Profile
       │
       ▼
📥 Read Back Source Profile
       │
       ▼
✅ Verify Empty Scope
```

> ⚠️ The source profile is not intentionally unscoped before the Blueprint creation and deployment phases have completed.

---

# 📜 Apple Unified Logging

Operational events are written to Apple Unified Logging using the subsystem:

```text
com.jawheelr.blueprintcreator
```

This provides persistent, system-integrated diagnostics without requiring a separate application log file.

### 🔍 Historical Logs

```bash
log show --predicate 'subsystem == "com.jawheelr.blueprintcreator"'
```

### 📡 Live Logs

```bash
log stream --predicate 'subsystem == "com.jawheelr.blueprintcreator"'
```

You can also specify a time range when investigating recent activity:

```bash
log show --last 1h --predicate 'subsystem == "com.jawheelr.blueprintcreator"'
```

---

# 🪵 View Logs

The application includes a dedicated **View Logs** window for inspecting its Unified Logging events.

The viewer provides:

- 🕐 Time predicates
- 🏷️ Category predicates
- 🔄 Refresh
- 📋 Copy
- 📤 Export

This allows common troubleshooting information to be collected without requiring operators to manually construct `log` command predicates.

---

# 🪟 Native macOS Window Behavior

The application's visible title-bar text is hidden while normal macOS window behavior remains available.

This preserves:

- 🔴🟡🟢 Standard macOS window controls
- Sidebar behavior
- Native window movement
- Native window resizing

while avoiding redundant title text in the main interface.

---

# 📋 Requirements

Blueprint Conversion Utility is intended for macOS environments administering Jamf Pro and Jamf Blueprints.

Typical requirements include:

- 🍎 macOS
- 🌐 Network access to the Jamf Platform API
- 🔑 Valid Jamf Platform OAuth client credentials
- 🪪 Appropriate Platform API scopes and permissions
- 📄 Access to configuration profiles being converted
- 🏗️ Permission to create Blueprints
- 🚀 Permission to deploy Blueprints
- 🧯 Permission to update source configuration-profile scope when using unscoping workflows
- 🛠️ Xcode/Swift build tooling when building from source

`jamf-cli` is optional for operations that have a supported native Platform API implementation.

---

# 🛠️ Building

The project includes application, package, and disk-image build support.

## 🚀 Build Without `sudo`

From the project root:

```bash
xattr -dr com.apple.quarantine . && /bin/bash ./build.sh
```

This removes the quarantine extended attribute from the source tree and executes the build script without requiring `sudo`.

> ⚠️ **Security note:** Review scripts before executing them when building code obtained from an untrusted source.

The build workflow produces the applicable macOS distribution artifacts:

```text
📦 Build
 ├── 🧭 Blueprint Conversion Utility.app
 ├── 📦 .pkg
 └── 💿 .dmg
```

Exact output locations are determined by `build.sh`.

---

# 🧪 API Tests

The project includes required API tests used to validate the supported Jamf Platform integration paths.

Tests should be run against an appropriate non-production or controlled Jamf environment when they perform operations capable of modifying server-side state.

> 🔐 Do not place production credentials directly in test source code.

---

# 🛡️ Security Considerations

Blueprint Conversion Utility performs administrative operations capable of changing device configuration distribution.

Before production deployment:

- 🔐 Use a least-privilege Platform OAuth client.
- 🧪 Validate conversions against representative test devices.
- ⚠️ Review payload compatibility warnings.
- 🧹 Review payloads excluded by the Blueprint compatibility filter.
- 👥 Verify automatically matched device groups.
- 🎯 Review individual-device scope warnings.
- 🔀 Confirm the selected distribution strategy.
- 🧯 Confirm the source-profile disposition.
- 📜 Review logs following failed API operations.
- 🔒 Protect exported diagnostics according to organizational security requirements.

The utility is designed to avoid placing secrets in subprocess command-line arguments and uses macOS Keychain for persistent credential material.

---

# 🛡️ Migration Safety Model

The conversion workflow deliberately separates conversion, deployment, and destructive source-profile changes.

```text
              📄 Load Source Profile
                       │
                       ▼
              🔍 Parse Payload + Scope
                       │
                       ▼
             🧠 Build Compatibility Plan
                       │
                       ▼
              🧹 Filter Disabled Payloads
                       │
                       ▼
                👥 Match Platform Groups
                       │
                       ▼
                 👀 Review Conversion
                       │
                       ▼
                 🏗️ Create Blueprint
                       │
                       ▼
                 🚀 Deploy Blueprint
                       │
                       ▼
               🧯 Unscope Source Profile
                       │
                       ▼
                📥 Read Back Profile
                       │
                       ▼
                ✅ Verify Empty Scope
```

> ⚠️ Operators should validate the resulting Blueprint, conversion warnings, and target group selection before approving destructive migration actions.

---

# 🩺 Troubleshooting

## ❌ `jamf-cli` Test Fails

Open **Connections → jamf-cli** and select:

> **Test jamf-cli**

Review:

- Executable path
- Executable source
- Version output
- Standard error
- Exit code

A CLI diagnostic failure does not necessarily prevent native Platform API operations.

---

## 🤷 `jamf-cli` Has No Blueprint Commands

This can occur when a CLI release does not expose the Blueprint functionality required by the utility.

The application inspects CLI capabilities before attempting Blueprint creation.

When compatible CLI commands are unavailable:

> 🛟 **Native Platform API Blueprint creation remains active.**

---

## ⚠️ Profile Conversion Contains Warnings

Review the conversion plan.

Warnings can indicate:

- 🧹 A payload removed by the Blueprint compatibility filter.
- ⚠️ A payload requiring a native component.
- ❓ A payload whose compatibility has not been verified.

A warning does not necessarily mean that the entire profile failed conversion.

---

## 👥 Expected Group Is Not Automatically Selected

Verify that:

- The source group exists in profile scope.
- A corresponding Platform group exists.
- The normalized group names match.
- The Platform group belongs to the expected device family/workspace.

Unknown-family Platform groups remain available but are explicitly identified.

---

## 🧯 Source Profile Could Not Be Unscoped

Review the deployment result and Unified Logging output.

The application verifies unscoping by retrieving the profile after the update.

An update is not treated as successfully unscoped merely because the API returned a successful write response.

---

## 🌐 Platform API Request Fails

Verify:

- The Platform API hostname is correct.
- The configured OAuth credentials are valid.
- The OAuth client has the required scopes.
- The target resource is available to the current Platform workspace.
- Network or proxy controls are not blocking the request.

Review the application's Unified Logging output for the associated request and response information.

---

## 📜 View Application Logs From Terminal

Historical events:

```bash
log show --predicate 'subsystem == "com.jawheelr.blueprintcreator"'
```

Recent events:

```bash
log show --last 1h --predicate 'subsystem == "com.jawheelr.blueprintcreator"'
```

Live events:

```bash
log stream --predicate 'subsystem == "com.jawheelr.blueprintcreator"'
```

---

# 📌 Project Information

| | |
|---|---|
| **Application** | Blueprint Conversion Utility |
| **Platform** | macOS |
| **API architecture** | Jamf Platform API |
| **Credential storage** | macOS Keychain |
| **Logging subsystem** | `com.jawheelr.blueprintcreator` |
| **CLI integration** | `jamf-cli` with native API fallback |
| **Distribution** | `.app` / `.pkg` / `.dmg` |

---

# ⚠️ Operational Warning

**Blueprint Conversion Utility can deploy configuration changes and remove scope from existing Jamf configuration profiles.**

Before approving a destructive migration, confirm:

1. 📄 The intended source profile.
2. 🧩 The converted payload set.
3. ⚠️ Any excluded or unverified payloads.
4. 👥 The destination Platform group or groups.
5. 🔀 The selected distribution strategy.
6. 🧯 The intended source-profile disposition.

> 🧪 **Test the complete migration workflow in a controlled Jamf environment before using it against production profiles.**

---

## 🧭 Blueprint Conversion Utility

### **Convert → Review → Deploy → Verify**

Built for migrating Jamf configuration profiles to Jamf Blueprints while keeping the operator in control of scope, compatibility, deployment, and source-profile disposition.
