# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MuscleBuildingRecorder (筋トレ記録アプリ) is a multi-platform iOS and watchOS workout tracking application for strength training. The app features real-time heart rate monitoring from multiple sources (HealthKit, Bluetooth LE heart rate monitors, and AirPods Pro), workout phase timing (Work/Rest cycles), Core Data persistence, and Live Activities for Dynamic Island.

## Build Commands

### Building the iOS App
```bash
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

### Building the Watch App
```bash
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  build
```

### Running Tests
```bash
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Building for Device (iPhone)
```bash
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

### Building for Device (Watch)
```bash
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'generic/platform=watchOS' \
  -configuration Release \
  build
```

### Listing Available Simulators
```bash
xcrun simctl list devices available
```

### Checking Available Schemes
```bash
xcodebuild -project MuscleBuildingRecorder.xcodeproj -list
```

### Running a Single Test
```bash
# Run a specific test class
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MuscleBuildingRecorderTests/TestClassName

# Run a specific test method
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MuscleBuildingRecorderTests/TestClassName/testMethodName
```

### Creating Archive for App Store/TestFlight
```bash
xcodebuild archive \
  -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -configuration Release \
  -archivePath ./build/MuscleBuildingRecorder.xcarchive \
  -destination 'generic/platform=iOS'
```

## Architecture

### Core Design Patterns

The app follows an MVVM-like architecture with shared singleton managers:

1. **SessionManager (Singleton)**: Central coordinator for workout sessions, managing workout phases (Work/Rest/Idle), cycle tracking, and Core Data persistence. Coordinates between UI, HeartRateManager, and WatchConnectivityService.

2. **HeartRateManager (Singleton)**: Abstracts heart rate data collection from three sources via the Strategy pattern. Publishes heart rate updates via Combine, calculates real-time heart rate slope (傾き) for recovery metrics, and maintains a 10-second rolling window of samples.

3. **DataController (Singleton)**: Manages Core Data stack with auto-save and change merging. Provides factory methods for Session and SetRecord entities.

4. **WatchConnectivityService (Singleton)**: Handles bidirectional communication between iPhone and Watch using WCSession. iPhone sends workout commands (start/stop/pause/resume) to Watch, and Watch sends heart rate data and workout state back to iPhone.

### Heart Rate Service Architecture

Heart rate data flows through a three-tier service abstraction:

```
HeartRateManager (facade)
    ├─ HealthKitHeartRateService (queries live HK samples)
    ├─ BLEHeartRateService (scans for BLE HR monitors)
    └─ AirPodsHeartRateService (discovers AirPods Pro via BLE)
