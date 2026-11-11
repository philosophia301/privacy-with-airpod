import Foundation
import Testing
@testable import PrivacyAirPods

@MainActor
@Test func coreMotionCallbackAcceptsBackgroundQueueAndDeliversErrorOnMainActor() async {
    let service = MotionService()
    let handler = service.makeHandler(generation: 0)
    let message = await withCheckedContinuation { continuation in
        service.onError = { message in continuation.resume(returning: message) }
        DispatchQueue.global().async {
            handler(nil, NSError(domain: "MotionCallbackTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "background error"]))
        }
    }
    #expect(message == "background error")
    service.stop()
}
