import Foundation
import SwiftData

/// アプリ全体で共有する依存の組み立て。
///
/// 各画面が自分で `ScoreStore` や `PageRenderer` を作ると、
/// 開いたPDFやキャッシュが二重に持たれてメモリ上限（NFR-03）が崩れる。
/// 生成箇所をここ1つに絞ることで、それを構造的に防いでいる。
@MainActor
@Observable
final class AppEnvironment {
    let store: ScoreStore
    let session: PerformanceSession
    let purchase: PurchaseManager
    let renderer: PageRenderer
    let cache: PageCache

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        let store = ScoreStore.makeDefault()
        self.store = store
        self.modelContext = modelContext
        self.session = PerformanceSession()
        self.purchase = PurchaseManager()
        self.cache = PageCache()
        self.renderer = PageRenderer(store: store)
    }

    func makeImporter() -> DocumentImporter {
        DocumentImporter(store: store, context: modelContext)
    }

    func makeAnnotationStore() -> AnnotationStore {
        AnnotationStore(context: modelContext)
    }

    func makeArchive() -> LibraryArchive {
        LibraryArchive(store: store, modelContext: modelContext)
    }

    /// 演奏ビュー1回分の部品を組む。
    ///
    /// 演奏のたびに新しい `PrerenderCoordinator` を作るのは、
    /// 前の曲の描画タスクを確実に断ち切るため。使い回すと、
    /// 曲を変えた直後に前の曲のページが届いて表示が飛ぶ。
    func makePerformance(
        context: PerformanceViewModel.Context
    ) -> (model: PerformanceViewModel, hub: PageTurnInputHub, tap: TapInputSource, keyboard: KeyboardInputSource) {
        let coordinator = PrerenderCoordinator(renderer: renderer, cache: cache)
        let model = PerformanceViewModel(
            context: context,
            coordinator: coordinator,
            session: session,
            modelContext: modelContext
        )

        let hub = PageTurnInputHub()
        let tap = TapInputSource()
        let keyboard = KeyboardInputSource()
        hub.register(tap)
        hub.register(keyboard)

        return (model, hub, tap, keyboard)
    }

    /// どの曲からも参照されなくなった実体を掃除する。
    ///
    /// 演奏中は走らせない（NFR-05）。`PerformanceSession.perform(deferrable:)` を通す。
    func cleanupOrphanFiles(scores: [Score]) {
        session.perform(deferrable: { [store] in
            let referenced = Set(scores.flatMap { $0.sources.map(\.relativePath) })
            store.removeOrphans(keeping: referenced)
        })
    }
}
