import Foundation
import Testing
@testable import PrivacyCore

/// 25Hz 합성 머리 움직임을 SeatPresence에 넣고 이벤트와 발생 시각을 모으는 입력 대역임.
/// 가속도는 높이의 2차 미분으로 만들며 판정 규칙은 복제하지 않음.
private struct Stream {
    struct Recorded: Equatable {
        let event: SeatPresence.Event
        let time: Double
    }

    var presence: SeatPresence
    var recorded: [Recorded] = []
    /// 마지막으로 넣은 표본의 시각임. 다음 재생의 기준 시각으로 씀.
    var time: Double = 0
    private let interval = 1.0 / 25

    var events: [SeatPresence.Event] {
        recorded.map(\.event)
    }

    init(presence: SeatPresence = SeatPresence()) {
        self.presence = presence
        feed(timestamp: 0, vertical: 0)
    }

    /// vertical은 위쪽 양수 m/s²임. 중력은 아래 방향 (0, 0, -1)으로 고정함.
    /// Core Motion 관례대로 위로 가속하면 사용자 가속도가 중력과 같은 쪽(-z)을 가리킴.
    mutating func feed(timestamp: Double, vertical: Double) {
        let acceleration = SIMD3<Double>(0, 0, -vertical / 9.80665)
        if let event = presence.ingest(timestamp: timestamp, acceleration: acceleration,
                                       gravity: SIMD3(0, 0, -1)) {
            recorded.append(Recorded(event: event, time: timestamp))
        }
    }

    /// seconds 동안 25Hz 표본을 만들어 넣음. sample은 표본 번호(1부터)와 재생 시작부터의 시각을 받아
    /// 표본의 시각 offset과 수직 가속도를 돌려줌. nil을 주면 그 번호의 표본은 빠짐.
    mutating func playSamples(seconds: Double,
                       sample: (Int, Double) -> (offset: Double, vertical: Double)?) {
        let start = time
        let count = Int((seconds / interval).rounded())
        for index in 0..<count {
            let local = Double(index + 1) * interval
            guard let made = sample(index + 1, local) else { continue }
            feed(timestamp: start + made.offset, vertical: made.vertical)
        }
        time = start + Double(count) * interval
    }

    /// seconds 동안 profile을 따르는 표본을 넣음. bias는 g 단위 일정 가속도이고 skipping 번호의 표본은 뺌.
    mutating func play(seconds: Double, bias: Double = 0, skipping: ClosedRange<Int>? = nil,
                       profile: (Double) -> Double) {
        playSamples(seconds: seconds) { index, local in
            if skipping?.contains(index) == true { return nil }
            return (local, profile(local) + bias * 9.80665)
        }
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

/// 걸음 한 번은 0.48초(25Hz 12표본)이며 5, 6번 표본에서 +5 m/s² 착지가 남.
/// 나머지 표본은 -1 m/s²이라 한 걸음의 평균이 0임.
private func heelStrikeGait(_ t: Double) -> Double {
    let index = Int((t * 25).rounded()) % 12
    return index == 5 || index == 6 ? 5 : -1
}

private func combined(_ first: @escaping (Double) -> Double, _ second: @escaping (Double) -> Double) -> (Double) -> Double {
    { first($0) + second($0) }
}

private func shifted(_ profile: @escaping (Double) -> Double, by offset: Double) -> (Double) -> Double {
    { profile($0 + offset) }
}

// MARK: 일어섬

@Test func risingBy045mIn12sReportsStoodUpBeforeRiseEnds() throws {
    var stream = Stream()
    stream.rest(2)
    let riseStart = stream.time
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.45, over: 1.2))
    let riseEnd = stream.time
    stream.rest(2)
    #expect(stream.events == [.stoodUp])
    #expect(stream.presence.posture == .standing)
    // 자리 비움 3초 기준이 상승 끝 이후에 시작되지 않도록 상승 중에 일어섬이 나와야 함.
    let stood = try #require(stream.recorded.first?.time)
    #expect(stood > riseStart && stood < riseEnd)
}

@Test func risingBy045mIn15sReportsStoodUp() {
    var stream = Stream()
    stream.rest(2)
    stream.play(seconds: 1.5, profile: smoothMove(by: 0.45, over: 1.5))
    stream.rest(2)
    #expect(stream.events == [.stoodUp])
    #expect(stream.presence.posture == .standing)
}

