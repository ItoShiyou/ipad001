import CoreGraphics
import XCTest
@testable import ScoreStand

final class RenderKeyTests: XCTestCase {
    /// 1ポイント未満の揺れで再描画が走らないこと。
    /// マルチタスクのリサイズ中に描き直しが連発すると譜めくりが詰まる。
    func testSubPointDifferencesProduceEqualKeys() {
        let a = RenderKey(size: CGSize(width: 1024.2, height: 768.4), scale: 2)
        let b = RenderKey(size: CGSize(width: 1024.1, height: 768.3), scale: 2)
        XCTAssertEqual(a, b)
    }

    func testDifferentSizesProduceDifferentKeys() {
        let a = RenderKey(size: CGSize(width: 1024, height: 768), scale: 2)
        let b = RenderKey(size: CGSize(width: 1280, height: 768), scale: 2)
        XCTAssertNotEqual(a, b)
    }

    func testPixelSizeAppliesScale() {
        let key = RenderKey(size: CGSize(width: 100, height: 50), scale: 3)
        XCTAssertEqual(key.pixelSize, CGSize(width: 300, height: 150))
    }
}
