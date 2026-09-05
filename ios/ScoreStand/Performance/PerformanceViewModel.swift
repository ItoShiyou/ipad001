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
    /// 手動切替は廃止し、`updateLayout` が画面の向きから自動的に決める
    /// （横長＝見開き、縦長＝単ページ）。反映は `updateLayout` の中で行うため、
    /// 外から直接代入しない。
    private(set) var isTwoPageSpread = false
    /// 暗所用の反転表示（FR-13）。
    var isInverted = false
    /// 注釈レイヤの表示（FR-42）。
    var showsAnnotations = true

    /// 現在ページの前後、スクロール表示の隣枠に出すための先読み済みページ。
    ///
    /// `displayedPage` / `displayedSecondaryPage` は「白紙よりは古い表示を優先する」
    /// 方針（NFR-01対応）のための現在ページ専用の状態で、ここでは触らない。
    /// こちらは隣の枠（まだ表示に使われていない）のためだけの単純なキャッシュの写しで、
    /// 空でもチラつきの問題にはならない（先読みが間に合っていれば通常は埋まっている）。
    private(set) var windowPages: [Int: RenderedPage] = [:]

    /// 速度を指定した自動スクロール（新規要望、ベータ）。
    ///
    /// 演奏タイミングを記録して自動再生する本格的な仕組み（要件定義 FR-90〜99）とは別の、
    /// 単純な一定速度のオートスクロール。人間の操作が来たら即座に止める（設計原則 P6）。
    private(set) var isAutoScrolling = false
    /// 1ページ（見開きでは1見開き）を送るのにかける秒数。小さいほど速い。
    var autoScrollSecondsPerPage: Double = 8 {
        didSet {
            let clamped = autoScrollSecondsPerPage.clamped(to: Self.autoScrollRange)
            if clamped != autoScrollSecondsPerPage { autoScrollSecondsPerPage = clamped }
        }
    }
    static let autoScrollRange: ClosedRange<Double> = 3...30
    private var autoScrollTask: Task<Void, Never>?

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

    /// リピート / D.S. / Coda などのジャンプ先（FR-26、ベータ）。
    var jumpPoints: [JumpPoint] {
        (score?.jumpPoints ?? []).sorted { $0.order < $1.order }
    }

    /// セットリストの任意の曲へ飛ぶ。
    func jumpToSetlistItem(at index: Int) {
        guard case .setlist(let setlist, let current) = context else { return }
        guard index != current, setlist.orderedItems.indices.contains(index) else { return }
        stopAutoScroll()
        moveScore(by: index - current)
    }

    /// セットリスト上の位置。演奏ビューの見出しに出す。
    var setlistPosition: (index: Int, total: Int)? {
        if case .setlist(let setlist, let index) = context {
            return (index, setlist.orderedItems.count)
        }
        return nil
    }

    // MARK: - 表示寸法

    /// 表示領域が決まった / 変わったときに呼ぶ。
    ///
    /// 見開き（FR-10）は手動切替をやめ、ここで画面の向きから自動的に決める
    /// （横長＝見開き、縦長＝単ページ、という要望による）。回転の途中で
    /// 中間的なアスペクト比の値が何度も届いても、確定した向きが変わった
    /// ときだけ切り替える。
    func updateLayout(size: CGSize, scale: CGFloat) {
        let wantsSpread = size.width > size.height
        let key = RenderKey(size: size, scale: scale)
        let spreadChanged = wantsSpread != isTwoPageSpread
        guard spreadChanged || key != renderKey else { return }

        if spreadChanged {
            isTwoPageSpread = wantsSpread
            // 窓の広さが変わるため、右ページの古い内容を持ち越さない。
            displayedSecondaryPage = nil
        }
        renderKey = key
        showCachedPageIfAvailable()
        refreshWindow()
    }

    // MARK: - 入力

    func handle(_ event: PageTurnEvent) {
        // P6: 人間の操作が来たら自動スクロールは即座に止める。
        stopAutoScroll()
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
        // 見開きでは「今の見開き2枚」に加えて前後1見開きぶんまで持つ。
        // スクロール型のページ送り（新規要望）にしたことで、戻る方向のドラッグも
        // 前へ進む操作と同じくらい日常的に起こるようになったため、以前の
        // 「前方向に厚く持つ」非対称な窓（前1枚・次2枚）はやめ、前後を揃えた。
        var indices = [currentPageIndex - 1, currentPageIndex, currentPageIndex + 1]
        if isTwoPageSpread {
            indices.append(contentsOf: [currentPageIndex - 2, currentPageIndex + 2, currentPageIndex + 3])
        }
        let descriptors = indices.compactMap {
            PageDescriptorFactory.make(score: score, pageIndex: $0)
        }
        coordinator.update(
            descriptors: descriptors,
            currentPageIndex: currentPageIndex,
            key: renderKey
        )

        // 窓の外の隣枠キャッシュは捨てる。
        let windowIndexSet = Set(indices)
        windowPages = windowPages.filter { windowIndexSet.contains($0.key) }
        // `PrerenderCoordinator` は新規に描いたページしか届けてくれないため、
        // 既にキャッシュ済み（戻ってきた場合など）のページはここで直接拾っておく。
        Task {
            for index in indices {
                guard let page = await coordinator.cachedPage(
                    scoreID: score.id, pageIndex: index, key: renderKey
                ) else { continue }
                windowPages[index] = page
            }
        }
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
                windowPages[index] = page
                isWaitingForRender = false
                Metrics.endPageTurn()
                Metrics.endColdStartIfNeeded()
            }
            if spread, index + 1 < score.pageCount,
               let right = await coordinator.cachedPage(
                scoreID: score.id, pageIndex: index + 1, key: renderKey
               ), index == currentPageIndex {
                displayedSecondaryPage = right
                windowPages[index + 1] = right
            }
        }
    }

    private func pageBecameReady(_ page: RenderedPage) {
        guard page.scoreID == score?.id, page.renderKey == renderKey else { return }
        windowPages[page.pageIndex] = page

        if page.pageIndex == currentPageIndex {
            displayedPage = page
            isWaitingForRender = false
            Metrics.endPageTurn()
            Metrics.endColdStartIfNeeded()
        } else if isTwoPageSpread, page.pageIndex == currentPageIndex + 1 {
            displayedSecondaryPage = page
        }
    }

    // MARK: - 自動スクロール（ベータ）

    /// 一定速度でページを自動送りする。曲単位のオプトインで、既定は無効（P6 と同じ考え方）。
    func toggleAutoScroll() {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            startAutoScroll()
        }
    }

    func stopAutoScroll() {
        guard isAutoScrolling else { return }
        isAutoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func startAutoScroll() {
        isAutoScrolling = true
        autoScrollTask?.cancel()
        autoScrollTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isAutoScrolling {
                let seconds = self.autoScrollSecondsPerPage
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, self.isAutoScrolling else { return }
                // 曲の最後まで来たら止める（FR-99 と同じく、自動が勝手に
                // セットリストの先へ進み続けて演奏者を置き去りにしないため）。
                let next = self.currentPageIndex + (self.isTwoPageSpread ? 2 : 1)
                guard let score = self.score, next < score.pageCount else {
                    self.stopAutoScroll()
                    return
                }
                self.goToPage(next)
            }
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
        stopAutoScroll()
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
