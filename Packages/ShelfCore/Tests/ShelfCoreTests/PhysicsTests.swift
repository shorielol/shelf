import Foundation
import Testing
@testable import ShelfCore

@Suite struct PhysicsTests {
    @Test func `a dropped body lands on the floor and settles`() {
        var sim = DropSim(bodies: [DropBody(y: 0, floor: 500, rotation: 0.3)], gravity: 3200, restitution: 0.35)
        var maxY = -Double.infinity
        for _ in 0..<(60 * 4) {
            sim.step(dt: 1.0 / 60.0)
            maxY = max(maxY, sim.bodies[0].y)
        }
        #expect(maxY <= 500.0001)
        #expect(abs(sim.bodies[0].y - 500) < 0.5)
        #expect(sim.isSettled)
        #expect(abs(sim.bodies[0].rotation) < 0.01)
    }

    @Test func `delayed bodies wait before falling`() {
        var sim = DropSim(bodies: [DropBody(y: 0, floor: 500, delay: 1)], gravity: 3200, restitution: 0.3)
        for _ in 0..<30 { sim.step(dt: 1.0 / 60.0) }
        #expect(sim.bodies[0].y == 0)
        #expect(!sim.isSettled)
    }

    @Test func `a damped spring converges on its target`() {
        var spring = SpringSim(value: 0, target: 1, stiffness: 170, damping: 26)
        for _ in 0..<120 { spring.step(dt: 1.0 / 60.0) }
        #expect(abs(spring.value - 1) < 0.001)
        #expect(spring.isAtRest)
    }

    @Test func `large time steps stay stable`() {
        var spring = SpringSim(value: 0, target: 1, stiffness: 400, damping: 10)
        for _ in 0..<50 { spring.step(dt: 0.5) }
        #expect(spring.value.isFinite)
        #expect(abs(spring.value) < 10)
    }
}
