import AppKit
import Combine
import Foundation
import Testing
@testable import PrivacyAirPods

/// 메뉴 막대 아이콘 시계 대역. 예약은 하나만 두고, advance는 예약 시각 순서대로 작업을 실행함.
@MainActor
final class ManualMenuBarClock: MenuBarIconClock {
    var now: TimeInterval = 5_000
    private var action: (@MainActor @Sendable () -> Void)?
    private var due = TimeInterval.infinity
    private var period: TimeInterval?
    private(set) var fires = 0

    var isScheduled: Bool { action != nil }
    /// 반복 예약이 돌 때만 간격을 줌. 정지 구간에 프레임 반복 예약이 남지 않는지 볼 때 씀.
    var repeatingInterval: TimeInterval? { period }

    func schedule(after delay: TimeInterval, repeating interval: TimeInterval?,
                  _ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
        period = interval
        due = now + max(0, delay)
    }

    func cancel() {
        action = nil
        period = nil
        due = .infinity
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let run = action, due <= target {
            now = due
            fires += 1
            if let period { due += period } else { cancel() }
            run()
        }
        now = target
    }
}

/// 동작 줄이기 설정 대역. 알림과 함께 값을 바꿈.
@MainActor
final class MotionFlag {
    var reduce = false
}

/// 저장소 Resources/MenuBarIcon. 빌드 산출물이 아니라 원본 프레임을 직접 읽음.
private let repoFrameDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/MenuBarIcon", isDirectory: true)

@MainActor
private func repoFrames() throws -> [NSImage] {
    try #require(MenuBarIconModel.loadFrames(in: repoFrameDirectory))
}

@MainActor
private func makeIcon(_ h: ProtectionHarness, frames: [NSImage]?, clock: ManualMenuBarClock,
                      motion: MotionFlag, workspace: NotificationCenter) -> MenuBarIconModel {
    MenuBarIconModel(frames: frames, protection: h.model.$protected.eraseToAnyPublisher(), clock: clock,
                     reduceMotion: { motion.reduce }, workspaceNotifications: workspace)
}

/// 실제 AppModel의 보호 상태를 관찰하는 메뉴 막대 아이콘. 시계와 동작 줄이기만 대역임.
@MainActor
@Suite(.serialized)
struct MenuBarIconTests {
    @Test func frameRhythmFollowsTheTenSecondCycleFromProtectionStart() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let clock = ManualMenuBarClock()
        let icon = makeIcon(h, frames: try repoFrames(), clock: clock, motion: MotionFlag(), workspace: NotificationCenter())
        try await h.protect()
        #expect(icon.isProtected)
        #expect(icon.frame == 0)

        // 0.05초 간격으로 21초를 본 프레임. 전환 중 화면 값은 마지막 갱신(최대 한 프레임 간격 전) 시점의 흐림임.
        // 전환 한가운데(흐림 0.5, 프레임 12)는 한 간격 늦은 값까지 허용해 10...13으로 봄. 이징 위치가 0.2나 0.8이면 5나 19 근처라 걸림.
        var byStep = [icon.frame]
        for _ in 1...420 {
            clock.advance(by: 0.05)
            byStep.append(icon.frame)
        }
        func at(_ t: TimeInterval) -> Int { byStep[Int((t / 0.05).rounded())] }

        #expect(at(0) == 0)
        #expect((10...13).contains(at(1)))
        #expect(at(2) == 24)
        #expect(at(4) == 24)
        #expect(at(7) == 24)
        #expect((10...13).contains(at(8)))
        #expect(at(9) == 0)
        #expect(at(9.5) == 0)
        #expect(at(10) == 0)
        #expect((10...13).contains(at(11)))
        // 두 번째 주기(10~20초)도 같은 위상으로 반복함.
        #expect(at(12) == 24)
        #expect(at(17) == 24)
        #expect((10...13).contains(at(18)))
        #expect(at(19) == 0)
        #expect(at(20) == 0)
        #expect((10...13).contains(at(21)))

