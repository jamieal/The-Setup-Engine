# The Setup Engine

A guided macOS setup workflow built with SwiftUI. Installs apps via Homebrew Cask and configures system preferences without ever touching Terminal.

## What it does

Walks you through a fresh Mac in six steps:

1. **Tools** — installs Homebrew (or detects existing install) with a friendly progress bar.
2. **Profile** — pick a curated bundle: Developer, Designer, Office, Media, or Custom.
3. **Apps** — fine-tune the list. Already-installed apps are detected and greyed out. Live brew search, ⌘K from anywhere.
4. **System** — Dock position, dark/light/auto mode, Finder toggles, 24-hour time.
5. **Review** — summary of everything that's about to change, including a heads-up for paid/freemium apps.
6. **Install** — staged progress, no terminal output. Just a clean "what's happening now" tile.

Then it tells you you're done.

## Why

The `setup.sh` from a fresh-Mac script grew up. Bash works fine when *you* run it, but it's not a thing you can hand to a less technical friend. This is the same idea, native, and friendly.

## Status

- **Apple Silicon only** (arm64). Universal binary support is on the to-do list.
- **macOS 14 (Sonoma)+**.
- Built and signed ad-hoc, so on first launch you'll need to right-click → Open. No notarization yet — that requires an Apple Developer Program membership.
- Single-developer side project. Not a polished product. PRs and issues welcome.

## Build & run

```bash
git clone https://github.com/jamieal/The-Setup-Engine.git
cd "The-Setup-Engine"
open "The Setup Engine.xcodeproj"
```

Then ⌘R in Xcode. The Debug build includes a hidden Debug menu (toggle Homebrew "not installed", simulate failures, jump between steps).

To build a Release `.dmg` for sharing:

```bash
./scripts/release.sh
# → build/The Setup Engine.dmg
```

If you have an Apple Developer account, set `DEVELOPMENT_TEAM`, `APPLE_ID`, and `NOTARY_PASSWORD` env vars and the same script will sign + notarize.

## Architecture

Single-target SwiftUI app. No Swift Package dependencies.

- **`SetupCoordinator`** — `ObservableObject` state machine. One step enum, one navigation method, all state lives here.
- **`SetupContainerView`** — header (progress track), body (current step), footer (Back / Continue), Cmd+K overlay.
- **Step views** — `WelcomeStep`, `HomebrewStep`, `ProfileStep`, `AppsStep`, `SystemStep`, `ReviewStep`, `InstallStep`, `DoneStep`.
- **`ShellRunner`** — async shell exec with non-blocking termination handling. `runWithAdmin` uses `osascript … with administrator privileges` for the Homebrew install.
- **`AppLog`** — lightweight logger; mirrors to `~/Library/Application Support/TheSetupEngine/Logs/`. Help → Collect Diagnostic Logs bundles every log into one file and reveals it in Finder.
- **`DebugState`** — runtime debug overrides (`#if DEBUG` gated). Toggleable from a menu bar item; also reads `TSE_FORCE_NO_BREW=1` and friends from the environment.

## Logging

Three log files exist after a setup run:

| Path | Contents |
|---|---|
| `~/Library/Application Support/TheSetupEngine/Logs/setup-engine.log` | App-level structured log (categories: homebrew, install, settings, ui) |
| `/tmp/the_setup_engine_admin.log` | Output of any `osascript with administrator privileges` invocations |
| `/tmp/the_setup_engine_install.log` | Per-cask `brew install` stdout/stderr |

**Help → Collect Diagnostic Logs… (⌘⇧L)** bundles all three into a single timestamped file in `~/Library/Caches/` and reveals it in Finder.

## Safety notes

The app runs a few commands as root via `osascript with administrator privileges`. Every privileged command:

- Hardcodes paths (`/opt/homebrew`) — no `rm -rf "$VAR/*"` patterns
- Validates `$USER_NAME` and `$PREFIX` before any destructive operation
- Logs everything it does to `/tmp/the_setup_engine_admin.log`

The system preferences step uses `defaults write` and `killall Dock` / `killall Finder` — all non-destructive and trivially reversible from System Settings.

## License

MIT.