```

All services implement `HeartRateSource` protocol and publish via `PassthroughSubject<Double, Never>`. HeartRateManager merges all three publishers and tracks samples for slope calculation.

### Watch App Architecture

The Watch app (`MuscleBuildingRecorderWatchTrue Watch App`) uses `WorkoutManager` which:
- Creates HKWorkoutSession with functionalStrengthTraining activity type
- Uses HKLiveWorkoutBuilder (watchOS 9.0+) with HKLiveWorkoutDataSource for real-time metrics
- Implements HKAnchoredObjectQuery for heart rate streaming with update handlers
- Falls back to polling via HKSampleQuery and HKObserverQuery if streaming is delayed
- Sends heart rate to iPhone via WCSession sendMessage (when reachable) or updateApplicationContext (when not reachable)

### Data Model (Core Data)

- **Session**: Top-level entity for each workout session with totalWorkSec, totalRestSec, totalVolume
- **SetRecord**: Individual work/rest periods with phase, cycleIndex, heart rate stats (hrAvg, hrMax, hrMin, hrSlopeAvg)
- **ExerciseMaster**: Pre-defined exercises with defaultLoad, defaultReps, and custom units (kg, 回, 秒, etc.)

Sessions have one-to-many relationship with SetRecords. SessionManager creates SetRecords on every phase transition and saves immediately.

### Live Activities

LiveActivityManager creates ActivityKit Live Activities displaying current workout phase, elapsed time, and heart rate in the Dynamic Island. Uses WorkoutAttributes for activity state. Activities are created when session starts, updated on phase transitions and heart rate changes, and ended when session completes.

### iPhone-Watch Communication Flow

1. **Workout Start**: iPhone SessionManager → WatchConnectivityService → Watch WorkoutManager starts HKWorkoutSession
2. **Heart Rate Updates**: Watch HKAnchoredObjectQuery → WorkoutManager → WCSession → iPhone WatchConnectivityService → HeartRateManager → SessionManager
3. **Phase Changes**: iPhone SessionManager sends pause/resume commands to Watch to maintain session state consistency

### UI Architecture

**Main Views:**
- **ContentView**: Tab-based navigation (Timer, History, Settings, Debug views)
- **MainTimerView** (20KB): Primary workout interface with section-based layout for timer display, heart rate monitoring, phase controls, and exercise input
- **HistoryView**: Displays past workouts with Core Data fetch requests
- **SettingsView**: App configuration, export options, and HealthKit permissions
- **ExerciseInputSheet**: Modal sheet for entering exercise details during workout
- **SessionSummaryView**: Full-screen summary shown after workout completion
- **WatchDebugView**: Debug panel for Watch connectivity status (DEBUG builds only)
- **AirPodsConnectionView**: Heart rate device selection and status UI

**View Patterns:**
- Environment object injection for SessionManager, HeartRateManager, DataController
- @ObservedObject for reactive UI updates from singleton managers
- Sheet presentations for data input
- Full-screen covers for summaries
- Section-based layouts for complex views like MainTimerView

## Development Requirements

- **Xcode**: 16.0.1 (26.0.1)
- **iOS Deployment Target**: 17.0
- **watchOS Deployment Target**: 10.0
- **Swift Version**: 5.0
- **Development Team**: MFQB3583D6

## Required Capabilities

### iOS App (MuscleBuildingRecorder)
- HealthKit (read heart rate, write workouts)
- Background Modes: "Uses Bluetooth LE accessories", "Background processing"
- App Groups: group.com.yourcompany.workouttracker
- Live Activities support (NSSupportsLiveActivities)

### Watch App (MuscleBuildingRecorderWatchTrue Watch App)
- HealthKit (read heart rate, write workouts)
- WatchKit App with companion app bundle identifier: yokAppDev.MuscleBuildingRecorder

## Info.plist Keys

Both iOS and Watch apps require:
- `NSHealthShareUsageDescription`: "ワークアウト中の心拍数データを読み取るために使用します"
- `NSHealthUpdateUsageDescription`: "ワークアウトセッションをHealthKitに保存するために使用します"

iOS app additionally requires:
- `NSBluetoothAlwaysUsageDescription`: "Bluetooth心拍計およびAirPods Proと接続して、リアルタイムで心拍数を測定するために使用します"
- `NSBluetoothPeripheralUsageDescription`: "Bluetooth Low Energy心拍計およびAirPods Proからデータを取得するために使用します"

## Project Structure Notes

- Main iOS app files are in `MuscleBuildingRecorder/` directory
- Watch app files are in `MuscleBuildingRecorderWatchTrue Watch App/` directory
- Some legacy files exist in `iOS/`, `watchOS/`, `Shared/` directories (likely from earlier SPM structure)
- The `.xcodeproj` uses file system synchronized groups (objectVersion 77)

## Export Functionality

The app provides data export capabilities through:
- **CSVExporter**: Exports workout sessions to CSV format with columns for date, exercise, sets, reps, weight, rest time, and heart rate metrics
- **JSONExporter**: Exports structured JSON with full session details including all SetRecords and heart rate data
- Both exporters are accessible from SettingsView and generate shareable documents

## Working with Heart Rate Data

When debugging heart rate issues:
1. Check HealthKit authorization status first (0=notDetermined, 1=sharingDenied, 2=sharingAuthorized)
2. For Watch: HKWorkoutSession must be in `.running` state before heart rate becomes available
3. AirPods heart rate requires Bluetooth permissions and only works with AirPods Pro with heart rate sensors
4. HeartRateManager uses a 10-second sliding window for slope calculation: `(n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)` returns bpm/minute

## Known Behavioral Details

- SessionManager auto-saves after every phase transition (togglePhase) and when ending session
- SetRecords are created eagerly on phase start, not on phase end
- Heart rate slope (hrSlopeAvg) is calculated continuously but only saved when SetRecord completes
- Watch sends heart rate updates via sendMessage when reachable (lower latency) or updateApplicationContext when unreachable (queued delivery)
- WorkoutManager uses multiple fallback mechanisms: HKAnchoredObjectQuery (primary), HKObserverQuery (backup), Timer-based HKSampleQuery polling (fallback)
- DataController seeds 15 default ExerciseMaster entries on first launch (胸, 背中, 脚, 肩, 腕, 体幹, 有酸素 categories)
- WorkoutPhase enum manages state transitions: Idle → Work ↔ Rest → Idle
- Live Activities update frequency: immediate on phase changes, throttled to 1Hz for heart rate updates

## Testing on Physical Devices

### iPhone Testing
1. Connect iPhone via cable
2. Select physical device in Xcode scheme
3. Ensure development team is configured (MFQB3583D6)
4. Grant HealthKit and Bluetooth permissions when prompted

### Watch Testing
1. Ensure Watch is paired with iPhone
2. Both devices must be connected and unlocked
3. Watch app will automatically install when iPhone app is installed
4. Use WatchDebugView on iPhone to monitor Watch connection status

### Testing Heart Rate on Watch
- Use the "Manual Trigger" button in Watch app to force a heart rate query
- Check debugMessage and sessionState for diagnostic info
- lastHeartRateTime shows data freshness ("Live" = <1.5s, "Xs ago" = older)
- queryStatus shows current query state and most recent heart rate value

## Common Issues

### Build Issues
If build fails, try in order:
```bash
# Clean build folder
xcodebuild clean -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder

# Delete derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Core Data Issues
- WorkoutModel.xcdatamodeld contains the data model
- If schema changes are needed, create a new model version
- DataController.loadInitialData() seeds ExerciseMaster entities on first launch

### Watch Communication Issues
- Check WCSession.isReachable status
- Watch must be on wrist, unlocked, and app must be in foreground for sendMessage to work
- If Watch is not reachable, updateApplicationContext will queue updates for delivery when reachable

### Heart Rate Not Appearing on Watch
1. Verify HKWorkoutSession state is "Running" (check sessionState in UI)
2. Check if consecutiveEmptyResults is increasing (indicates no samples being received)
3. Verify Watch has heart rate sensor active (green light on back of Watch should be on)
4. Try manual trigger: debugTriggerHeartRate() queries last 24h of samples
5. Check authorization: healthStore.authorizationStatus(for: heartRateType) must be .sharingAuthorized

### Watch App Icon Issues
If "Missing Icons" error occurs during TestFlight upload:
1. Ensure all icon sizes are present in `MuscleBuildingRecorderWatchTrue Watch App/Assets.xcassets/AppIcon.appiconset/`
2. Add `CFBundleIconFiles` array to Watch app's Info.plist
3. Set `GENERATE_INFOPLIST_FILE = NO` in build settings
4. Exclude Info.plist from File System Synchronized Groups in project.pbxproj
