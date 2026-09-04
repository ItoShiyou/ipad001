import SwiftUI

/// 描画済みページを表示するだけのビュー。
///
/// `Image(decorative:scale:orientation:)` を使うのは、すでにビットマップ化された
/// `CGImage` を SwiftUI に再解釈させないため。ここで余計な処理が入ると
/// 譜めくりの1フレーム（NFR-01）を落とす。
struct PageImageView: View {
    let page: RenderedPage?
    /// 見開き表示のときの右ページ（FR-10）。単ページ表示では nil。
    let secondaryPage: RenderedPage?
    let isInverted: Bool

    var body: some View {
        // 背景の黒は `PerformanceView` 側が画面全体に敷いているので、
        // ここでは持たない。以前は `Color.black.ignoresSafeArea()` を
        // ここに置いていたが、`ignoresSafeArea()` は親から渡された padding
        // による縮小を無視して常に画面いっぱいに広がろうとするため、
        // 結果としてこの ZStack 自体の実サイズが常に画面全体に戻ってしまい、
        // コントロールバー表示中に譜面を縮めて全体を見せる機能が効かなかった
        // （実機で判明）。
        HStack(spacing: 0) {
            pageImage(page)
            if let secondaryPage {
                pageImage(secondaryPage)
            }
        }
    }

    @ViewBuilder
    private func pageImage(_ page: RenderedPage?) -> some View {
        if let page {
            Image(decorative: page.image, scale: 1, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // 反転は色を入れ替えるだけなので、暗いステージで
                // 客席に光を撒かずに譜面を読むための最も軽い手段になる（FR-13）。
                .colorInvert(isEnabled: isInverted)
                .accessibilityLabel("\(page.pageIndex + 1)ページ")
        }
    }
}

/// 反転表示（FR-13）の条件付き適用。譜面画像・注釈オーバーレイの両方から使う。
extension View {
    @ViewBuilder
    func colorInvert(isEnabled: Bool) -> some View {
        if isEnabled {
            self.colorInvert()
        } else {
            self
        }
    }
}