        // 흐려짐은 0~2초, 걷힘은 7~9초에 단조롭게 진행함. 최대 흐림과 선명 구간은 흔들리지 않음.
        #expect(zip(byStep[0...40], byStep[1...41]).allSatisfy { $0 <= $1 })
        #expect(byStep[40...140].allSatisfy { $0 == 24 })
        #expect(zip(byStep[140...180], byStep[141...181]).allSatisfy { $0 >= $1 })
        #expect(byStep[180...200].allSatisfy { $0 == 0 })
    }

    @Test func stationaryPhasesHaveNoFifteenFpsSchedule() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let clock = ManualMenuBarClock()
        let icon = makeIcon(h, frames: try repoFrames(), clock: clock, motion: MotionFlag(), workspace: NotificationCenter())
        try await h.protect()

        clock.advance(by: 1)
        #expect(icon.frame > 0 && icon.frame < 24)
        #expect(clock.repeatingInterval == MenuBarBlurRhythm.frameInterval)

        clock.advance(by: 2)
        // 3초: 최대 흐림 정지 구간. 반복 예약이 없고 한 번짜리 예약만 남음.
        #expect(clock.repeatingInterval == nil)
        #expect(clock.isScheduled)
        let firesBeforeHold = clock.fires
        clock.advance(by: 3.5)
        #expect(clock.fires == firesBeforeHold)

        clock.advance(by: 2)
        #expect(clock.repeatingInterval == MenuBarBlurRhythm.frameInterval)

        clock.advance(by: 1)
        // 9.5초: 선명 정지 구간.
        #expect(clock.repeatingInterval == nil)
        #expect(clock.isScheduled)
        #expect(icon.frame == 0)
    }

    @Test func stoppingProtectionReleasesFrameAndAllScheduledWork() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let clock = ManualMenuBarClock()
        let icon = makeIcon(h, frames: try repoFrames(), clock: clock, motion: MotionFlag(), workspace: NotificationCenter())
        try await h.protect()
        clock.advance(by: 1)
        #expect(icon.frame > 0 && icon.frame < 24)

        // 전환 한가운데서 끄면 즉시 선명 프레임이 되고 예약도 남지 않아야 함.
        h.model.stopProtection()
        #expect(!icon.isProtected)
        #expect(icon.frame == 0)
        #expect(!clock.isScheduled)
        let firesAfterStop = clock.fires
        clock.advance(by: 30)
        #expect(clock.fires == firesAfterStop)
        #expect(icon.frame == 0)
        #expect(icon.fallbackSymbolName == "eye")
    }

    @Test func reduceMotionHoldsTheBlurredFrameWithoutTimers() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let clock = ManualMenuBarClock()
        let motion = MotionFlag()
        motion.reduce = true
        let workspace = NotificationCenter()
        let icon = makeIcon(h, frames: try repoFrames(), clock: clock, motion: motion, workspace: workspace)
        try await h.protect()
        #expect(icon.frame == 24)
        #expect(!clock.isScheduled)
        clock.advance(by: 20)
        #expect(icon.frame == 24)
        #expect(clock.fires == 0)

        // 실행 중 설정을 끄면 바로 리듬이 시작됨. 다시 켜면 최대 흐림에 멈춤.
        motion.reduce = false
        workspace.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(icon.frame == 0)
        #expect(clock.repeatingInterval == MenuBarBlurRhythm.frameInterval)

        motion.reduce = true
        workspace.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(icon.frame == 24)
        #expect(!clock.isScheduled)
    }

    @Test func missingFrameFallsBackToSymbolWithoutTimers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<MenuBarBlurRhythm.frameCount where index != 7 {
            let name = String(format: "blur-%02d.png", index)
            try FileManager.default.copyItem(at: repoFrameDirectory.appendingPathComponent(name),
                                             to: directory.appendingPathComponent(name))
        }
        #expect(MenuBarIconModel.loadFrames(in: directory) == nil)

        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let clock = ManualMenuBarClock()
        let icon = MenuBarIconModel(frames: MenuBarIconModel.loadFrames(in: directory),
                                    protection: h.model.$protected.eraseToAnyPublisher(), clock: clock,
                                    reduceMotion: { false }, workspaceNotifications: NotificationCenter())
        try await h.protect()
        #expect(icon.fallbackSymbolName == "eye.slash.fill")
        #expect(icon.labelSource == .symbol("eye.slash.fill"))
        #expect(!clock.isScheduled)
        h.model.stopProtection()
        #expect(icon.fallbackSymbolName == "eye")
    }

    @Test func repoFramesReadAsColorAtHalfPixelSize() throws {
        let frames = try repoFrames()
        #expect(frames.count == 25)
        #expect(frames.allSatisfy { $0.size == NSSize(width: 22, height: 18) && !$0.isTemplate })
    }

    @Test func labelPicksFrameImageWhenFramesLoaded() async throws {
        let h = try ProtectionHarness()
        defer { h.model.stopProtection() }
        let icon = makeIcon(h, frames: try repoFrames(), clock: ManualMenuBarClock(), motion: MotionFlag(),
                            workspace: NotificationCenter())
        #expect(icon.labelSource == .frame(0))
    }

    @Test func versionLineShowsBuildOrDevelopmentRun() {
        #expect(MenuBarVersionText.make(short: "0.1.3", build: "4") == "버전 0.1.3 (빌드 4)")
        #expect(MenuBarVersionText.make(short: nil, build: nil).contains("개발 실행"))
        #expect(MenuBarVersionText.make(short: "0.1.3", build: "").contains("개발 실행"))
    }
}
