import Foundation
import SwiftData

/// ページ1枚分の手書き注釈。
///
/// `PKDrawing` のシリアライズ結果をそのまま持ち、**元のPDFには一切書き込まない**（FR-41 / P3）。
/// 表示・非表示の切り替え（FR-42）が成立するのも、分離して持っているため。
@Model
final class AnnotationLayer {
    var id: UUID = UUID()
    var pageIndex: Int = 0

    /// `PKDrawing.dataRepresentation()` の結果。
    var drawingData: Data = Data()
    var updatedAt: Date = Date()

    var score: Score?

    var isEmpty: Bool { drawingData.isEmpty }

    init(pageIndex: Int, drawingData: Data = Data()) {
        self.pageIndex = pageIndex
        self.drawingData = drawingData
    }
}
