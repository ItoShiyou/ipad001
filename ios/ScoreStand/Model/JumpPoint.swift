import Foundation
import SwiftData

/// リピート / D.S. / Coda など、曲中の任意ページへの飛び先（FR-26、ベータ）。
///
/// **ベータ実装**: S 優先度機能。演奏ビューからの導線は用意したが、
/// 実機での「暗所・片手で押せるか」の検証（P5）はまだ済んでいない。
@Model
final class JumpPoint {
    var id: UUID = UUID()
    /// 表示用のラベル（例: "D.S.", "Coda", "サビ2回目"）。
    var label: String = ""
    /// 飛び先の通しページ番号（0始まり）。
    var pageIndex: Int = 0
    var order: Int = 0

    var score: Score?

    init(label: String, pageIndex: Int, order: Int = 0) {
        self.label = label
        self.pageIndex = pageIndex
        self.order = order
    }
}
