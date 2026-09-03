import CoreGraphics
import Foundation
import SwiftData

/// ページ単位の表示調整（トリミングと回転）。
///
/// 既定から変更されたページの分だけ作る。全ページ分を先に作らないのは、
/// 500ページのPDFで無駄なレコードを持たないため（NFR-03）。
@Model
final class PageSetting {
    var id: UUID = UUID()
    var pageIndex: Int = 0

    /// 正規化された切り抜き矩形（0...1）。ページ寸法に依存しないので、
    /// 解像度や用紙サイズが変わっても同じ意味を保つ。
    var cropX: Double = 0
    var cropY: Double = 0
    var cropWidth: Double = 1
    var cropHeight: Double = 1

    /// 90度単位の回転（0, 90, 180, 270）。
    var rotation: Int = 0

    var score: Score?

    var cropRect: CGRect {
        get { CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight) }
        set {
            cropX = newValue.origin.x
            cropY = newValue.origin.y
            cropWidth = newValue.width
            cropHeight = newValue.height
        }
    }

    var isDefault: Bool {
        cropRect == CGRect(x: 0, y: 0, width: 1, height: 1) && rotation == 0
    }

    init(pageIndex: Int, cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), rotation: Int = 0) {
        self.pageIndex = pageIndex
        self.cropX = cropRect.origin.x
        self.cropY = cropRect.origin.y
        self.cropWidth = cropRect.width
        self.cropHeight = cropRect.height
        self.rotation = rotation
    }
}
