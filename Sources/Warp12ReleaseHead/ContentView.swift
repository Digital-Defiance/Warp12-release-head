import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runner: BuildRunner

    @State private var nextMinor = false
    @State private var nextBuild = true
    @State private var explicitVersion = ""
    @State private var createGitTag = true
    @State private var pushHomebrewTap = true
    @State private var appleNotaryPassword = ""
    @State private var appleIosPassword = ""
    @State private var androidPassword = ""
    @State private var accountUserShell = ""

    private var releaseTagPreview: String {
        let version = previewReleaseVersion
        guard !version.isEmpty else { return "v?" }
        return version.hasPrefix("v") ? version : "v\(version)"
    }

    /// Same precedence as build-all: bump flags, then explicit, else current.
    private var previewReleaseVersion: String {
        let current = runner.detectedVersion
        if nextMinor || nextBuild {
            return Self.bumpedVersion(from: current, nextMinor: nextMinor, nextBuild: nextBuild)
        }
        let explicit = explicitVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        return current
    }

    private static func bumpedVersion(from current: String, nextMinor: Bool, nextBuild: Bool) -> String {
        let parts = current.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var major = parts[0], minor = parts[1], build = parts[2]
        if nextMinor {
            minor += 1
            build = 0
        } else if nextBuild {
            build += 1
        }
        return "\(major).\(minor).\(build)"
    }

    var body: some View {
        // HSplitView (not NavigationSplitView sidebar) so SecureFields receive keyboard
        // focus when the app is launched from Terminal via `swift run`.
        HSplitView {
            Form {
                Section("Login shell") {
                    TextField("Login shell (bsh, zsh, …)", text: $runner.loginShellPath)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Detect") {
                            runner.detectLoginShell()
                        }
                        if !accountUserShell.isEmpty {
                            Text("Account UserShell: \(accountUserShell)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Text("Build runs in an embedded terminal (PTY) under your login shell — same as Terminal.app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Warp 12 repo") {
                    TextField("Repo root", text: $runner.repoRoot)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Detect") {
                            if let root = BuildRunner.findWarp12Root() {
                                runner.repoRoot = root.path
                                Task { await runner.refreshDetectedVersion() }
                            }
                        }
                        Button("Refresh version") {
                            Task { await runner.refreshDetectedVersion() }
                        }
                    }
                    if !runner.detectedVersion.isEmpty {
                        Text("Current: v\(runner.detectedVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !runner.repoRoot.isEmpty {
                        Text("Current: (could not detect — need node on login-shell PATH)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Version bump") {
                    Toggle("--next-minor", isOn: $nextMinor)
                    Toggle("--next-build", isOn: $nextBuild)
                    TextField("Or explicit 0.minor.build", text: $explicitVersion)
                        .textFieldStyle(.roundedBorder)
                    Text("Bump flags take precedence over the version field (same as build-all.sh).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Publish (macOS DMG)") {
                    Text("Release tag: \(releaseTagPreview) (after bump, if any)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Create git tag on HEAD", isOn: $createGitTag)
                    Toggle("Push homebrew-tap to origin", isOn: $pushHomebrewTap)
                    Text("Create tag uses --no-push-tag when off. Push tap uses WARP12_PUSH_HOMEBREW_TAP=0 for local-only commit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Secrets (environment only)") {
                    SecureField("Apple notary — app-specific password (optional)", text: $appleNotaryPassword)
                        .textFieldStyle(.roundedBorder)
                    SecureField("iOS .p12 export password", text: $appleIosPassword)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Android upload keystore", text: $androidPassword)
                        .textFieldStyle(.roundedBorder)
                    Text("Your shell uses App Store Connect API key notarization. Leave the Apple notary field blank — filling it made Tauri prefer password auth and 401.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button(runner.isRunning ? "Running…" : "Run build-all") {
                            runner.start(
                                nextMinor: nextMinor,
                                nextBuild: nextBuild,
                                explicitVersion: explicitVersion,
                                createGitTag: createGitTag,
                                pushHomebrewTap: pushHomebrewTap,
                                appleNotaryPassword: appleNotaryPassword,
                                appleIosPassword: appleIosPassword,
                                androidPassword: androidPassword
                            )
                        }
                        .disabled(runner.isRunning || runner.repoRoot.isEmpty)

                        if runner.isRunning {
                            Button("Cancel", role: .destructive) {
                                runner.cancel()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            BuildTerminalView(runner: runner)
                .equatable()
                .frame(minWidth: 280)
        }
        .navigationTitle("Warp 12 Release")
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            if accountUserShell.isEmpty {
                accountUserShell = ShellEnvironment.accountLoginShell() ?? ""
            }
            if runner.repoRoot.isEmpty, let root = BuildRunner.findWarp12Root() {
                runner.repoRoot = root.path
                Task { await runner.refreshDetectedVersion() }
            }
        }
        .onDisappear {
            runner.persistLoginShell()
        }
    }
}
