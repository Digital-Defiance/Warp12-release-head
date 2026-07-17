# Warp 12 Release Head

Quick macOS SwiftUI front-end for [`scripts/build-all.sh`](../../scripts/build-all.sh).

<img width="1119" height="752" alt="Screenshot 2026-07-16 at 12 06 20 PM" src="https://github.com/user-attachments/assets/458ee254-1159-4082-8190-d634e0bc716b" />

Builds run in an embedded **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) PTY** under your login shell (`-bsh`, `-zsh`, …) — the same environment as Terminal.app, including `~/.zprofile`, `~/.zshrc`, rustup, and signing exports.

Passwords are injected via **environment variables** on the PTY child — not command-line args and not shell history.

| UI field | Environment variable(s) |
|----------|-------------------------|
| Apple notary | `APPLE_PASSWORD` |
| iOS .p12 | `APPLE_IOS_CERTIFICATE_PASSWORD` |
| Android | `ANDROID_KEYSTORE_PASSWORD` |

Before each build, the app captures your **login-shell environment** (`bsh -il` / `zsh -il`), sources the repo-root `.env` (via `WARP12_REPO_ROOT`), and merges GUI password overrides on top. Org identity (`APPLE_TEAM_ID`, `APPLE_BUNDLE_ID`, `GITHUB_REPO`, …) should live in `.env` — see the monorepo `.env.example`. Check the terminal for `notary env: APPLE_ID=set, APPLE_TEAM_ID=…` before the build starts.

Also sets `NONINTERACTIVE=1` so macOS publish **does not** prompt for git tag / homebrew-tap push.

| UI toggle | Effect |
|-----------|--------|
| Create git tag | off → `--no-push-tag` |
| Push homebrew-tap | off → `WARP12_PUSH_HOMEBREW_TAP=0` (local commit only) |

## Run (no Xcode)

From the monorepo root:

```bash
yarn release:build
yarn release:run
```

Or from this directory:

```bash
swift build -c release
swift run -c release
```

**Password fields typing into Terminal?** Click the app window once so it is frontmost. Or:

```bash
# Detached binary (no .app)
./run-detached.sh
# or: yarn release:detached

# Double-clickable .app (recommended)
./build-app.sh
# or: yarn release:app
#     ./build-app.sh --open   # build and launch
```

`build-app.sh` writes `Warp 12 Release.app` in this directory.

## Submodule setup

After creating a GitHub repo for this tool:

```bash
cd /path/to/Warp12
git submodule add https://github.com/Digital-Defiance/warp12-release-head.git vendor/warp12-release-head
```

Until then, this folder can live vendored in the monorepo as-is.

## Notes

- **bsh** is zsh-compatible (date formatting differs only). Use **Detect** to read macOS `UserShell`.
- **Version detect** runs `scripts/app-version.mjs print` under your **login shell** (`-il`), not the GUI process PATH. Finder-launched `.app` bundles only get `/usr/bin:/bin`, so plain `env node` fails when Node lives in nvm/Homebrew — Refresh version / Current label need the login shell.
- Leave password fields empty to use shell exports; fill them only to override.
- Signing identities / API keys still come from your profile or Keychain — the GUI only covers interactive **password** prompts.
- Child `ps` may still list env keys for your user; avoid shared-screen debugging while a build runs.
