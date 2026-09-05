import SwiftUI

/// 譜面をスクロールでめくるコンテナ（新規要望、ベータ）。
///
/// FR-10 の見開き切替は手動トグルを廃止し、画面の向き（`PerformanceViewModel`
/// が `updateLayout` で決める）から自動的に決まる：縦置きは単ページ・縦スクロール、
/// 横置きは見開き2ページ・横スクロール。
///
/// 大判の楽譜では全ページを並べて置くとメモリを使い切る（NFR-03）ため、
/// 常に「前・現在・次」の3枠だけを並べ、スクロールが1枠ぶん確定して
/// 止まったら中央の枠へ無音で（アニメーションなしで）付け替える。
/// 画面に映る内容は変わらないので、ユーザーには途切れなく流れたように見える
/// （インフィニットカルーセルの定石と同じ考え方）。
struct ScorePagingView: View {
    let model: PerformanceViewModel
    let isEditing: Bool
    let onTap: (CGFloat, CGFloat) -> Void
    @Binding var isDragging: Bool

    @State private var windowIndices: [Int] = []
    @State private var scrollPositionID: Int?
    @State private var pendingIndex: Int?

    private var isTwoPageSpread: Bool { model.isTwoPageSpread }
    private var step: Int { isTwoPageSpread ? 2 : 1 }
    private var axis: Axis.Set { isTwoPageSpread ? .horizontal : .vertical }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(axis, showsIndicators: false) {
                Group {
                    if isTwoPageSpread {
                        HStack(spacing: 0) {
                            slots(proxy: proxy)
                        }
                    } else {
                        VStack(spacing: 0) {
                            slots(proxy: proxy)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPositionID)
            .scrollDisabled(false)
            .contentShape(Rectangle())
            .onTapGesture { location in
                onTap(location.x, proxy.size.width)
            }
            // ページ送りに使っている軸と別に、指の上げ下げそのものを検知する。
            // ドラッグ中に窓を付け替えると UIScrollView 自身のパン認識と競合して
            // カクつく恐れがあるため、指を離してから付け替える（下の onChange 参照）。
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in isDragging = true }
                    .onEnded { _ in isDragging = false }
            )
        }
        .onAppear { resetWindow(around: model.currentPageIndex, animated: false) }
        .onChange(of: model.currentPageIndex) { _, newValue in
            // ペダル・スクラバー・ジャンプなど、このビュー自身のスクロール以外で
            // ページが変わったとき（＝すでに窓の中央でない）は窓を追従させる。
            guard newValue != windowIndices[safe: 1] else { return }
            resetWindow(around: newValue, animated: false)
        }
        .onChange(of: isTwoPageSpread) { _, _ in
            resetWindow(around: model.currentPageIndex, animated: false)
        }
        .onChange(of: scrollPositionID) { _, newValue in
            guard let newValue else { return }
            pendingIndex = newValue
            if !isDragging { commitPendingIndex() }
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { commitPendingIndex() }
        }
    }

    @ViewBuilder
    private func slots(proxy: GeometryProxy) -> some View {
        // 各枠を常にちょうど画面1枚ぶんの大きさにする。以前（スクロール化前）の
        // 単一の `PageImageView` も画面いっぱいに敷いていたのと同じ大きさなので、
        // `PageImageView` 内部の見開き分割（HStack で半分ずつ）もそのまま流用できる。
        ForEach(windowIndices, id: \.self) { index in
            slot(for: index)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .id(index)
        }
    }

    @ViewBuilder
    private func slot(for index: Int) -> some View {
        if index == model.currentPageIndex {
            // 現在ページだけは「白紙より古い表示を優先する」方針
            // （`PerformanceViewModel` 冒頭コメント）に沿った専用の状態を使う。
            PageImageView(
                page: model.displayedPage,
                secondaryPage: isTwoPageSpread ? model.displayedSecondaryPage : nil,
                isInverted: model.isInverted && !isEditing
            )
        } else {
            PageImageView(
                page: model.windowPages[index],
                secondaryPage: isTwoPageSpread ? model.windowPages[index + 1] : nil,
                isInverted: model.isInverted && !isEditing
            )
        }
    }

    private func commitPendingIndex() {
        guard let target = pendingIndex else { return }
        pendingIndex = nil
        guard target != model.currentPageIndex else { return }
        model.stopAutoScroll()
        model.goToPage(target)
        resetWindow(around: target, animated: false)
    }

    /// 窓を指定ページ中心の3枠へ組み直し、`scrollPositionID` を同じページに
    /// 付け直す。`animated: false` を transaction で明示的に指定しないと、
    /// 直前の指の動きから続くスクロールの慣性アニメーションと衝突して
    /// 一瞬戻る・跳ねるような見え方になることがある。
    private func resetWindow(around index: Int, animated: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            windowIndices = [index - step, index, index + step]
            scrollPositionID = index
        }
    }
}
