# Repository Guidelines

## Project Structure & Module Organization
`RepoMonitor/` contains the app source. Keep UI in `Views/`, state and orchestration in `ViewModels/`, domain models in `Models/`, and external/process integrations in `Services/`. App entry is `RepoMonitor/RepoMonitorApp.swift`. Assets live in `RepoMonitor/Assets.xcassets`; app metadata and entitlements are alongside the target files. Packaging helpers live in `scripts/`, and release bundles are written to `build/`. SwiftPM build output goes to `.build/`.

## Build, Test, and Development Commands
Use SwiftPM for local validation:

- `swift build` builds the app target for debugging.
- `swift build -c release` produces an optimized binary in `.build/release/`.
- `bash scripts/bundle.sh` builds release and creates `build/RepoMonitor.app`.
- `open build/RepoMonitor.app` launches the packaged app.

If you have full Xcode installed, you may also build from `RepoMonitor.xcodeproj`; the current environment may only have Command Line Tools.

## Coding Style & Naming Conventions
Use standard Swift formatting with 4-space indentation. Prefer `struct` for SwiftUI views and value models, `final class` for observable coordinators, and `actor` for isolated process wrappers like Git access. Type names use UpperCamelCase (`RepoMonitorService`); properties and methods use lowerCamelCase (`startPeriodicScan`). Name files after the primary type they define. Keep `// MARK:` sections concise and only where they improve navigation.

No formatter or linter is committed in this repository, so follow Xcode’s default Swift style and keep diffs small.

## Testing Guidelines
There is no test target yet. Add new tests under a `RepoMonitorTests/` target when changing non-trivial logic in `Models/` or `Services/`. Prefer XCTest. Use names like `testScan_WhenRepoIsBehind_SetsBehindCount()`. Run tests with `swift test` once the test target exists. For UI-heavy changes, include manual verification notes for menu bar behavior, settings persistence, and scan results.

## Commit & Pull Request Guidelines
Git history is not available in this workspace snapshot, so use short imperative commit subjects such as `Fix auto-start scanning` or `Harden config decoding`. Keep commits focused. PRs should include a brief summary, linked issue if applicable, manual test steps, and screenshots for visible UI changes.

## Security & Configuration Tips
Do not commit personal repo paths or generated state files. User configuration is stored under `~/.config/repo-monitor/`, typically `config.json` and `state.json`. Preserve remote URL sanitization and avoid logging secrets from Git remotes or fetch errors.

## App Export

everytime you add any function or fixed a bug or made modify to the project, build a new app.