import Foundation

enum ShellEnvironment {
  private static let userDefaultsKey = "loginShellPath"

  /// After the shell's own login/interactive rc load: cargo PATH, GUI overrides, notary mode.
  /// Do not source ~/.zshrc / ~/.bshrc here — `bsh -il` / `zsh -il` already do that.
  private static let postRcBootstrap = """
    [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"; \
    export PATH="$HOME/.cargo/bin:$PATH"; \
    export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"; \
    export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"; \
    [[ -n "${WARP12_GUI_APPLE_PASSWORD:-}" ]] && export APPLE_PASSWORD="$WARP12_GUI_APPLE_PASSWORD"; \
    [[ -n "${WARP12_GUI_APPLE_IOS_PASSWORD:-}" ]] && export APPLE_IOS_CERTIFICATE_PASSWORD="$WARP12_GUI_APPLE_IOS_PASSWORD"; \
    [[ -n "${WARP12_GUI_ANDROID_PASSWORD:-}" ]] && export ANDROID_KEYSTORE_PASSWORD="$WARP12_GUI_ANDROID_PASSWORD"; \
    export APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID APPLE_SIGNING_IDENTITY \
      APPLE_IOS_CERTIFICATE_PASSWORD ANDROID_KEYSTORE_PASSWORD \
      APPLE_API_KEY APPLE_API_ISSUER APPLE_API_KEY_PATH 2>/dev/null || true; \
    if [ -n "${APPLE_API_KEY:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then \
      if [ -z "${APPLE_API_KEY_PATH:-}" ] && [ -f "$HOME/private_keys/AuthKey_${APPLE_API_KEY}.p8" ]; then \
        export APPLE_API_KEY_PATH="$HOME/private_keys/AuthKey_${APPLE_API_KEY}.p8"; \
      fi; \
      if [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -f "${APPLE_API_KEY_PATH}" ]; then \
        unset APPLE_PASSWORD; \
        export WARP12_NOTARY_MODE=api-key; \
      fi; \
    fi; \
    if [ -z "${WARP12_NOTARY_MODE:-}" ]; then \
      export WARP12_NOTARY_MODE=apple-id-password; \
    fi;
    """

  /// Resolved login shell: saved preference, account record, then fallbacks.
  static func detectLoginShell() -> String {
    if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
       isExecutableShell(saved) {
      return saved
    }
    if let account = accountLoginShell(), isExecutableShell(account) {
      return account
    }
    let processShell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
    if isExecutableShell(processShell) {
      return processShell
    }
    for candidate in bshCandidates() where isExecutableShell(candidate) {
      return candidate
    }
    return "/bin/zsh"
  }

  static func saveLoginShell(_ path: String) {
    UserDefaults.standard.set(path, forKey: userDefaultsKey)
  }

  /// argv[0] for a login shell (`-bsh`, `-zsh`, …) on a PTY.
  static func loginExecName(shellPath: String) -> String {
    let name = URL(fileURLWithPath: shellPath).lastPathComponent
    return "-\(name)"
  }

  /// `shell -il -c …` — the shell loads its own rc; we only patch afterward.
  static func loginShellArgs(scriptPath: String, buildArgs: [String], shellPath: String = "") -> [String] {
    _ = shellPath
    return ["-il", "-c", buildCommand(scriptPath: scriptPath, args: buildArgs)]
  }

  /// Minimal PTY env. Profiles come from the login shell, not from us re-sourcing files.
  static func ptyEnvironment(
    createGitTag: Bool,
    pushHomebrewTap: Bool,
    secrets: BuildSecrets
  ) -> [String: String] {
    var env: [String: String] = [:]
    let borrowKeys = ["HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR"]
    for key in borrowKeys {
      if let value = ProcessInfo.processInfo.environment[key] {
        env[key] = value
      }
    }
    if env["HOME"] == nil {
      env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
    }
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    if env["LANG"] == nil {
      env["LANG"] = "en_US.UTF-8"
    }
    ensureToolPaths(&env)
    env["NONINTERACTIVE"] = "1"
    env["WARP12_GUI_BUILD"] = "1"
    if !createGitTag {
      env["WARP12_CREATE_GIT_TAG"] = "0"
    }
    if !pushHomebrewTap {
      env["WARP12_PUSH_HOMEBREW_TAP"] = "0"
    }
    if let notary = secrets.appleNotaryPassword {
      env["WARP12_GUI_APPLE_PASSWORD"] = notary
    }
    if let ios = secrets.appleIosPassword {
      env["WARP12_GUI_APPLE_IOS_PASSWORD"] = ios
    }
    if let android = secrets.androidPassword {
      env["WARP12_GUI_ANDROID_PASSWORD"] = android
    }
    return env
  }

