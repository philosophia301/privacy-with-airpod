import Foundation
import Testing
@testable import PrivacyCore

/// 25Hz 합성 머리 움직임을 SeatPresence에 넣고 이벤트를 모으는 입력 대역임.
/// 가속도는 높이의 2차 미분으로 만들며 판정 규칙은 복제하지 않음.
private struct Stream {
    var presence: SeatPresence
    var events: [SeatPresence.Event] = []
    var time: Double = 0
    private let interval = 1.0 / 25

    init(presence: SeatPresence = SeatPresence()) {
        self.presence = presence
        feed(timestamp: 0, vertical: 0)
    }

    /// vertical은 위쪽 양수 m/s²임. 중력은 아래 방향 (0, 0, -1)으로 고정함.
    mutating func feed(timestamp: Double, vertical: Double) {
        let acceleration = SIMD3<Double>(0, 0, vertical / 9.80665)
        if let event = presence.ingest(timestamp: timestamp, acceleration: acceleration,
                                       gravity: SIMD3(0, 0, -1)) {
            events.append(event)
        }
    }

    /// seconds 동안 25Hz 표본을 넣고 시간을 그만큼 진행함. bias는 g 단위 일정 가속도임.
    mutating func play(seconds: Double, bias: Double = 0, skipping: ClosedRange<Int>? = nil,
                       profile: (Double) -> Double) {
        let start = time
        let count = Int((seconds / interval).rounded())
        for index in 1...count where !(skipping?.contains(index) ?? false) {
            let local = Double(index) * interval
            feed(timestamp: start + local, vertical: profile(local) + bias * 9.80665)
        }
        time = start + Double(count) * interval
    }

    mutating func rest(_ seconds: Double, bias: Double = 0) {
        play(seconds: seconds, bias: bias) { _ in 0 }
    }
}

/// 0.5*(1-cos(pi t/T))로 T초 동안 h만큼 움직이는 머리 높이의 2차 미분을 돌려줌.
/// 시작과 끝에서 가속도가 0이 아니므로 구간 경계에서 적분 오차가 남음.
private func smoothMove(by height: Double, over duration: Double) -> (Double) -> Double {
    let omega = Double.pi / duration
    return { t in 0.5 * height * omega * omega * cos(omega * t) }
}

/// 2Hz, 진폭 0.04m 수직 흔들림의 가속도임. 걸음처럼 정지가 잡히지 않는 입력을 만듦.
private func verticalShake(amplitude: Double, frequency: Double) -> (Double) -> Double {
    let omega = 2 * Double.pi * frequency
    return { t in -amplitude * omega * omega * sin(omega * t) }
}

@Test func standingUpAfterStillnessReportsOnceAndSetsStanding() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(1)
    #expect(stream.events == [.stoodUp])
    #expect(stream.presence.posture == .standing)
    #expect(abs(stream.presence.level - 0.45) < 0.05)
}

@Test func sittingDownAfterStandingReportsSatDownOnce() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.45, over: 1.2))
    stream.rest(1)
    #expect(stream.events == [.stoodUp, .satDown])
    #expect(stream.presence.posture == .seated)
}

@Test func smallRiseAndReturnWhileSeatedStaysQuiet() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 1, profile: smoothMove(by: 0.10, over: 1))
    stream.play(seconds: 1, profile: smoothMove(by: -0.10, over: 1))
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func bendingDownAndStraighteningStaysQuiet() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.30, over: 1.2))
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.30, over: 1.2))
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func standingUpWithConstantBiasStillReportsStoodUp() {
    var stream = Stream()
    stream.rest(1, bias: 0.02)
    stream.play(seconds: 1.2, bias: 0.02, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(2, bias: 0.02)
    #expect(stream.events == [.stoodUp])
    #expect(stream.presence.posture == .standing)
    // 편향이 쌓인 속도를 보정하지 못하면 높이가 0.2m 넘게 어긋남.
    #expect(abs(stream.presence.level - 0.45) < 0.05)
}

@Test func sittingDownWithConstantBiasStillReportsSatDown() {
    var stream = Stream()
    stream.rest(1, bias: 0.02)
    stream.play(seconds: 1.2, bias: 0.02, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(2, bias: 0.02)
    stream.play(seconds: 1.2, bias: 0.02, profile: smoothMove(by: -0.45, over: 1.2))
    stream.rest(2, bias: 0.02)
    #expect(stream.events == [.stoodUp, .satDown])
    #expect(stream.presence.posture == .seated)
}

/// 1.5초에 걸친 완만한 일어섬은 속도 최고점에서 가속도가 0.4m/s² 아래로 0.25초 넘게 머묾.
@Test func gentleStandingUpIsNotSplitAtPeakVelocity() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 1.5, profile: smoothMove(by: 0.45, over: 1.5))
    stream.rest(1.5)
    #expect(stream.events == [.stoodUp])
    #expect(abs(stream.presence.level - 0.45) < 0.05)
}

