import XCTest
@testable import ScoreStand

/// 見開き表示で、ページ遷移直後に右ページが白く一瞬チラつく回帰の再発防止。
///
/// 原因は `displayedSecondaryPage` を遷移のたびに無条件で nil にしていたこと。
/// 新しい右ページが用意できるまで古い表示を保つべき場面で消していた。
final class PerformanceViewModelTests: XCTestCase {
    func testKeepsSecondaryPageWhenSpreadContinuesWithinScore() {
        XCTAssertFalse(
            PerformanceViewModel.shouldClearSecondaryPage(
                isTwoPageSpread: true, primaryIndex: 10, pageCount: 150
            ),
            "見開きが続く遷移先では、新しい右ページが届くまで古い表示を残すべき"
        )
    }

    func testClearsSecondaryPageWhenSinglePageMode() {
        XCTAssertTrue(
            PerformanceViewModel.shouldClearSecondaryPage(
                isTwoPageSpread: false, primaryIndex: 10, pageCount: 150
            ),
            "単ページ表示では右ページは常に存在しない"
        )
    }

    func testClearsSecondaryPageWhenLandingOnLastPage() {
        XCTAssertTrue(
            PerformanceViewModel.shouldClearSecondaryPage(
                isTwoPageSpread: true, primaryIndex: 149, pageCount: 150
            ),
            "遷移先が曲の最終ページなら、右ページは存在しないので消してよい"
        )
    }
}
