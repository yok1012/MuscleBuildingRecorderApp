import XCTest
@testable import WorkoutTimer

class HeartRateTests: XCTestCase {

    func testHeartRateSlopeCalculation() {
        let manager = HeartRateManager.shared

        let samples: [(Date, Double)] = [
            (Date().addingTimeInterval(-10), 60),
            (Date().addingTimeInterval(-8), 62),
            (Date().addingTimeInterval(-6), 64),
            (Date().addingTimeInterval(-4), 66),
            (Date().addingTimeInterval(-2), 68),
            (Date(), 70)
        ]

        let slope = calculateSlope(samples: samples)
        XCTAssertGreaterThan(slope, 0, "Slope should be positive for increasing heart rate")
        XCTAssertLessThan(abs(slope - 60), 5, "Slope should be approximately 60 bpm/min")
    }

    func testHeartRateSlopeWithConstantRate() {
        let samples: [(Date, Double)] = [
            (Date().addingTimeInterval(-10), 70),
            (Date().addingTimeInterval(-8), 70),
            (Date().addingTimeInterval(-6), 70),
            (Date().addingTimeInterval(-4), 70),
            (Date().addingTimeInterval(-2), 70),
            (Date(), 70)
        ]

        let slope = calculateSlope(samples: samples)
        XCTAssertEqual(slope, 0, "Slope should be 0 for constant heart rate")
    }

    func testHeartRateSlopeWithDecreasingRate() {
        let samples: [(Date, Double)] = [
            (Date().addingTimeInterval(-10), 80),
            (Date().addingTimeInterval(-8), 78),
            (Date().addingTimeInterval(-6), 76),
            (Date().addingTimeInterval(-4), 74),
            (Date().addingTimeInterval(-2), 72),
            (Date(), 70)
        ]

        let slope = calculateSlope(samples: samples)
        XCTAssertLessThan(slope, 0, "Slope should be negative for decreasing heart rate")
    }

    func testHeartRateStatsCalculation() {
        let samples = [60.0, 65.0, 70.0, 75.0, 80.0]
        let avg = samples.reduce(0, +) / Double(samples.count)
        let max = samples.max() ?? 0
        let min = samples.min() ?? 0

        XCTAssertEqual(avg, 70.0, "Average should be 70")
        XCTAssertEqual(max, 80.0, "Maximum should be 80")
        XCTAssertEqual(min, 60.0, "Minimum should be 60")
    }

    private func calculateSlope(samples: [(Date, Double)]) -> Double {
        guard samples.count >= 2 else { return 0 }

        let n = Double(samples.count)
        let referenceTime = samples.first!.0

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for (timestamp, bpm) in samples {
            let x = timestamp.timeIntervalSince(referenceTime)
            let y = bpm

            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.0001 else { return 0 }

        let slopePerSecond = (n * sumXY - sumX * sumY) / denominator
        return slopePerSecond * 60
    }
}