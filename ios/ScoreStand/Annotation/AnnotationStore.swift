import SwiftData
import PencilKit
import Foundation

/// Score のページ単位で PKDrawing を読み書きするだけの薄い層。
/// 元のPDF/画像データには一切触れず、AnnotationLayer という別レコードにのみ書き込む（FR-41）。
@MainActor
final class AnnotationStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 指定ページの手書きを読み込む。レイヤーが存在しなければ空の PKDrawing を返す。
    func loadDrawing(for score: Score, pageIndex: Int) -> PKDrawing {
        guard let layer = score.annotation(forPage: pageIndex) else {
            return PKDrawing()
        }
        // 保存データが壊れている場合も空描画にフォールバックし、アプリを落とさない。
        return (try? PKDrawing(data: layer.drawingData)) ?? PKDrawing()
    }

    /// 指定ページの手書きを保存する。
    /// 既存レイヤーがあれば更新し、無ければ新規作成して score.annotations に追加する。
    /// 描画が空になった場合は無駄なレコードを残さないようレイヤー自体を削除する。
    func saveDrawing(_ drawing: PKDrawing, for score: Score, pageIndex: Int) {
        let data = drawing.dataRepresentation()

        if let layer = score.annotation(forPage: pageIndex) {
            if drawing.strokes.isEmpty {
                score.annotations.removeAll { $0.id == layer.id }
                context.delete(layer)
            } else {
                layer.drawingData = data
                layer.updatedAt = Date()
            }
        } else if !drawing.strokes.isEmpty {
            let layer = AnnotationLayer(pageIndex: pageIndex, drawingData: data)
            layer.score = score
            score.annotations.append(layer)
            context.insert(layer)
        }
        // strokes が空でレイヤーも存在しない場合は何もしない（作って即削除を避ける）。

        score.touch()
    }
}
