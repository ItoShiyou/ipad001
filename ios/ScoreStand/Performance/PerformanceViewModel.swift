import CoreGraphics
import Foundation
import SwiftData

/// 演奏ビューの状態。譜めくり入力を受けて、表示するページを決める。
///
/// 表示の差し替えは**キャッシュ済みの画像に対してのみ即座に行う**。
/// 描けていないページに切り替えて白紙を見せるくらいなら、
/// 現在のページを出したまま待つ方が本番では安全である（設計原則 P1）。
@MainActor
@Observable
final class PerformanceViewModel {
    /// セットリストを辿っているのか、単曲を開いているのか。
    enum Context {
        case single(Score)
        case setlist(Setlist, index: Int)

        var score: Score? {
            switch self {
            case .single(let score):
                return score
            case .setlist(let setlist, let index):
                return setlist.orderedItems[safe: index]?.score
            }
        }
    }

    private(set) var context: Context
    private(set) var currentPageIndex = 0
    private(set) var displayedPage: RenderedPage?
    /// 見開き表示のときの右側ページ。単ページ表示では常に nil。
    private(set) var displayedSecondaryPage: RenderedPage?
    /// 次のページがまだ描けていないときだけ立つ。UI は控えめな待ち表示に使う。
    private(set) var isWaitingForRender = false

    /// 見開き表示（FR-10）。
    ///
    /// 変更の反映は `spreadModeChanged()` を呼んで行う。`@Observable` は
    /// プロパティを計算プロパティへ変換するため、`didSet` を当てにしない。
    var isTwoPageSpread = false
    /// 暗所用の反転表示（FR-13）。
    var isInverted = false
    /// 注釈レイヤの表示（FR-42）。
    var showsAnnotations = true

    private let coordinator: PrerenderCoordinator
    private let session: PerformanceSession
    private let context_: ModelContext
    private var renderKey: RenderKey?

    init(
        context: Context,
        coordinator: PrerenderCoordinator,
        session: PerformanceSession,
        modelContext: ModelContext
    ) {
        self.context = context
        self.coordinator = coordinator
        self.session = session
        self.context_ = modelContext
        self.currentPageIndex = context.score?.lastPageIndex ?? 0

        coordinator.onPageReady = { [weak self] page in
            self?.pageBecameReady(page)
        }
    }

    var score: Score? { context.score }

    var pageCount: Int { score?.pageCount ?? 0 }

    /// セットリスト上の曲名一覧。演奏中のジャンプUIに使う（FR-32）。
    var setlistTitles: [String] {
        guard case .setlist(let setlist, _) = context else { return [] }
        return setlist.orderedItems.map { $0.score?.title ?? "（削除された曲）" }
    }

    /// セットリストの任意の曲へ飛ぶ。
    func jumpToSetlistItem(at index: Int) {
        guard case .setlist(let setlist, let current) = context else { return }
        guard index != current, setlist.orderedItems.indices.contains(index) else { return }
        moveScore(by: index - current)
    }

    /// セットリスト上の位置。演奏ビューの見出しに出す。
    var setlistPosition: (index: Int, total: Int)? {
        if case .setlist(let setlist, let index) = context {
            return (index, setlist.orderedItems.count)
        }
        return nil
    }

    /// 見開きの切り替え後に呼ぶ。窓の広さが変わるため描き直しが要る。
    func spreadModeChanged() {
        displayedSecondaryPage = nil
        showCachedPageIfAvailable()
        refreshWindow()
    }

    // MARK: - 表示寸法

    /// 表示領域が決まった / 変わったときに呼ぶ。
    func updateLayout(size: CGSize, scale: CGFloat) {
        let key = RenderKey(size: size, scale: scale)
        guard key != renderKey else { return }
        renderKey = key
        refreshWindow()
    }

    // MARK: - 入力

    func handle(_ event: PageTurnEvent) {
        switch event.command {
        case .next:
            goToPage(currentPageIndex + (isTwoPageSpread ? 2 : 1))
        case .previous:
            goToPage(currentPageIndex - (isTwoPageSpread ? 2 : 1))
        case .jump(let pageIndex):
            goToPage(pageIndex)
        case .nextScore:
            moveScore(by: 1)
        case .previousScore:
            moveScore(by: -1)
        }
    }

