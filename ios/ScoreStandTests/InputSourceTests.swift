import UIKit
import XCTest
@testable import ScoreStand

@MainActor
final class TapInputSourceTests: XCTestCase {
    private func makeSource() -> (TapInputSource, () -> [PageTurnCommand]) {
        let source = TapInputSource()
        source.activate()
        var received: [PageTurnCommand] = []
        source.handler = { received.append($0.command) }
        return (source, { received })
    }

    /// 左右それぞれ3分の1を判定領域にしている。手元を見ずに触れてもめくれる幅が要るため。
    func testLeftThirdGoesBack() {
        let (source, received) = makeSource()
        source.handleTap(at: 100, width: 1000)
        XCTAssertEqual(received(), [.previous])
    }

    func testRightThirdGoesForward() {
        let (source, received) = makeSource()
        source.handleTap(at: 900, width: 1000)
        XCTAssertEqual(received(), [.next])
    }

    /// 中央は無反応。譜面を確かめようとして触れた指でめくらないため。
    func testCenterDoesNothing() {
        let (source, received) = makeSource()
        source.handleTap(at: 500, width: 1000)
        XCTAssertTrue(received().isEmpty)
    }

    func testInactiveSourceIgnoresTaps() {
        let (source, received) = makeSource()
        source.deactivate()
        source.handleTap(at: 900, width: 1000)
        XCTAssertTrue(received().isEmpty)
    }
}

@MainActor
final class KeyboardInputSourceTests: XCTestCase {
    func testDefaultKeysMapToPageTurns() {
        let source = KeyboardInputSource()
        source.activate()
        var received: [PageTurnCommand] = []
        source.handler = { received.append($0.command) }

        XCTAssertTrue(source.handleKey(UIKeyCommand.inputRightArrow))
        XCTAssertTrue(source.handleKey(UIKeyCommand.inputLeftArrow))
        XCTAssertEqual(received, [.next, .previous])
    }

    func testUnmappedKeyIsNotConsumed() {
        let source = KeyboardInputSource()
        source.activate()
        XCTAssertFalse(source.handleKey("q"))
    }

    func testInactiveSourceConsumesNothing() {
        let source = KeyboardInputSource()
        XCTAssertFalse(source.handleKey(UIKeyCommand.inputRightArrow))
    }
}
