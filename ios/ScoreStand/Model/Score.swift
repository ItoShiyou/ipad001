import Foundation
import SwiftData

/// 1つの曲。ページの実体は `PageSource` が持ち、この型はその並びとメタデータを持つ。
///
/// 元のPDFは決して改変しない（設計原則 P3）。トリミングも注釈も、
/// ここにぶら下がる別レコードとして保存する。
@Model
final class Score {
    #Index<Score>([\.title], [\.createdAt])

    var id: UUID = UUID()
    var title: String = ""
    var composer: String = ""
    var ensemble: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// 最後に開いていたページ。次に開いたとき同じ場所から始めるために使う（FR-15）。
    var lastPageIndex: Int = 0

    /// 練習用のテンポと拍子。未設定なら nil。
    var tempoBPM: Int?
    var timeSignature: String?

    @Relationship(deleteRule: .cascade, inverse: \PageSource.score)
    var sources: [PageSource] = []

    @Relationship(deleteRule: .cascade, inverse: \PageSetting.score)
    var pageSettings: [PageSetting] = []

    @Relationship(deleteRule: .cascade, inverse: \AnnotationLayer.score)
    var annotations: [AnnotationLayer] = []

    init(title: String, composer: String = "", ensemble: String = "", tags: [String] = []) {
        self.title = title
        self.composer = composer
        self.ensemble = ensemble
        self.tags = tags
    }

    /// 全ソースを順に並べた通しページ数。
    var pageCount: Int {
        sources.reduce(0) { $0 + $1.pageCount }
    }

    /// 通しページ番号を、どのソースの何ページ目かに解決する。
    ///
    /// 複数のPDFを1曲として連結できる（FR-06）ため、表示側は常にこの通し番号で扱い、
    /// ソース境界を意識しない。
    func resolve(pageIndex: Int) -> (source: PageSource, pageInSource: Int)? {
        guard pageIndex >= 0 else { return nil }
        var remaining = pageIndex
        for source in sources.sorted(by: { $0.order < $1.order }) {
            if remaining < source.pageCount {
                return (source, remaining)
            }
            remaining -= source.pageCount
        }
        return nil
    }

    func setting(forPage pageIndex: Int) -> PageSetting? {
        pageSettings.first { $0.pageIndex == pageIndex }
    }

    func annotation(forPage pageIndex: Int) -> AnnotationLayer? {
        annotations.first { $0.pageIndex == pageIndex }
    }

    func touch() {
        updatedAt = Date()
    }
}