@Test func sittingDownAfterStandingConfirmsBetweenOneAndTwoSecondsAfterDropStart() throws {
    var stream = Stream()
    stream.rest(2)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(1)
    let dropStart = stream.time
    let drop = smoothMove(by: -0.45, over: 1.2)
    stream.play(seconds: 0.6, profile: drop)
    // 확인 중에는 앉음 이벤트가 없고 3초 자리 비움 타이머를 붙잡는 후보만 있어야 함.
    #expect(stream.presence.isConfirmingSit)
    #expect(stream.events == [.stoodUp])
    stream.play(seconds: 0.6, profile: shifted(drop, by: 0.6))
    stream.rest(2)
    #expect(stream.events == [.stoodUp, .satDown])
    #expect(stream.presence.posture == .seated)
    let sat = try #require(stream.recorded.last?.time)
    #expect(sat - dropStart > 1.0 && sat - dropStart < 2.0)
}

@Test func sittingDownFromResetStandingReportsSatDown() {
    var presence = SeatPresence()
    presence.reset(to: .standing)
    var stream = Stream(presence: presence)
    stream.rest(2)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.45, over: 1.2))
    stream.rest(2)
    #expect(stream.events == [.satDown])
    #expect(stream.presence.posture == .seated)
}

/// 0.30m만 오른 사용자가 오래 서 있어도 같은 0.30m 하강으로 앉음이 잡혀야 함. 누적 높이에 기대지 않음을 봄.
@Test func shortRiseThenLongStandingThenSameShortDropReportsBothEvents() {
    var stream = Stream()
    stream.rest(2)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.30, over: 1.2))
    stream.rest(60)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.30, over: 1.2))
    stream.rest(2)
    #expect(stream.events == [.stoodUp, .satDown])
}

// MARK: 움직임 차이

@Test(arguments: [0.0, 1.0, 3.0, 5.0])
func seatedLeanAndStraightenAfterPauseReportsNothing(pauseSeconds: Double) {
    var stream = Stream()
    stream.rest(2)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.30, over: 1.2))
    stream.rest(pauseSeconds)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.30, over: 1.2))
    stream.rest(2)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func smallRiseAndReturnWhileSeatedReportsNothing() {
    var stream = Stream()
    stream.rest(2)
    stream.play(seconds: 1, profile: smoothMove(by: 0.10, over: 1))
    stream.play(seconds: 1, profile: smoothMove(by: -0.10, over: 1))
    stream.rest(2)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func constantBiasWhileSeatedReportsNothing() {
    var stream = Stream()
    stream.rest(20, bias: 0.005)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func standingUpWithConstantBiasReportsStoodUp() {
    var stream = Stream()
    stream.rest(2, bias: 0.005)
    stream.play(seconds: 1.2, bias: 0.005, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(2, bias: 0.005)
    #expect(stream.events == [.stoodUp])
    #expect(stream.presence.posture == .standing)
}

// MARK: 걸음

@Test func walkingForSixSecondsWhileStandingReportsNothing() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    stream.play(seconds: 6, profile: heelStrikeGait)
    stream.rest(3)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .standing)
}

@Test func sittingDownRightAfterThreeSecondsOfWalkingReportsSatDown() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    stream.play(seconds: 3, profile: heelStrikeGait)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.45, over: 1.2))
    stream.rest(3)
    #expect(stream.events == [.satDown])
    #expect(stream.presence.posture == .seated)
}

/// 걸음의 위아래 흔들림이 짝 판정 기억에 남으면 걷다 바로 앉는 완만한 하강이 가려짐. 걷는 동안 기억을 비워야 함.
@Test func gentleSitRightAfterWalkingIsNotMaskedByGaitSwings() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    stream.play(seconds: 3, profile: heelStrikeGait)
    stream.play(seconds: 1.2, profile: smoothMove(by: -0.30, over: 1.2))
    stream.rest(3)
    #expect(stream.events == [.satDown])
    #expect(stream.presence.posture == .seated)
}

@Test func dipsSuperimposedOnWalkingReportNothing() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    stream.play(seconds: 3, profile: heelStrikeGait)
    stream.play(seconds: 1.2, profile: combined(heelStrikeGait, smoothMove(by: -0.45, over: 1.2)))
    stream.play(seconds: 2, profile: heelStrikeGait)
    stream.rest(3)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .standing)
}

// MARK: 불응기

