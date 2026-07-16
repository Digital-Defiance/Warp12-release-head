import Foundation

/// One-shot build invocation handed to the embedded terminal PTY.
struct BuildLaunch: Equatable, Identifiable {
    let id = UUID()
    let shellPath: String
    let scriptPath: String
    let args: [String]
    let workingDirectory: String
    let environment: [String]
    let secrets: BuildSecrets
}