  static func notaryDiagnostic(secrets: BuildSecrets) -> String {
    let pass = secrets.appleNotaryPassword.map { "gui-field(\($0.count) chars — ignored if API key present)" } ?? "none"
    let ios = secrets.appleIosPassword.map { "gui-override(\($0.count) chars)" } ?? "from-shell-rc"
    return "notary: GUI Apple password=\(pass); iOS.p12=\(ios). Shell loads its own rc via -il.\n"
  }

  static func buildCommand(scriptPath: String, args: [String]) -> String {
    let invocation = ([scriptPath] + args)
      .map(shellQuote)
      .joined(separator: " ")
    return """
    \(postRcBootstrap) \
    echo "rustc: $(command -v rustc) ($(rustc -vV 2>/dev/null | awk '/^host:/{print $2}'))"; \
    echo "shell-env: TEAM=${APPLE_TEAM_ID:-UNSET} ID=${APPLE_ID:-UNSET}"; \
    echo "notary mode: ${WARP12_NOTARY_MODE:-unknown} | PASS=$([ -n "${APPLE_PASSWORD:-}" ] && echo set || echo unset) API_KEY=${APPLE_API_KEY:+set}"; \
    if [ "${WARP12_NOTARY_MODE:-}" = "api-key" ]; then \
      :; \
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then \
      :; \
    else \
      echo "error: need App Store Connect API key or Apple ID+app-specific password+TEAM."; \
      exit 1; \
    fi; \
    exec \(invocation)
    """
  }

  static func environmentArray(_ env: [String: String]) -> [String] {
    env.map { key, value in
      "\(key)=\(value)"
    }
  }

  static func parseSecrets(
    appleNotaryPassword: String,
    appleIosPassword: String,
    androidPassword: String
  ) -> BuildSecrets {
    BuildSecrets(
      appleNotaryPassword: trimmedOrNil(appleNotaryPassword),
      appleIosPassword: trimmedOrNil(appleIosPassword),
      androidPassword: trimmedOrNil(androidPassword)
    )
  }

  static func accountLoginShell() -> String? {
    let user = NSUserName()
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
    process.arguments = [".", "-read", "/Users/\(user)", "UserShell"]
    process.standardOutput = pipe
    process.standardError = Pipe()
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let text = String(data: data, encoding: .utf8) else { return nil }
      for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("UserShell:") {
          return trimmed.replacingOccurrences(of: "UserShell:", with: "")
            .trimmingCharacters(in: .whitespaces)
        }
      }
      return nil
    } catch {
      return nil
    }
  }

  private static func trimmedOrNil(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func ensureToolPaths(_ env: inout [String: String]) {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let cargoBin = "\(home)/.cargo/bin"
    var parts = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
      .split(separator: ":")
      .map(String.init)
      .filter { $0 != cargoBin }
    let extras = [
      "\(home)/.local/bin",
      "/opt/homebrew/bin",
      "/opt/homebrew/sbin",
      "/usr/local/bin",
    ]
    for extra in extras.reversed() {
      if FileManager.default.fileExists(atPath: extra), !parts.contains(extra) {
        parts.insert(extra, at: 0)
      }
    }
    if FileManager.default.fileExists(atPath: cargoBin) {
      parts.insert(cargoBin, at: 0)
    }
    env["PATH"] = parts.joined(separator: ":")
    env["CARGO_HOME"] = env["CARGO_HOME"] ?? "\(home)/.cargo"
    env["RUSTUP_HOME"] = env["RUSTUP_HOME"] ?? "\(home)/.rustup"
  }

  private static func bshCandidates() -> [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return [
      "\(home)/bin/bsh",
      "\(home)/.local/bin/bsh",
      "/usr/local/bin/bsh",
      "/opt/homebrew/bin/bsh",
    ]
  }

  private static func isExecutableShell(_ path: String) -> Bool {
    guard !path.isEmpty else { return false }
    return FileManager.default.isExecutableFile(atPath: path)
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

struct BuildSecrets: Equatable {
  let appleNotaryPassword: String?
  let appleIosPassword: String?
  let androidPassword: String?
}
