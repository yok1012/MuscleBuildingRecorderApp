import ActivityKit
import Foundation
import SwiftUI

struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String
        var elapsedTime: String
        var heartRate: Int
        var exercise: String
        var category: String
        var cycleIndex: Int
    }

    var startTime: Date
}