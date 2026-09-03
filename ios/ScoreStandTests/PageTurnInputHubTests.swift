import XCTest
@testable import ScoreStand

@MainActor
private final class StubSource: PageTurnInputSource {
    let kind: InputSourceKind
    var isActive = false
    var handler: ((PageTurnEvent) -> Void)?

    init(kind: InputSourceKind) { self.kind = kind }
    func activate() { isActive = true }
    func deactivate() { isActive = false }

    func emit(_ command: PageTurnCommand, at date: Date = Date()) {
        handler?(PageTurnEvent(command, from: kind, at: date))
    }
}

@MainActor
final class PageTurnInputHubTests: XCTestCase {
    func testForwardsEvents() {
        let hub = PageTurnInputHub()
        let source = StubSource(kind: .tap)
        hub.register(source)

        var received: [PageTurnCommand] = []
        hub.onEvent = { received.append($0.command) }

        source.emit(.next)
        XCTAssertEqual(received, [.next])
    }

    /// 1回の操作が二重に届くのを落とす。連打を塞いではいけない。
    func testCooldownDropsDuplicateWithinWindow() {
        let hub = PageTurnInputHub()
        hub.cooldown = 0.2
        let source = StubSource(kind: .tap)
        hub.register(source)

        var count = 0
        hub.onEvent = { _ in count += 1 }

        let start = Date()
        source.emit(.next, at: start)
        source.emit(.next, at: start.addingTimeInterval(0.05))
        XCTAssertEqual(count, 1, "クールダウン内の重複は落とす")

        source.emit(.next, at: start.addingTimeInterval(0.5))
        XCTAssertEqual(count, 2, "十分に間が空いたら通す")
    }

    /// 設計原則 P6。人間が手で位置を直した直後に、自動が上書きしてはならない。
    func testManualInputSuppressesAutomaticInput() {
        let hub = PageTurnInputHub()
        hub.manualOverrideWindow = 3.0
        let manual = StubSource(kind: .tap)
        let automatic = StubSource(kind: .timeline)
        hub.register(manual)
        hub.register(automatic)

        var sources: [InputSourceKind] = []
        hub.onEvent = { sources.append($0.source) }

        let start = Date()
        manual.emit(.next, at: start)
        automatic.emit(.next, at: start.addingTimeInterval(1.0))
        XCTAssertEqual(sources, [.tap], "手動直後の自動入力は抑止される")

        automatic.emit(.next, at: start.addingTimeInterval(4.0))
        XCTAssertEqual(sources, [.tap, .timeline], "窓を過ぎたら自動入力も通る")
    }

    func testAutomaticInputPassesWhenNoManualInput() {
        let hub = PageTurnInputHub()
        let automatic = StubSource(kind: .timeline)
        hub.register(automatic)

        var count = 0
        hub.onEvent = { _ in count += 1 }
        automatic.emit(.next)
        XCTAssertEqual(count, 1)
    }

    func testActiveKindsReflectsActivation() {
        let hub = PageTurnInputHub()
        let tap = StubSource(kind: .tap)
        let keyboard = StubSource(kind: .keyboard)
        hub.register(tap)
        hub.register(keyboard)

        XCTAssertTrue(hub.activeKinds.isEmpty)
        hub.activateAll()
        XCTAssertEqual(Set(hub.activeKinds), [.tap, .keyboard])
        hub.deactivateAll()
        XCTAssertTrue(hub.activeKinds.isEmpty)
    }
}