/// 0.30m만 오른 사용자가 오래 서 있어도 같은 0.30m 하강으로 앉음이 잡혀야 함.
@Test func shortUserSittingDownAfterLongStandingIsDetected() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.30, over: 1.2))
    stream.rest(60)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.30, over: 1.2))
    stream.rest(2)
    #expect(stream.events == [.stoodUp, .satDown])
}

@Test func constantBiasAloneReportsNothingAndKeepsLevel() {
    var stream = Stream()
    stream.rest(10, bias: 0.02)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
    #expect(stream.presence.level == 0)
}

@Test func walkingLikeShakeNeverStartsSegmentAndKeepsLevel() {
    var stream = Stream()
    stream.rest(1)
    stream.play(seconds: 6, profile: verticalShake(amplitude: 0.04, frequency: 2))
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
    #expect(stream.presence.level == 0)
}

@Test func timestampGapInsideStandingUpDiscardsSegmentWithoutEvent() {
    var stream = Stream()
    stream.rest(1)
    // 25Hz 표본 10~22번을 빼서 앞뒤 표본 간격을 0.25초 이상으로 만듦.
    stream.play(seconds: 1.2, skipping: 10...22, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
    #expect(stream.presence.level == 0)
}

@Test func repeatedTimestampInsideStandingUpDiscardsSegmentWithoutEvent() {
    var stream = Stream()
    stream.rest(1)
    let profile = smoothMove(by: 0.45, over: 1.2)
    let start = stream.time
    for index in 1...30 {
        // 5번째 표본의 시각을 4번째와 같게 두어 표본 간격을 0으로 만듦. 간격 0은 구간을 버려야 함.
        let stamp = index == 5 ? 4 : index
        stream.feed(timestamp: start + Double(stamp) / 25, vertical: profile(Double(index) / 25))
    }
    stream.time = start + 1.2
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
    #expect(stream.presence.level == 0)
}

@Test func motionSegmentLongerThanMaximumIsDiscardedWithoutEvent() {
    var stream = Stream()
    stream.rest(1)
    // 2.5초 상승 뒤 2.5초 하강은 속도가 0으로 끝나 상한 없이 적분하면 일어섬으로 잡히는 입력임.
    // 4초 상한을 넘은 구간은 높이 변화를 반영하지 않아야 함.
    stream.play(seconds: 2.5, profile: { _ in 0.5 })
    stream.play(seconds: 2.5, profile: { _ in -0.5 })
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
    #expect(stream.presence.level == 0)
}

@Test func resetToStandingThenSittingReportsSatDown() {
    var presence = SeatPresence()
    presence.reset(to: .standing)
    var stream = Stream(presence: presence)
    stream.rest(1)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.45, over: 1.2))
    stream.rest(1)
    #expect(stream.events == [.satDown])
    #expect(stream.presence.posture == .seated)
}

@Test func nonfiniteSampleInsideStandingUpDiscardsSegmentWithoutCrash() {
    var stream = Stream()
    stream.rest(1)
    let profile = smoothMove(by: 0.45, over: 1.2)
    let start = stream.time
    for index in 1...30 {
        let local = Double(index) / 25
        stream.feed(timestamp: start + local, vertical: index == 15 ? .nan : profile(local))
    }
    stream.time = start + 1.2
    stream.rest(1)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
    #expect(stream.presence.level == 0)
}
