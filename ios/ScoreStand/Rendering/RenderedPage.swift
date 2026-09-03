import CoreGraphics
import Foundation

/// 描画済みの1ページ。
///
/// `CGImage` は生成後に不変なので、スレッドをまたいで渡しても安全である。
/// Core Graphics の型は `Sendable` に適合していないため、その事実をここで一度だけ明示する。
struct RenderedPage: @unchecked Sendable {
    let scoreID: UUID
    let pageIndex: Int
    /// どの表示寸法向けに描いたか。画面サイズが変わったら描き直す判定に使う。
    let renderKey: RenderKey
    let image: CGImage
}

/// 描画結果の同一性を決める鍵。
///
/// 寸法を丸めているのは、1ポイントの揺れで再描画が走るのを防ぐため。
/// 揺れるたびに描き直すと、回転やマルチタスクのリサイズ中に譜めくりが詰まる。
struct RenderKey: Hashable, Sendable {
    let width: Int
    let height: Int
    let scale: Int

    init(size: CGSize, scale: CGFloat) {
        self.width = Int(size.width.rounded())
        self.height = Int(size.height.rounded())
        self.scale = Int(scale.rounded())
    }

    var pixelSize: CGSize {
        CGSize(width: CGFloat(width * scale), height: CGFloat(height * scale))
    }
}

/// キャッシュ上の位置。
struct PageAddress: Hashable, Sendable {
    let scoreID: UUID
    let pageIndex: Int
    let renderKey: RenderKey
}
