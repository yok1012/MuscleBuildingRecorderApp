# Repository Guidelines

MuscleBuildingRecorder is a SwiftUI workout tracker for iOS and watchOS. Use this guide to keep contributions aligned with the existing architecture, tooling, and release expectations.

## Project Structure & Module Organization
- `MuscleBuildingRecorder/` hosts primary SwiftUI views (`ContentView.swift`, `MainTimerView.swift`) alongside supporting folders: `ViewModels/` for session state, `Services/` for HealthKit and heart-rate integrations, `Data/` for persistence, `Models/` for workout phases/Core Data, `LiveActivity/` for Dynamic Island widgets, and `Utils/` for exporters.
- Platform shells live in `iOS/` and `watchOS/`; cross-target assets and resources sit under `Shared/`.
- Tests mirror production code in `MuscleBuildingRecorderTests/` and `MuscleBuildingRecorderUITests/`; watch targets keep their own suites beside the app.

## Build, Test, and Development Commands
- `xed MuscleBuildingRecorder.xcodeproj` — open the project in Xcode with the correct schemes.
- `xcodebuild -scheme MuscleBuildingRecorder -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build` — perform a simulator build suitable for CI.
- `xcodebuild test -scheme MuscleBuildingRecorder -destination 'platform=iOS Simulator,name=iPhone 15 Pro'` — execute unit and UI tests.
- `rm -rf ~/Library/Developer/Xcode/DerivedData/*` — clear stale build artefacts when encountering unexplained failures.

## Coding Style & Naming Conventions
Follow Swift 5.9 defaults with four-space indentation and SwiftUI declarative patterns. Types, protocols, and enums use PascalCase; members and bindings use camelCase; feature-scoped constants may include prefixes (for example, `timerIntervalSeconds`). Group extensions near their primary type, mark shared singletons (such as `SessionManager.shared`), and run Xcode's Re-indent plus "treat warnings as errors" before pushing.

## Testing Guidelines
Rely on XCTest. Name scenarios descriptively (`testSessionTransitionsToRest()`), keep UI flows under `MuscleBuildingRecorderUITests/`, and mirror view-model coverage inside `MuscleBuildingRecorderTests/`. Prefer dependency injection or faked HealthKit services, and cap expectations with pragmatic timeouts to keep tests reliable.

## Commit & Pull Request Guidelines
Write short, imperative commit subjects (e.g., `Add heart-rate reconnect logic`) and group related changes together. Pull requests should outline the feature or fix, list verification steps (simulator, device, or unit tests), attach screenshots or screen recordings for UI updates, and call out configuration changes so reviewers can rebuild quickly.

## Security & Configuration Tips
Keep `MuscleBuildingRecorder.entitlements` synchronized with HealthKit, Bluetooth, Background Modes, and App Group requirements. Never commit provisioning profiles or personal identifiers; rely on `.xcconfig` overrides for local tweaks. Document new Info.plist keys or environment variables in the PR description and update setup docs whenever runtime requirements change.
