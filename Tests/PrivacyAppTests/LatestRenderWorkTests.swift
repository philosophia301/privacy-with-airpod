import Testing
import CoreImage
@testable import PrivacyAirPods

@Test func busyRendererKeepsOnlyNewestPendingFrameAndAngle() {
    let work = LatestRenderWork<Int>()
    #expect(work.submit(1))
    #expect(work.take() == 1)
    for value in 2...100 { #expect(!work.submit(value)) }
    #expect(work.take() == 100)
    #expect(work.take() == nil)
    #expect(work.submit(101))
    #expect(work.take() == 101)
}

@Test func stoppingRendererDiscardsPendingWorkAndRejectsNewFrames() {
    let work = LatestRenderWork<Int>()
    #expect(work.submit(1))
    work.close()
    #expect(work.take() == nil)
    #expect(!work.submit(2))
    #expect(work.take() == nil)
}

@MainActor
@Test func stalledMainActorReceivesOnlyNewestCompletedFrame() async {
    var received: [Int] = []
    await withCheckedContinuation { continuation in
        let delivery = LatestFrameDelivery<Int> { value in
            received.append(value)
            continuation.resume()
        }
        // 이 동기 구간 동안 표시 작업은 메인 액터에 진입할 수 없음.
        for value in 1...100 { delivery.submit(value) }
    }
    #expect(received == [100])
}

@MainActor
@Test func hiddenPreviewDropsOldFrameAndVisiblePreviewUsesLatestSettings() async {
    let input = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    var received: [RenderSettings] = []
    let renderer = PreviewRenderer()
    renderer.setVisible(true)
    renderer.request(input, settings: RenderSettings(angle: 10, radius: 20))
    renderer.setVisible(false)
    renderer.setVisible(true)
    let latest = RenderSettings(angle: 70, radius: 20)

    await withCheckedContinuation { continuation in
        renderer.onFrame = { frame in
            received.append(frame.settings)
            continuation.resume()
        }
        renderer.request(input, settings: latest)
    }

    #expect(received == [latest])
    renderer.stop()
}

@Test func spaceBoundaryDiscardsWaitingWorkWithoutClosingTheRenderer() {
    let work = LatestRenderWork<Int>()
    #expect(work.submit(1))
    #expect(work.take() == 1)
    #expect(!work.submit(2))
    work.discardPending()
    #expect(work.take() == nil)
    #expect(work.submit(3))
    #expect(work.take() == 3)
}
