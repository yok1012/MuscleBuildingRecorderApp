# MuscleBuildingRecorder Codebase Structure

## Project Root Structure
```
MuscleBuildingRecorder/
├── MuscleBuildingRecorder/                    # iOS App
├── MuscleBuildingRecorderWatchTrue Watch App/ # Active Watch App
├── MuscleBuildingRecorderWatch Watch App/     # Legacy Watch App (unused)
├── MuscleBuildingRecorderTests/               # iOS Unit Tests
├── MuscleBuildingRecorderUITests/             # iOS UI Tests
├── MuscleBuildingRecorderWatchTrue Watch AppTests/   # Watch Unit Tests
├── MuscleBuildingRecorderWatchTrue Watch AppUITests/ # Watch UI Tests
├── Shared/                                    # SPM Shared Code
├── MuscleBuildingRecorder.xcodeproj/          # Xcode Project
├── Package.swift                              # SPM Configuration
├── CLAUDE.md                                  # AI Assistant Instructions
├── README.md                                  # Project Documentation
└── Various .md files                          # Technical documentation
```

## iOS App Structure (`MuscleBuildingRecorder/`)

### Core Architecture Components

#### `/ViewModels/`
- `SessionManager.swift` - Central workout coordinator (Singleton)
  - Manages workout phases (Idle/Work/Rest)
  - Handles Core Data persistence
  - Coordinates with all services
  - Tracks time and cycles

#### `/Services/`
Heart Rate Management:
- `HeartRateManager.swift` - Facade aggregating all HR sources
- `HeartRateService.swift` - Protocol definition
- `HealthKitHeartRateService.swift` - HealthKit integration
- `BLEHeartRateService.swift` - Bluetooth LE devices
- `AirPodsHeartRateService.swift` - AirPods Pro sensors

Connectivity & Logging:
- `WatchConnectivityService.swift` - Watch-iPhone communication
- `SensorLogManager.swift` - CSV sensor data logging
- `LiveActivityManager.swift` - Dynamic Island updates

#### `/Views/`
Main Views:
- `ContentView.swift` - App root view
- `MainTimerView.swift` - Primary workout timer interface
- `SessionSummaryView.swift` - Post-workout results
- `SettingsView.swift` - App configuration
- `HistoryView.swift` - Workout history list
- `HistoryDetailView.swift` - Individual workout details

Supporting Views:
- `ExerciseInputSheet.swift` - Exercise data entry
- `WorkoutLiveActivity.swift` - Live Activity widget
- `MultiDayExportView.swift` - Data export interface
- `GraphView.swift` - Heart rate visualization

#### `/Models/`
- `WorkoutPhase.swift` - Enum for workout states
- `HeartRateLog.swift` - In-memory HR logging (not persisted)
- `LiveActivityContext.swift` - Dynamic Island data model

#### `/Data/`
- `DataController.swift` - Core Data stack management
- `WorkoutModel.xcdatamodeld/` - Core Data schema
  - Entities: Session, SetRecord, ExerciseMaster

#### `/Utils/`
- `CSVExporter.swift` - CSV export functionality
- `JSONExporter.swift` - JSON export functionality
- `ShareSheet.swift` - iOS share functionality

#### `/Resources/`
- `Assets.xcassets/` - Images and colors
- `Info.plist` - App configuration
- `MuscleBuildingRecorderApp.swift` - App entry point

## Watch App Structure (`MuscleBuildingRecorderWatchTrue Watch App/`)

### Core Components
- `ContentView.swift` - Main Watch UI
- `WorkoutManager.swift` - HKWorkoutSession management
  - HealthKit workout tracking
  - Heart rate monitoring
  - Phase synchronization

### Sensor Collection
- `WatchMotionStreamer.swift` - Accelerometer/gyroscope data
  - Configurable sampling rates
  - Batch sending optimization
  - File transfer management

- `BackgroundSensorRecorder.swift` - Background execution support

### Supporting Files
- `Assets.xcassets/` - Watch app icons (all sizes)
- `Info.plist` - Watch app configuration
- `MuscleBuildingRecorderWatchTrueApp.swift` - Watch app entry

## Shared Components (`Shared/`)
- `Sources/` - Shared Swift code
- SPM target: `WorkoutTimerCore`
- Used for cross-platform code sharing

## Data Flow Architecture

### Workout Lifecycle
1. **Start**: iPhone → SessionManager → WatchConnectivityService → Watch
2. **Heart Rate**: Watch → HealthKit → WCSession → iPhone → UI
3. **Sensor Data**: Watch → CMMotionManager → Batch → CSV files
4. **Phase Changes**: Bidirectional sync with timestamps
5. **End**: Save to Core Data, HealthKit, display summary

### Communication Patterns
- **Real-time**: WCSession.sendMessage (when reachable)
- **Queued**: updateApplicationContext (unreachable fallback)
- **Files**: transferFile for sensor logs
- **Time Sync**: Timestamp-based state synchronization

### Data Persistence
- **Core Data**: Sessions, SetRecords, ExerciseMaster
- **CSV Files**: `Documents/SensorLogs/[type]_yyyyMMdd.csv`
- **In-Memory**: HeartRateLog during sessions only
- **HealthKit**: Workout sessions and samples

## Key Design Patterns
1. **Singleton**: All managers use shared instances
2. **Observer**: Combine @Published for reactive UI
3. **Facade**: HeartRateManager aggregates sources
4. **Factory**: DataController creates entities
5. **Delegation**: WCSession and HKWorkoutSession delegates

## File Naming Conventions
- Views: `*View.swift` or `*Sheet.swift`
- Managers: `*Manager.swift`
- Services: `*Service.swift`
- Models: Descriptive names without suffix
- Tests: `*Tests.swift`

## Important Notes
- File system uses synchronized groups (Xcode 16+)
- Info.plist manually maintained (not auto-generated)
- Watch app requires all icon sizes for App Store
- No external dependencies beyond Apple frameworks
- Japanese text hardcoded (no localization files)