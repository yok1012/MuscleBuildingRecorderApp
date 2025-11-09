# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MuscleBuildingRecorder (筋トレ記録アプリ) is a comprehensive iOS and watchOS workout tracking application featuring real-time heart rate monitoring, motion sensor data collection, workout phase management, Core Data persistence, and Live Activities support for Dynamic Island.

## Build Commands

### Primary Build Commands
```bash
# iOS App - Simulator
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Watch App - Simulator
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  build

# iOS App - Physical Device
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build

# Watch App - Physical Device
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'generic/platform=watchOS' \
  -configuration Release \
  build
```

### Testing
```bash
# Run all tests
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MuscleBuildingRecorderTests/TestClassName/testMethodName
```

### Archive for App Store/TestFlight
```bash
xcodebuild archive \
  -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -configuration Release \
  -archivePath ./build/MuscleBuildingRecorder.xcarchive \
  -destination 'generic/platform=iOS'
```

### Utility Commands
```bash
# Clean build
xcodebuild clean -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder

# List available simulators (use IDs from here for -destination)
xcrun simctl list devices available

# List schemes
xcodebuild -project MuscleBuildingRecorder.xcodeproj -list

# Reset if build issues
rm -rf ~/Library/Developer/Xcode/DerivedData

# Run linter (if configured)
swiftlint lint

# Run formatter (if configured)
swiftformat .
```

### Swift Package Manager Build (Alternative)
```bash
# Build using SPM for shared components
swift build --package-path . -c debug --target WorkoutTimerCore
```

## Architecture

### Core Singleton Managers

**SessionManager** (`/ViewModels/SessionManager.swift`)
- Central workout coordinator managing phases (Idle/Work/Rest)
- Creates SetRecords on phase transitions, saves to Core Data immediately
- Maintains `lastCompletedSession` for post-workout results
- Tracks separate `totalWorkTime` and `totalRestTime`
- Coordinates with HeartRateManager, DataController, WatchConnectivityService, HeartRateLogManager

**HeartRateManager** (`/Services/HeartRateManager.swift`)
- Facade pattern aggregating three heart rate sources
- Publishes via Combine `@Published` properties
- 10-second sliding window for slope calculation (bpm/minute)
- Merges HealthKit, BLE devices, and AirPods Pro streams

**DataController** (`/Data/DataController.swift`)
- Core Data stack with auto-save (3-second intervals)
- Factory methods for Session and SetRecord creation
- Seeds 15 ExerciseMaster entries on first launch
- Background context merge handling

**WatchConnectivityService** (`/Services/WatchConnectivityService.swift`)
- Bidirectional WCSession communication
- Commands: start/stop/pause/resume workout
- Data: heart rate, workout state, sensor data
- Fallback: `updateApplicationContext` when unreachable

**SensorLogManager** (`/Services/SensorLogManager.swift`)
- CSV file management for sensor data (accel/gyro/motion/combined)
- Separate files per sensor type and day
- Real-time sample buffer for visualization (`recentSamples`)
- Multi-day ZIP export capability via MultiDayExportView
- File path: `Documents/SensorLogs/[type]_yyyyMMdd.csv`
- Session sensor data stored in `sessionSensorData` array during workout
- Note: `logDirectory` property must be internal/public for MultiDayExportView access

**HeartRateLogManager** (`/Models/HeartRateLog.swift`)
- In-memory heart rate log storage during sessions
- Not persisted to Core Data (memory only)
- Provides logs by cycle/phase for analysis
- Property access: `currentSessionLogs` (not `getLogs()`)

### Watch App Architecture

**WorkoutManager** (`MuscleBuildingRecorderWatchTrue Watch App/WorkoutManager.swift`)
- HKWorkoutSession with `functionalStrengthTraining` type
- HKLiveWorkoutBuilder for real-time metrics
- Three-tier heart rate fallback: Anchored → Observer → Polling
- Phase-specific time tracking: `currentPhaseTime`, `totalWorkTime`, `totalRestTime`
- Updates iPhone via WCSession when reachable

**WatchMotionStreamer** (`MuscleBuildingRecorderWatchTrue Watch App/WatchMotionStreamer.swift`)
- CMMotionManager for sensor data collection
- Configurable sampling (25/50/100 Hz)
- 0.5-second batch sending for battery optimization
- Buffer size limit: 1000 samples (~80KB)
- File transfer size check: 50MB limit
- Uses modern FileHandle APIs: `close()`, `seekToEnd()`, `write(contentsOf:)`
- Dictionary message format with optional sensor fields
- Error reporting to iPhone via `sendErrorToPhone()`

**BackgroundSensorRecorder** (`MuscleBuildingRecorderWatchTrue Watch App/BackgroundSensorRecorder.swift`)
- HKWorkoutSession-based background execution
- Continues sensor collection when backgrounded
- Requires `import Combine` for @Published properties
- Automatic cleanup on session end

### Data Model (Core Data)

**Entities:**
- `Session`: totalWorkSec, totalRestSec, totalVolume, startedAt, endedAt
- `SetRecord`: phase, cycleIndex, category, name, load, reps, hrAvg, hrMax, hrMin, hrSlopeAvg
- `ExerciseMaster`: category, name, defaultLoad, defaultReps, loadUnit, repsUnit

**Relationships:**
- Session ↔ SetRecords (one-to-many, cascade delete)
- SetRecords created on phase start, completed on phase end

### Heart Rate Service Hierarchy

```
HeartRateManager (Facade)
├── HealthKitHeartRateService (HKAnchoredObjectQuery)
├── BLEHeartRateService (CoreBluetooth with 180D service)
└── AirPodsHeartRateService (AirPods Pro HR sensors)
```

