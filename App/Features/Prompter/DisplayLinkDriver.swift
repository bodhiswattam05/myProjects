import QuartzCore
import UIKit

/// Calls back once per screen refresh (up to 120 Hz on ProMotion). Drives the prompter's
/// scrolling so it moves every frame by elapsed time — no `Timer` stepping.
@MainActor
final class DisplayLinkDriver: NSObject {
    private var link: CADisplayLink?
    private var onFrame: ((CFTimeInterval) -> Void)?

    var isRunning: Bool { link != nil }

    func start(_ onFrame: @escaping (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Must be called when the prompter goes away: the display link retains its target.
    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}
