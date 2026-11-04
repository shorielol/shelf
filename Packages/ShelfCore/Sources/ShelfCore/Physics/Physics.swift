import Foundation

/// A damped spring integrated with semi-implicit Euler and sub-stepping, so big frame gaps stay stable.
public struct SpringSim: Sendable, Equatable {
    public var value: Double
    public var target: Double
    public var velocity: Double = 0
    public let stiffness: Double
    public let damping: Double

    static let maxSubstep = 1.0 / 240.0
    static let restThreshold = 0.0005

    public init(value: Double, target: Double, stiffness: Double = 170, damping: Double = 26) {
        self.value = value
        self.target = target
        self.stiffness = stiffness
        self.damping = damping
    }

    public mutating func step(dt: Double) {
        let clamped = min(dt, 0.1)
        let steps = max(1, Int((clamped / Self.maxSubstep).rounded(.up)))
        let h = clamped / Double(steps)
        for _ in 0..<steps {
            let force = -stiffness * (value - target) - damping * velocity
            velocity += force * h
            value += velocity * h
        }
    }

    public var isAtRest: Bool {
        abs(value - target) < Self.restThreshold && abs(velocity) < Self.restThreshold * 10
    }
}

/// A body falling onto a floor, used by the onboarding "drop". y grows downward, like the screen.
public struct DropBody: Sendable, Equatable {
    public var y: Double
    public var velocity: Double = 0
    public let floor: Double
    public var rotation: Double
    public var delay: Double
    public var landed = false
    var spin: SpringSim

    public init(y: Double, floor: Double, rotation: Double = 0, delay: Double = 0) {
        self.y = y
        self.floor = floor
        self.rotation = rotation
        self.delay = delay
        self.spin = SpringSim(value: rotation, target: 0, stiffness: 120, damping: 14)
    }
}

public struct DropSim: Sendable, Equatable {
    public var bodies: [DropBody]
    public let gravity: Double
    public let restitution: Double

    /// Bounces slower than this stop, so bodies settle instead of buzzing.
    static let restVelocity = 60.0

    public init(bodies: [DropBody], gravity: Double = 3200, restitution: Double = 0.35) {
        self.bodies = bodies
        self.gravity = gravity
        self.restitution = restitution
    }

    public mutating func step(dt: Double) {
        bodies = bodies.map { advance($0, dt: dt) }
    }

    private func advance(_ body: DropBody, dt: Double) -> DropBody {
        var body = body
        if body.delay > 0 {
            body.delay -= dt
            return body
        }
        if !body.landed || body.velocity != 0 {
            body.velocity += gravity * dt
            body.y += body.velocity * dt
            if body.y >= body.floor {
                body.y = body.floor
                body.velocity = abs(body.velocity) < Self.restVelocity / restitution ? 0 : -body.velocity * restitution
                body.landed = true
            }
        }
        if body.landed {
            body.spin.step(dt: dt)
            body.rotation = body.spin.value
        }
        return body
    }

    public var isSettled: Bool {
        bodies.allSatisfy { $0.delay <= 0 && $0.landed && $0.velocity == 0 && $0.y == $0.floor && $0.spin.isAtRest }
    }
}
