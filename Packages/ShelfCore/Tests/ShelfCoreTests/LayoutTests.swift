import Foundation
import Testing
@testable import ShelfCore

@Suite struct LayoutTests {
    let main = DisplayKey(name: "Built-in", width: 1512, height: 982)
    let external = DisplayKey(name: "LG", width: 2560, height: 1440)

    func widget(_ kind: String, on display: DisplayKey) -> WidgetInstance {
        WidgetInstance(kind: kind, frame: Rect(x: 10, y: 10, width: 170, height: 170), display: display)
    }

    @Test func `adding and removing return new layouts`() {
        let empty = WallLayout()
        let one = empty.adding(widget("clock", on: main))
        #expect(empty.widgets.isEmpty)
        #expect(one.widgets.count == 1)
        #expect(one.removing(id: one.widgets[0].id).widgets.isEmpty)
    }

    @Test func `updating replaces only the matching widget`() {
        let a = widget("a", on: main), b = widget("b", on: main)
        let layout = WallLayout(widgets: [a, b])
        let moved = layout.updating(id: b.id) { $0.frame.x = 300 }
        #expect(moved.widgets[0] == a)
        #expect(moved.widgets[1].frame.x == 300)
        #expect(layout.widgets[1].frame.x == 10)
    }

    @Test func `widgets on a missing display fall back to the main display`() {
        let layout = WallLayout(widgets: [widget("a", on: external), widget("b", on: main)])
        let placed = layout.placement(connected: [main], main: main)
        #expect(placed.map(\.display) == [main, main])
        #expect(layout.placement(connected: [main, external], main: main).map(\.display) == [external, main])
    }

    @Test func `config values round trip through JSON`() throws {
        var w = widget("turntable", on: main)
        w.config["rpm"] = .number(45)
        w.config["skin"] = .string("walnut")
        w.config["lyrics"] = .bool(true)
        let data = try JSONEncoder().encode(WallLayout(widgets: [w]))
        let decoded = try JSONDecoder().decode(WallLayout.self, from: data)
        #expect(decoded.widgets[0] == w)
        #expect(decoded.widgets[0].config.double("rpm") == 45)
        #expect(decoded.widgets[0].config.string("skin") == "walnut")
        #expect(decoded.widgets[0].config.bool("lyrics") == true)
        #expect(decoded.widgets[0].config.string("missing", default: "x") == "x")
    }

    @Test func `store saves atomically and reads corrupt files as nil`() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = JSONFileStore<WallLayout>(url: dir.appending(path: "layout.json"))
        #expect(store.load() == nil)
        let layout = WallLayout(widgets: [widget("a", on: main)])
        try store.save(layout)
        #expect(store.load() == layout)
        try Data("{not json".utf8).write(to: store.url)
        #expect(store.load() == nil)
    }
}

@Suite struct GridSnapperTests {
    let bounds = Rect(x: 0, y: 0, width: 1000, height: 800)

    @Test func `snaps the origin to the nearest grid step`() {
        let snapper = GridSnapper(step: 8, margin: 16)
        let snapped = snapper.snap(Rect(x: 101, y: 205, width: 170, height: 170), in: bounds)
        #expect(snapped.x == 104)
        #expect(snapped.y == 208)
    }

    @Test func `keeps widgets inside the margins`() {
        let snapper = GridSnapper(step: 8, margin: 16)
        let snapped = snapper.snap(Rect(x: -50, y: 900, width: 170, height: 170), in: bounds)
        #expect(snapped.x == 16)
        #expect(snapped.maxY <= 800 - 16)
    }

    @Test func `sizes are kept but never below the minimum`() {
        let snapper = GridSnapper(step: 8, margin: 0, minimumSide: 80)
        let snapped = snapper.snap(Rect(x: 0, y: 0, width: 171, height: 20), in: bounds)
        #expect(snapped.width == 171)
        #expect(snapped.height == 80)
    }

    @Test func `widget size presets match the system widget grid`() {
        #expect(WidgetSize.small.side == (170, 170))
        #expect(WidgetSize.medium.side == (364, 170))
        #expect(WidgetSize.large.side == (364, 382))
        #expect(WidgetSize.extraLarge.side == (750, 382))
    }

    @Test func `nearest preset picks the closest size`() {
        #expect(WidgetSize.nearest(to: (360, 180), among: [.small, .medium, .large]) == .medium)
    }
}
