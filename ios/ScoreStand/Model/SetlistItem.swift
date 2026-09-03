import Foundation
import SwiftData

/// セットリスト上の1曲。
///
/// 曲そのものへの参照と、その公演でだけ必要なメモ（キー、テンポ、MC、注意点）を持つ。
/// メモをここに置くのは、同じ曲でも公演ごとに違うことを書けるようにするため。
@Model
final class SetlistItem {
    var id: UUID = UUID()
    var order: Int = 0
    var note: String = ""

    /// 曲を消してもセットリスト側は壊れないよう、参照は nullify で持つ。
    @Relationship(deleteRule: .nullify)
    var score: Score?

    var setlist: Setlist?

    init(order: Int, note: String = "") {
        self.order = order
        self.note = note
    }
}
