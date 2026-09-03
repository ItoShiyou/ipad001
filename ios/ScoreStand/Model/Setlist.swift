import Foundation
import SwiftData

/// 演奏する曲の並び。
@Model
final class Setlist {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SetlistItem.setlist)
    var items: [SetlistItem] = []

    init(name: String) {
        self.name = name
    }

    /// 並び順に整列した項目。SwiftData の配列順は保証されないため、常にこちらを使う。
    var orderedItems: [SetlistItem] {
        items.sorted { $0.order < $1.order }
    }

    func appending(_ score: Score, note: String = "") -> SetlistItem {
        let item = SetlistItem(order: items.count, note: note)
        item.score = score
        item.setlist = self
        items.append(item)
        updatedAt = Date()
        return item
    }

    /// 並べ替えのあと、order を 0..<n に振り直す。
    func renumber() {
        for (index, item) in orderedItems.enumerated() {
            item.order = index
        }
        updatedAt = Date()
    }
}
