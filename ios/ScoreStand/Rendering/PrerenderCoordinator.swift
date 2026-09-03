import CoreGraphics
import Foundation

/// 現在ページの前後を、常に描画済みにしておく担当。
///
/// **この製品の中核。** 譜めくりの応答（NFR-01: 16ms）は、
/// めくった瞬間に描くのではなく「めくる前に描き終えている」ことでしか達成できない。
@MainActor
final class PrerenderCoordinator {
    private let renderer: PageRenderer
    private let cache: PageCache
    private var tasks: [PageAddress: Task<Void, Never>] = [:]

    /// 描画が終わったページを受け取る先。表示中のページが届いたら差し替える。
    var onPageReady: ((RenderedPage) -> Void)?

    init(renderer: PageRenderer, cache: PageCache) {
        self.renderer = renderer
        self.cache = cache
    }

    /// 表示位置が変わったときに呼ぶ。窓の中を描き、窓の外を捨てる。
    ///
    /// 現在ページを先に投入するのは、めくった直後にまだ描けていない場合に
    /// 一番早く埋まってほしいのが現在ページだからである。
    func update(descriptors: [PageDescriptor], currentPageIndex: Int, key: RenderKey) {
        let addresses = Set(descriptors.map {
            PageAddress(scoreID: $0.scoreID, pageIndex: $0.pageIndex, renderKey: key)
        })

        for (address, task) in tasks where !addresses.contains(address) {
            task.cancel()
            tasks[address] = nil
        }

        Task { await cache.retain(addresses) }

        let ordered = descriptors.sorted { lhs, _ in lhs.pageIndex == currentPageIndex }
        for descriptor in ordered {
            schedule(descriptor, key: key)
        }
    }

    /// 指定ページが描画済みなら返す。無ければ nil（呼び出し側は前ページを出したまま待つ）。
    func cachedPage(scoreID: UUID, pageIndex: Int, key: RenderKey) async -> RenderedPage? {
        await cache.page(at: PageAddress(scoreID: scoreID, pageIndex: pageIndex, renderKey: key))
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func reset() async {
        cancelAll()
        await cache.removeAll()
        await renderer.closeAll()
    }

    private func schedule(_ descriptor: PageDescriptor, key: RenderKey) {
        let address = PageAddress(
            scoreID: descriptor.scoreID,
            pageIndex: descriptor.pageIndex,
            renderKey: key
        )
        guard tasks[address] == nil else { return }

        tasks[address] = Task { [renderer, cache] in
            if await cache.page(at: address) != nil {
                await MainActor.run { self.tasks[address] = nil }
                return
            }
            do {
                let page = try await renderer.render(descriptor, key: key)
                guard !Task.isCancelled else { return }
                await cache.insert(page)
                await MainActor.run {
                    self.tasks[address] = nil
                    self.onPageReady?(page)
                }
            } catch is CancellationError {
                await MainActor.run { self.tasks[address] = nil }
            } catch {
                Log.rendering.error("描画に失敗: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.tasks[address] = nil }
            }
        }
    }
}
