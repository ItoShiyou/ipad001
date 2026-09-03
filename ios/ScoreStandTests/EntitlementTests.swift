import XCTest
@testable import ScoreStand

final class EntitlementTests: XCTestCase {
    /// 無料枠は「機能を削る」のではなく「曲数を制限する」。
    /// 上限そのものが変わっても、この境界の意味は変わらない。
    func testFreeTierAllowsUpToLimit() {
        let free = Entitlement.free
        XCTAssertTrue(free.canAddScore(currentCount: 0))
        XCTAssertTrue(free.canAddScore(currentCount: Entitlement.freeScoreLimit - 1))
        XCTAssertFalse(free.canAddScore(currentCount: Entitlement.freeScoreLimit))
        XCTAssertFalse(free.canAddScore(currentCount: Entitlement.freeScoreLimit + 10))
    }

    func testUnlockedHasNoLimit() {
        let unlocked = Entitlement.unlocked
        XCTAssertTrue(unlocked.canAddScore(currentCount: 0))
        XCTAssertTrue(unlocked.canAddScore(currentCount: 10_000))
    }
}
