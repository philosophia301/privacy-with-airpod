import XCTest
@testable import PrivacyCore

final class InertialProbeTests: XCTestCase {
    private let down = SIMD3<Double>(0, 0, -1)

    private func feed(_ probe: inout InertialProbe, _ time: Double, _ metresPerSecondSquared: Double = 1) {
        probe.ingest(timestamp: time, acceleration: SIMD3(0, 0, metresPerSecondSquared / 9.80665), gravity: down)
    }

    func testKnownUpwardAccelerationThenDeceleration() {
        var probe = InertialProbe()
        // a(t)=2-2t, v(t)=2t-t², z(t)=t²-t³/3. 2초 후 v=0, z=4/3임.
        for step in 0...8 {
            let t = Double(step) / 4
            feed(&probe, t, 2 - 2 * t)
        }
        XCTAssertEqual(probe.displacement.z, 4.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(probe.velocity.z, 0, accuracy: 1e-12)
        XCTAssertEqual(probe.displacement.x, 0)
        XCTAssertEqual(probe.displacement.y, 0)
        XCTAssertEqual(probe.duration, 2)
        XCTAssertEqual(probe.sampleCount, 9)
    }

    func testRotatingGravityAxesPreservesVerticalProjectionAndRejectsHorizontalComponent() {
        var probe = InertialProbe()
        let directions: [SIMD3<Double>] = [SIMD3(0, 0, -2), SIMD3(-3, 0, 0), SIMD3(0, -4, 0)]
        let accelerations: [SIMD3<Double>] = [SIMD3(7, 0, 1), SIMD3(1, 7, 0), SIMD3(0, 1, 7)]
        for i in 0...2 {
            probe.ingest(timestamp: Double(i) / 4, acceleration: accelerations[i] / 9.80665, gravity: directions[i])
        }
        XCTAssertEqual(probe.displacement.z, 0.125, accuracy: 1e-12)
        XCTAssertEqual(probe.velocity, SIMD3(0, 0, 0.5))
        XCTAssertEqual(probe.displacement.x, 0)
        XCTAssertEqual(probe.displacement.y, 0)
    }

    func testDuplicateReverseAndExcessiveGapInvalidateUntilReset() {
        for invalidTime in [0.25, 0.1, 0.500001] {
            var probe = InertialProbe()
            feed(&probe, 0)
            feed(&probe, 0.25)
            XCTAssertGreaterThan(probe.displacement.z, 0)
            feed(&probe, invalidTime)
            assertInvalid(probe)
            feed(&probe, 0.75)
            assertInvalid(probe)
            probe.reset()
            feed(&probe, 20)
            XCTAssertEqual(probe.sampleCount, 1)
            XCTAssertEqual(probe.duration, 0)
            XCTAssertEqual(probe.displacement, .zero)
        }
    }

    func testNonfiniteInputAndZeroGravityInvalidate() {
        let cases: [(Double, SIMD3<Double>, SIMD3<Double>)] = [
            (.nan, .zero, down), (.infinity, .zero, down),
            (0.5, SIMD3(.nan, 0, 0), down), (0.5, SIMD3(0, .infinity, 0), down),
            (0.5, .zero, SIMD3(0, 0, .nan)), (0.5, .zero, .zero),
            (0.5, SIMD3(0, 0, Double.greatestFiniteMagnitude), down)
        ]
        for (timestamp, acceleration, gravity) in cases {
            var probe = InertialProbe()
            feed(&probe, 0)
            feed(&probe, 0.25)
            probe.ingest(timestamp: timestamp, acceleration: acceleration, gravity: gravity)
            assertInvalid(probe)
        }
        var firstInvalid = InertialProbe()
        feed(&firstInvalid, .nan)
        feed(&firstInvalid, 0)
        assertInvalid(firstInvalid)
    }

    func testTenSecondBoundaryCompletesAndFreezes() {
        var probe = InertialProbe()
        for step in 0...40 { feed(&probe, Double(step) / 4) }
        XCTAssertEqual(probe.duration, 10)
        XCTAssertEqual(probe.sampleCount, 41)
        XCTAssertEqual(probe.displacement.z, 50, accuracy: 1e-10)
        XCTAssertTrue(probe.status.hasPrefix("완료:"))
        feed(&probe, 10.25)
        XCTAssertEqual(probe.duration, 10)
        XCTAssertEqual(probe.sampleCount, 41)
        XCTAssertEqual(probe.displacement.z, 50, accuracy: 1e-10)
    }

    func testCrossingTenSecondsInvalidatesWithoutPartialIntegration() {
        var probe = InertialProbe()
        for step in 0...39 { feed(&probe, Double(step) / 4) }
        feed(&probe, 9.875)
        feed(&probe, 10.125)
        assertInvalid(probe)
        XCTAssertTrue(probe.status.contains("10초"))
    }

    private func assertInvalid(_ probe: InertialProbe, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(probe.status.hasPrefix("무효:"), file: file, line: line)
        XCTAssertEqual(probe.displacement, .zero, file: file, line: line)
        XCTAssertEqual(probe.velocity, .zero, file: file, line: line)
        XCTAssertEqual(probe.duration, 0, file: file, line: line)
        XCTAssertEqual(probe.sampleCount, 0, file: file, line: line)
    }
}
