# MuscleBuildingRecorder Project Overview

## Project Purpose
MuscleBuildingRecorder (筋トレ記録アプリ) is a comprehensive iOS and watchOS workout tracking application designed for strength training enthusiasts. The app tracks workout sessions, heart rate data, and sensor data while providing real-time feedback through Dynamic Island and Live Activities.

## Key Features
- **Workout Phase Management**: Work/Rest timer functionality with automatic phase transitions
- **Heart Rate Monitoring**: Three-source integration (HealthKit, BLE devices, AirPods Pro)
- **Motion Sensor Data**: Accelerometer and gyroscope data collection from Apple Watch (25-100Hz sampling)
- **Core Data Persistence**: Workout sessions and exercise records saved locally
- **Live Activities**: Dynamic Island integration for real-time workout status
- **Watch-iPhone Sync**: Bidirectional communication with time synchronization
- **Data Export**: CSV/JSON export of workout data and sensor logs

## Tech Stack
- **Platform**: iOS 17.0+ and watchOS 10.0+
- **Language**: Swift 5.0
- **UI Framework**: SwiftUI
- **Data Storage**: Core Data
- **Health Integration**: HealthKit
- **Connectivity**: WatchConnectivity, CoreBluetooth
- **Real-time Updates**: ActivityKit (Live Activities)
- **Sensors**: Core Motion (CMMotionManager)
- **Development**: Xcode 16.0.1+

## Project Type
Native iOS/watchOS application using Apple's ecosystem frameworks. No external dependencies beyond Swift Package Manager for shared components.

## Team Configuration
- Team ID: MFQB3583D6
- Bundle ID (iOS): yokAppDev.MuscleBuildingRecorder
- Bundle ID (Watch): yokAppDev.MuscleBuildingRecorder.watchkitapp

## Target Environment
- **System**: Darwin (macOS)
- **Primary Development**: Xcode IDE with xcodebuild CLI
- **Version Control**: Git (v2 branch active)

## Development Status
Active development with recent updates focusing on Watch-iPhone synchronization, sensor data collection, and time sync improvements. The app is ready for TestFlight deployment.