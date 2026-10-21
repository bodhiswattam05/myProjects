/// Smooths scrolling toward a moving target with a critically damped spring.
///
/// Voice-paced scrolling sets the target to the line being spoken. The spring
/// catches up smoothly when the speaker resumes and never oscillates. With
/// `allowsReverse` off it never moves backward, and it never passes the target.
public struct ScrollSpring: Sendable, Equatable {
    public var position: Double
    public var velocity: Double = 0
    /// Time, in seconds, to mostly settle on a new target. Lower is snappier.
    public var response: Double
    /// Speed cap in points per second, so catching up after a long ad-lib glides rather than jumps.
    public var maximumSpeed: Double
    public var allowsReverse: Bool

    public init(position: Double = 0, response: Double = 0.55, maximumSpeed: Double = 700, allowsReverse: Bool = false) {
        self.position = position
        self.response = response
        self.maximumSpeed = maximumSpeed
        self.allowsReverse = allowsReverse
    }

    /// Advances by `deltaTime` seconds and returns the new position.
    @discardableResult
    public mutating func step(toward target: Double, deltaTime: Double) -> Double {
        // Long frames (the app was backgrounded) are split so the integration stays stable.
        var remaining = min(max(deltaTime, 0), 0.25)
        let omega = 2 * Double.pi / max(response, 0.05)
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 120)
            remaining -= dt
            let acceleration = -omega * omega * (position - target) - 2 * omega * velocity
            velocity += acceleration * dt
            velocity = min(max(velocity, -maximumSpeed), maximumSpeed)
            if !allowsReverse { velocity = max(velocity, 0) }
            let previous = position
            position += velocity * dt
            if !allowsReverse, previous <= target, position > target {
                position = target
                velocity = 0
            }
        }
        return position
    }

    public mutating func jump(to position: Double) {
        self.position = position
        velocity = 0
    }
}
