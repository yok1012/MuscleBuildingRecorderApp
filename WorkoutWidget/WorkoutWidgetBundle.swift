import WidgetKit
import SwiftUI

@main
struct WorkoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutWidget()
        WorkoutLiveActivity()
    }
}
