import Foundation

@MainActor
final class BuildRunner: ObservableObject {
    @Published var isRunning = false
    @Published var repoRoot = ""
    @Published var detectedVersion = ""
    @Published var loginShellPath = ""

    weak var terminalCoordinator: BuildTerminalView.Coordinator?

    init() {
        repoRoot = Self.findWarp12Root()?.path ?? ""
        loginShellPath = ShellEnvironment.detectLoginShell()
        Task { await refreshDetectedVersion() }
    }

    func detectLoginShell() {
        loginShellPath = ShellEnvironment.detectLoginShell()
        persistLoginShell()
    }

    func persistLoginShell() {
        ShellEnvironment.saveLoginShell(
            loginShellPath.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func refreshDetectedVersion() async {
        guard !repoRoot.isEmpty else {
            detectedVersion = ""
            return
        }
        let script = URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("scripts/app-version.mjs")
        guard FileManager.default.fileExists(atPath: script.path) else {
            detectedVersion = ""
            return
        }

        let root = repoRoot
        let version: String = await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", script.path, "print"]
            process.currentDirectoryURL = URL(fileURLWithPath: root)
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return (String(data: data, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return ""
            }
        }.value

        detectedVersion = version
    }

    func cancel() {
        terminalCoordinator?.cancelLaunch()
        isRunning = false
    }

    func start(
        nextMinor: Bool,
        nextBuild: Bool,
        explicitVersion: String,
        createGitTag: Bool,
        pushHomebrewTap: Bool,
        appleNotaryPassword: String,
        appleIosPassword: String,
        androidPassword: String
    ) {
        guard !isRunning else { return }

        let root = repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else {
            terminalCoordinator?.feedStatus("error: set Warp 12 repo root\n")
            return
        }

        let buildAll = URL(fileURLWithPath: root)
            .appendingPathComponent("scripts/build-all.sh")
        guard FileManager.default.isExecutableFile(atPath: buildAll.path) else {
            terminalCoordinator?.feedStatus("error: not executable: \(buildAll.path)\n")
            return
        }

        let trimmedVersion = explicitVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        var args: [String] = []
        if nextMinor || nextBuild {
            if nextMinor { args.append("--next-minor") }
            if nextBuild { args.append("--next-build") }
        } else if !trimmedVersion.isEmpty {
            args.append(trimmedVersion)
        } else {
            terminalCoordinator?.feedStatus("error: pick --next-minor / --next-build or enter a version\n")
            return
        }
        if !createGitTag { args.append("--no-push-tag") }

        persistLoginShell()

        let shellPath = loginShellPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            terminalCoordinator?.feedStatus("error: login shell not executable: \(shellPath)\n")
            return
        }

        let secrets = ShellEnvironment.parseSecrets(
            appleNotaryPassword: appleNotaryPassword,
            appleIosPassword: appleIosPassword,
            androidPassword: androidPassword
        )
        let env = ShellEnvironment.ptyEnvironment(
            createGitTag: createGitTag,
            pushHomebrewTap: pushHomebrewTap,
            secrets: secrets
        )
        let launch = BuildLaunch(
            shellPath: shellPath,
            scriptPath: buildAll.path,
            args: args,
            workingDirectory: root,
            environment: ShellEnvironment.environmentArray(env),
            secrets: secrets
        )

        isRunning = true
        terminalCoordinator?.beginBuild(
            launch: launch,
            diagnostic: ShellEnvironment.notaryDiagnostic(secrets: secrets)
        )
    }

    static func findWarp12Root() -> URL? {
        var candidates: [URL] = []
        if let cwd = FileManager.default.currentDirectoryPath as String? {
            candidates.append(URL(fileURLWithPath: cwd))
        }
        let bundle = Bundle.main.bundleURL
        candidates.append(bundle)
        candidates.append(bundle.deletingLastPathComponent())
        candidates.append(bundle.deletingLastPathComponent().deletingLastPathComponent())

        for start in candidates {
            var url = start
            for _ in 0..<10 {
                let marker = url.appendingPathComponent("scripts/build-all.sh")
                if FileManager.default.fileExists(atPath: marker.path) {
                    return url
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        return nil
    }
}
