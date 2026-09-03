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
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                pageImage(page)
                if let secondaryPage {
                    pageImage(secondaryPage)
                }
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

private extension View {
    @ViewBuilder
    func colorInvert(isEnabled: Bool) -> some View {
        if isEnabled {
            self.colorInvert()
        } else {
            self
        }
    }
}
