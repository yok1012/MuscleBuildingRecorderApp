# Copilot Instructions for MuscleBuildingRecorder

## Build, Test, and Lint Commands

Use `xcodebuild` for building and testing.

### iOS App
```bash
# Build for Simulator (iPhone 16)
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Build for Physical Device (Release)
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

### Watch App
```bash
# Build for Simulator (Apple Watch Series 10)
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  build
```

### Testing
```bash
# Run all iOS tests
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a specific test case
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MuscleBuildingRecorderTests/TestClassName/testMethodName
```

### Utility
```bash
# Clean build folder
xcodebuild clean -project MuscleBuildingRecorder.xcodeproj -scheme MuscleBuildingRecorder

# Clear derived data (fix unexplained build failures)
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

## High-Level Architecture

### Core Components
- **SessionManager (iOS) / WorkoutManager (watchOS)**: Central singletons managing workout state (Idle/Work/Rest), timer logic, and connectivity.
- **HeartRateManager**: Facade aggregating HR from HealthKit (Watch), BLE, and AirPods. Uses `PassthroughSubject` and `@Published` properties.
- **WatchConnectivityService**: Handles bidirectional communication.
  - **Real-time**: `sendMessage` (throttled).
  - **State sync**: `updateApplicationContext` (fallback).
  - **Bulk data**: `transferFile` (sensor logs).
- **DataController**: Core Data stack with auto-save (3s intervals). Manages `Session`, `SetRecord`, and `ExerciseMaster` entities.
- **SensorLogManager**: Manages CSV logging for high-frequency motion data (accel/gyro).

### Data Flow
1. **Workout Start**: iPhone `SessionManager` -> `WatchConnectivity` -> Watch `WorkoutManager` -> `HKWorkoutSession`.
2. **Heart Rate**: Watch `HKQuery` -> `WCSession` -> iPhone `HeartRateManager` -> UI/LiveActivity.
3. **Phase Change**: iPhone triggers pause/resume -> Watch updates `HKLiveWorkoutBuilder`.
4. **Sensor Data**: Watch `CMMotionManager` buffers samples -> batches sent to iPhone -> saved to CSV.

## Key Conventions

### Swift & SwiftUI
- **Style**: Swift 5.9+, 4-space indentation. PascalCase for types, camelCase for members.
- **Concurrency**: Use `async`/`await` where possible, but respect existing `Combine` pipelines in service layers.
- **Memory Management**: Strictly use `[weak self]` in closures (especially `Timer`, `WCSession` delegates, and Combine sinks).
- **UI**: Prefer functional, declarative SwiftUI. Use `@StateObject`, `@ObservedObject` appropriately.

### Watch Connectivity & HealthKit
- **WCSessionDelegate**: MUST be declared directly in the class definition (not in an extension) for reliable iOS/Watch interop.
- **Heart Rate**: Fallback hierarchy is Anchored Query -> Observer Query -> Polling.
- **Throttling**: Heart rate updates min 1s, workout state min 3-5s to prevent flooding `WCSession`.

### File System & Logging
- **Sensor Logs**: Stored in `Documents/SensorLogs/[type]_yyyyMMdd.csv`.
- **File APIs**: Use modern `FileHandle` APIs (`close()`, `seekToEnd()`, `write(contentsOf:)`).
- **Target Membership**: Ensure new files are added to the correct target (iOS, watchOS, or Shared).

### Operational Rules
- **Preserve Logic**: Do not rewrite `HeartRateService` or `WatchConnectivity` logic without deep understanding; these are critical and fragile paths.
- **APP_STATUS.md**: Check this file for known bugs and recent stability fixes before starting tasks.
- **Simulators**: You cannot launch a GUI simulator. Use `xcodebuild` to build and test.
