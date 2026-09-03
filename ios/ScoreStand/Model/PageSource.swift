import Foundation
import SwiftData

/// 楽譜の実体ファイル1つ分への参照。
///
/// ファイル名はアプリコンテナ内の相対パスで持つ。絶対パスを保存すると
/// OSアップデートやバックアップ復元でコンテナのパスが変わったときに全滅するため。
@Model
final class PageSource {
    enum Kind: String, Codable {
        case pdf
        case image
    }

    var id: UUID = UUID()

    /// `ScoreStore` が管理するディレクトリからの相対パス。
    var relativePath: String = ""
    var kindRaw: String = Kind.pdf.rawValue
    var pageCount: Int = 0
    var order: Int = 0
    /// 取り込み時の元のファイル名。表示と、書き出し時の復元に使う。
    var originalName: String = ""

    var score: Score?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .pdf }
        set { kindRaw = newValue.rawValue }
    }

    init(relativePath: String, kind: Kind, pageCount: Int, order: Int, originalName: String) {
        self.relativePath = relativePath
        self.kindRaw = kind.rawValue
        self.pageCount = pageCount
        self.order = order
        self.originalName = originalName
    }
}