/// 앉음이 확인된 직후 1.5초 안의 일어서는 움직임은 같은 움직임의 여파로 보고 잡지 않아야 함.
@Test func riseRightAfterSitConfirmationIsNotReported() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    let drop = smoothMove(by: -0.45, over: 1.2)
    stream.play(seconds: 1.2, profile: drop)
    stream.rest(0.2)
    stream.play(seconds: 1.0, profile: smoothMove(by: 0.45, over: 1.0))
    stream.rest(3)
    #expect(stream.events == [.satDown])
    #expect(stream.presence.posture == .seated)
}

/// 초기화 직후 첫 표본부터 불응기가 시작하므로 바로 이어진 일어섬은 잡지 않아야 함.
@Test func riseRightAfterResetIsNotReported() {
    var stream = Stream()
    stream.rest(2)
    stream.presence.reset(to: .seated)
    stream.play(seconds: 1.2, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(3)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

// MARK: 취소와 잘못된 표본

@Test func dropThenImmediateRiseWithinCandidateCancelsSit() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    stream.play(seconds: 0.8, profile: smoothMove(by: -0.30, over: 0.8))
    stream.play(seconds: 0.8, profile: smoothMove(by: 0.45, over: 0.8))
    stream.rest(3)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .standing)
}

@Test func timestampGapMidRiseReportsNothingAndStaysSeated() {
    var stream = Stream()
    stream.rest(2)
    // 25Hz 표본 3~16번을 빼서 앞뒤 표본 간격을 0.5초 넘게 만듦.
    stream.play(seconds: 1.2, skipping: 3...16, profile: smoothMove(by: 0.45, over: 1.2))
    stream.rest(2)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

/// 시각이 같거나 되돌아간 표본은 상태에 반영하지 않아야 함. 큰 가속도를 실어 적분되면 속도와 판정이 어긋나게 함.
@Test func duplicateAndBackwardTimestampsMidRiseLeaveStateUntouched() {
    var stream = Stream()
    stream.rest(2)
    let profile = smoothMove(by: 0.45, over: 1.2)
    stream.play(seconds: 0.12, profile: profile)
    let before = stream.presence.velocity
    stream.feed(timestamp: stream.time, vertical: 50)
    #expect(stream.presence.velocity == before)
    stream.feed(timestamp: stream.time - 0.04, vertical: 50)
    #expect(stream.presence.velocity == before)
    stream.play(seconds: 1.08, profile: shifted(profile, by: 0.12))
    stream.rest(1)
    #expect(stream.events == [.stoodUp])
}

/// 0.5초 넘는 공백 뒤 첫 표본의 가속도를 공백 전체에 곱해 적분하면 일어섬이 잡히므로, 공백이 속도를 0으로 돌려야 함.
@Test func largeSampleAfterTimestampGapIsNotIntegratedOverTheGap() {
    var stream = Stream()
    stream.rest(2)
    stream.feed(timestamp: stream.time + 0.6, vertical: 2)
    stream.time += 0.6
    #expect(stream.presence.velocity == 0)
    stream.rest(2)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func nonfiniteSampleMidRiseReportsNothingAndStaysSeated() {
    var stream = Stream()
    stream.rest(2)
    let profile = smoothMove(by: 0.45, over: 1.2)
    stream.playSamples(seconds: 1.2) { index, local in
        (local, index == 5 ? Double.nan : profile(local))
    }
    stream.rest(2)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .seated)
}

@Test func gapDuringSitConfirmationDropsCandidate() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    // 25Hz 표본 16~30번을 빼서 0.6초 공백을 만듦. 확인 중 공백은 후보를 버려야 함.
    stream.play(seconds: 1.2, skipping: 16...30, profile: smoothMove(by: -0.45, over: 1.2))
    stream.rest(3)
    #expect(stream.events.isEmpty)
    #expect(stream.presence.posture == .standing)
}

@Test func resetDuringSitConfirmationCancelsCandidate() {
    var stream = Stream(presence: resetStanding())
    stream.rest(2)
    let drop = smoothMove(by: -0.45, over: 1.2)
    stream.play(seconds: 0.6, profile: drop)
    #expect(stream.presence.isConfirmingSit)
    stream.presence.reset(to: .standing)
    #expect(stream.presence.isConfirmingSit == false)
    stream.play(seconds: 0.6, profile: shifted(drop, by: 0.6))
    stream.rest(2)
    #expect(stream.events.isEmpty)
}

/// 서 있는 상태로 초기화한 판정기임.
private func resetStanding() -> SeatPresence {
    var presence = SeatPresence()
    presence.reset(to: .standing)
    return presence
}