    /// ページ移動。
    ///
    /// 曲の端を越えたらセットリストの隣の曲へ繋ぐ（FR-31）。
    /// 演奏中に曲の終わりで操作が無反応になると、奏者は「壊れた」と感じるため。
    func goToPage(_ index: Int) {
        guard let score else { return }

        if index >= score.pageCount {
            if case .setlist = context {
                moveScore(by: 1)
            }
            return
        }
        if index < 0 {
            if case .setlist = context {
                moveScore(by: -1, landingOnLastPage: true)
            }
            return
        }

        currentPageIndex = index
        score.lastPageIndex = index
        // NFR-01: ここから、表示中のページが実際に差し替わるまでを計測する。
        Metrics.beginPageTurn()
        // 白紙より古い表示を優先する方針（ファイル冒頭コメント）は右ページにも適用する。
        // 次の見開きに右ページが存在しないときだけ、ここで確実に消しておく。
        if PerformanceViewModel.shouldClearSecondaryPage(
            isTwoPageSpread: isTwoPageSpread, primaryIndex: currentPageIndex, pageCount: score.pageCount
        ) {
            displayedSecondaryPage = nil
        }
        showCachedPageIfAvailable()
        refreshWindow()
    }

    private func moveScore(by delta: Int, landingOnLastPage: Bool = false) {
        guard case .setlist(let setlist, let index) = context else { return }
        let items = setlist.orderedItems
        let next = index + delta
        guard next >= 0, next < items.count, let nextScore = items[next].score else { return }

        context = .setlist(setlist, index: next)
        currentPageIndex = landingOnLastPage ? max(0, nextScore.pageCount - 1) : 0
        displayedPage = nil
        if PerformanceViewModel.shouldClearSecondaryPage(
            isTwoPageSpread: isTwoPageSpread, primaryIndex: currentPageIndex, pageCount: nextScore.pageCount
        ) {
            displayedSecondaryPage = nil
        }
        showCachedPageIfAvailable()
        refreshWindow()
    }

    // MARK: - 描画

    private func refreshWindow() {
        guard let score, let renderKey else { return }
        // 見開きでは「今の見開き2枚」と「次の見開きの左」までを持つ。
        // 前方向に厚く持つのは、譜めくりが前へ進む操作の方が圧倒的に多いため。
        var indices = [currentPageIndex - 1, currentPageIndex, currentPageIndex + 1]
        if isTwoPageSpread {
            indices.append(contentsOf: [currentPageIndex + 2, currentPageIndex + 3])
        }
        let descriptors = indices.compactMap {
            PageDescriptorFactory.make(score: score, pageIndex: $0)
        }
        coordinator.update(
            descriptors: descriptors,
            currentPageIndex: currentPageIndex,
            key: renderKey
        )
    }

    private func showCachedPageIfAvailable() {
        guard let score, let renderKey else { return }
        let index = currentPageIndex
        let spread = isTwoPageSpread
        isWaitingForRender = true
        Task {
            if let page = await coordinator.cachedPage(
                scoreID: score.id, pageIndex: index, key: renderKey
            ), index == currentPageIndex {
                displayedPage = page
                isWaitingForRender = false
                Metrics.endPageTurn()
                Metrics.endColdStartIfNeeded()
            }
            if spread, index + 1 < score.pageCount,
               let right = await coordinator.cachedPage(
                scoreID: score.id, pageIndex: index + 1, key: renderKey
               ), index == currentPageIndex {
                displayedSecondaryPage = right
            }
        }
    }

    private func pageBecameReady(_ page: RenderedPage) {
        guard page.scoreID == score?.id, page.renderKey == renderKey else { return }

        if page.pageIndex == currentPageIndex {
            displayedPage = page
            isWaitingForRender = false
            Metrics.endPageTurn()
            Metrics.endColdStartIfNeeded()
        } else if isTwoPageSpread, page.pageIndex == currentPageIndex + 1 {
            displayedSecondaryPage = page
        }
    }

    /// 見開きの右ページを、遷移直後に消してよいか。
    ///
    /// 単ページ表示、または遷移先に右ページが存在しない（曲の最終ページ）ときだけ
    /// 消す。それ以外は新しい右ページが用意できるまで古い内容を出したままにして、
    /// 白紙のチラつきを避ける（ファイル冒頭コメントの方針）。
    nonisolated static func shouldClearSecondaryPage(isTwoPageSpread: Bool, primaryIndex: Int, pageCount: Int) -> Bool {
        !isTwoPageSpread || primaryIndex + 1 >= pageCount
    }

    // MARK: - 生存期間

    func onAppear() {
        session.begin()
    }

    func onDisappear() {
        session.end()
        // 表示位置の保存は失敗しても致命的でないため、演奏の妨げにならないよう
        // 画面を離れるこの時点まで遅らせている。
        try? context_.save()
        Task { await coordinator.reset() }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
