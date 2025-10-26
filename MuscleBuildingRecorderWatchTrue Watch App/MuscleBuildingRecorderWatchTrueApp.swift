//
//  MuscleBuildingRecorderWatchTrueApp.swift
//  MuscleBuildingRecorderWatchTrue Watch App
//
//  Created by kiichi yokokawa on 2025/10/05.
//

#if os(watchOS)
import SwiftUI

@main
struct MuscleBuildingRecorderWatchTrue_Watch_AppApp: App {
    @StateObject private var motionStreamer = WatchMotionStreamer.shared
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .environmentObject(motionStreamer)
        }
    }
}
#endif
