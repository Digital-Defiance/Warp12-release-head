import AppKit
import SwiftTerm
import SwiftUI

/// Embedded PTY terminal that runs `build-all.sh` under the user's login shell.
struct BuildTerminalView: NSViewRepresentable, Equatable {
    var runner: BuildRunner

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Terminal is AppKit-driven; ignore SwiftUI state churn (isRunning, version, …).
        true
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(runner: runner)
        runner.terminalCoordinator = coordinator
        return coordinator
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.autoresizingMask = [.width, .height]
        terminal.processDelegate = context.coordinator
        context.coordinator.prepare(terminal: terminal)
        terminal.feed(text: "Warp 12 Release — Run build-all to start.\n")
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        // Equatable view — avoid re-entry during terminal layout / feed updates.
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private weak var runner: BuildRunner?
        weak var terminal: LocalProcessTerminalView?
        private var launchedID: UUID?
        private var deferredLaunch: BuildLaunch?
        private var styled = false
        private var retryScheduled = false

        init(runner: BuildRunner) {
            self.runner = runner
        }

        func prepare(terminal: LocalProcessTerminalView) {
            self.terminal = terminal
            guard !styled else { return }
            terminal.font = NSFont.monospacedSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            )
            terminal.configureNativeColors()
            styled = true
        }

        func beginBuild(launch: BuildLaunch, diagnostic: String) {
            deferredLaunch = launch
            launchedID = nil
            terminal?.getTerminal().resetToInitialState()
            feedStatus(diagnostic)
            scheduleRetry()
        }

        func cancelLaunch() {
            deferredLaunch = nil
            retryScheduled = false
            terminal?.terminate()
        }

        func feedStatus(_ text: String) {
            terminal?.feed(text: text)
        }

        private func scheduleRetry() {
            guard deferredLaunch != nil, !retryScheduled else { return }
            retryScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.retryScheduled = false
                self?.retryDeferredLaunch()
            }
        }

        private func retryDeferredLaunch() {
            guard let launch = deferredLaunch,
                  let terminal,
                  terminal.bounds.width > 1,
                  terminal.bounds.height > 1 else {
                scheduleRetry()
                return
            }

            deferredLaunch = nil
            if launch.id == launchedID { return }

            if terminal.process.running {
                terminal.terminate()
            }

            let shellArgs = ShellEnvironment.loginShellArgs(
                scriptPath: launch.scriptPath,
                buildArgs: launch.args,
                shellPath: launch.shellPath
            )
            let execName = ShellEnvironment.loginExecName(shellPath: launch.shellPath)
            terminal.feed(text: "$ cd \(launch.workingDirectory)\n")
            terminal.feed(text: "$ \(launch.shellPath) -il -c '…build-all…'\n\n")

            terminal.startProcess(
                executable: launch.shellPath,
                args: shellArgs,
                environment: launch.environment,
                execName: execName,
                currentDirectory: launch.workingDirectory
            )
            launchedID = launch.id
        }

        // MARK: - LocalProcessTerminalViewDelegate

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                guard let runner else { return }
                runner.isRunning = false
                deferredLaunch = nil
                if let code = exitCode {
                    source.feed(text: "\n— exit \(code) —\n")
                } else {
                    source.feed(text: "\n— process ended —\n")
                }
                await runner.refreshDetectedVersion()
            }
        }
    }
}
