import XCTest
import SwiftData
@testable import ScoreStand

/// 複数PDFを1曲として連結したとき、通しページ番号が正しく解決されるか。
/// ここがずれると、演奏中に別の曲のページが出るという最悪の事故になる。
@MainActor
final class ScoreTests: XCTestCase {
    private func makeScore() -> Score {
        let score = Score(title: "テスト曲")
        let first = PageSource(relativePath: "a.pdf", kind: .pdf, pageCount: 3, order: 0, originalName: "a.pdf")
        let second = PageSource(relativePath: "b.pdf", kind: .pdf, pageCount: 2, order: 1, originalName: "b.pdf")
        first.score = score
        second.score = score
        score.sources = [first, second]
        return score
    }

    func testPageCountSumsAllSources() {
        XCTAssertEqual(makeScore().pageCount, 5)
    }

    func testResolveWithinFirstSource() throws {
        let resolved = try XCTUnwrap(makeScore().resolve(pageIndex: 2))
        XCTAssertEqual(resolved.source.relativePath, "a.pdf")
        XCTAssertEqual(resolved.pageInSource, 2)
    }

    func testResolveCrossesIntoSecondSource() throws {
        let resolved = try XCTUnwrap(makeScore().resolve(pageIndex: 3))
        XCTAssertEqual(resolved.source.relativePath, "b.pdf")
        XCTAssertEqual(resolved.pageInSource, 0)
    }

    func testResolveOutOfRangeReturnsNil() {
        XCTAssertNil(makeScore().resolve(pageIndex: 5))
        XCTAssertNil(makeScore().resolve(pageIndex: -1))
    }

    /// order の値どおりに並ぶこと。SwiftData の配列順は保証されないため、
    /// 配列に入れた順ではなく order で解決していることを確かめる。
    func testResolveUsesOrderNotArrayOrder() throws {
        let score = Score(title: "順序")
        let later = PageSource(relativePath: "later.pdf", kind: .pdf, pageCount: 1, order: 1, originalName: "later.pdf")
        let earlier = PageSource(relativePath: "earlier.pdf", kind: .pdf, pageCount: 1, order: 0, originalName: "earlier.pdf")
        score.sources = [later, earlier]

        let resolved = try XCTUnwrap(score.resolve(pageIndex: 0))
        XCTAssertEqual(resolved.source.relativePath, "earlier.pdf")
    }
}