All implement `HeartRateSource` protocol with `PassthroughSubject<Double, Never>`.

### Communication Flow

**Workout Lifecycle:**
1. Start: iPhone SessionManager → WatchConnectivityService → Watch WorkoutManager → HKWorkoutSession
2. Heart Rate: Watch HKQuery → WCSession → iPhone HeartRateManager → UI/LiveActivity
3. Sensor Data: Watch CMMotionManager → batch → WCSession → iPhone SensorLogManager → CSV
4. Phase Change: iPhone → Watch (pause/resume) → HKLiveWorkoutBuilder
5. End: iPhone → Watch → Save HealthKit → SessionSummaryView with lastCompletedSession

**Data Sync:**
- Real-time: `sendMessage` when reachable (low latency)
- Queued: `updateApplicationContext` when unreachable
- Files: `transferFile` for pending sensor logs (JSONL format)

## Key Implementation Details

### API Migrations (iOS 17+/watchOS 10+)
- FileHandle APIs: Use `close()` not `closeFile()`, `seekToEnd()` not `seekToEndOfFile()`, `write(contentsOf:)` not `write()`
- Explicit tuple type annotations required for optionals in sensor data
- Combine framework must be imported for @Published in all ObservableObject classes
- WatchOS 9.0+ uses HKLiveWorkoutDataSource for enhanced workout tracking

### Behavioral Details
- SetRecords created eagerly on phase start, not end
- SessionManager auto-saves on every phase transition
- Heart rate slope calculated continuously, saved on SetRecord completion
- `lastCompletedSession` preserved for result display after workout
- CSV files: `Documents/SensorLogs/[sensor]_yyyyMMdd.csv` format
- Sensor timestamps in milliseconds since epoch
- WatchDebugView available in DEBUG builds only
- Live Activities throttled to 1Hz for battery

### Critical Property Access
- SensorLogManager: `logDirectory` must be internal/public (not private)
- HeartRateLogManager: Use `currentSessionLogs` property (no `getLogs()` method)
- Avoid duplicate extensions that redefine existing properties

## Common Issues and Solutions

### Watch Heart Rate Not Appearing
1. Verify HKWorkoutSession state = "Running"
2. Check authorization: `.sharingAuthorized`
3. Use "Manual Trigger" button in Watch app
4. Monitor `consecutiveEmptyResults` counter

### Build Failures
- Simulator missing: Use device IDs from `xcrun simctl list devices available`
- Icon errors: Verify all sizes in Watch app Assets.xcassets
- Clean derived data if incremental build fails
- Duplicate symbols: Check for extension redefinitions

### Core Data Changes
- Create new version in WorkoutModel.xcdatamodeld
- Never modify existing version
- DataController handles migration

### Watch Communication
- `isReachable` requires: Watch on wrist, unlocked, app foreground
- Fallback to `updateApplicationContext` for background
- Check WatchDebugView for status
- Phone-to-watch sync uses context updates with timestamp for bidirectional time sync
- Watch sends workout state changes via `sendMessage` when reachable

### Sensor Data Issues
- Check CMMotionManager availability first
- Verify sampling rate is reasonable (25-100 Hz)
- Monitor `lastError` property in WatchMotionStreamer
- Check pending file count for unsent data
- Ensure NSMotionUsageDescription in Info.plist

## Project Structure

```
MuscleBuildingRecorder/
├── MuscleBuildingRecorder/          # iOS app
│   ├── Models/                      # Data models & HeartRateLog
│   ├── ViewModels/                  # SessionManager
│   ├── Views/                       # UI components & MultiDayExportView
│   ├── Services/                    # Heart rate & sensor services
│   ├── Utils/                       # CSV/JSON exporters
│   └── Data/                        # Core Data controller
├── MuscleBuildingRecorderWatchTrue Watch App/  # Watch app
│   ├── WorkoutManager.swift         # HK workout session
│   ├── WatchMotionStreamer.swift    # Sensor collection
│   └── BackgroundSensorRecorder.swift # Background execution
├── Shared/                           # SPM shared code (WorkoutTimerCore)
└── Package.swift                     # SPM configuration
```

File system uses synchronized groups (objectVersion 77 in .pbxproj).

## Requirements

- Xcode: 16.0.1+
- iOS: 17.0+
- watchOS: 10.0+
- Swift: 5.0
- Team ID: MFQB3583D6

## Required Capabilities

**iOS App:**
- HealthKit (read HR, write workouts)
- Background Modes: Bluetooth LE, Background processing
- App Groups: group.com.yourcompany.workouttracker
- Live Activities: NSSupportsLiveActivities

**Watch App:**
- HealthKit (read HR, write workouts)
- Motion Usage: NSMotionUsageDescription
- Background Modes: workout-processing
- Bundle ID: yokAppDev.MuscleBuildingRecorder.watchkitapp

## Info.plist Required Keys

**iOS App:**
- NSHealthShareUsageDescription
- NSHealthUpdateUsageDescription
- NSBluetoothAlwaysUsageDescription
- NSBluetoothPeripheralUsageDescription
- NSSupportsLiveActivities

**Watch App:**
- NSHealthShareUsageDescription
- NSHealthUpdateUsageDescription
- NSMotionUsageDescription
- WKBackgroundModes: workout-processing
- WKCompanionAppBundleIdentifier: yokAppDev.MuscleBuildingRecorder

## Recent Updates

### v2 Branch Changes (2025-11)
- Implemented bidirectional time synchronization between Watch and iPhone
- Added automatic app launch functionality when workout starts
- Enhanced sensor data collection with session-based storage
- Improved Watch-iPhone communication reliability with timestamp-based sync