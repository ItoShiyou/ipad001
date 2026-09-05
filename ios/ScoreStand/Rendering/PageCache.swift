import Foundation

/// 描画済みページの保持庫。
///
/// このクラス自体は上限を持たない。実際に何ページ保持されるかは、
/// 呼び出し側が `retain(_:)` に渡す集合（＝「今必要な窓」）で決まる。
/// 単ページ表示では「前・現在・次」の3枚（NFR-03）、見開き表示では
/// 現在の見開き2枚＋前1枚＋次の見開き2枚の最大5枚になる
/// （`PerformanceViewModel.refreshWindow` 参照）。
/// 500ページのPDFでも常用メモリが一定に収まるのは、この「窓の外は即座に捨てる」
/// 方式のため。窓自体を無制限に広げない限り、ページ数によらず上限は一定である。
actor PageCache {
    private var entries: [PageAddress: RenderedPage] = [:]

    init() {}

    func page(at address: PageAddress) -> RenderedPage? {
        entries[address]
    }

    func insert(_ page: RenderedPage) {
        let address = PageAddress(
            scoreID: page.scoreID,
            pageIndex: page.pageIndex,
            renderKey: page.renderKey
        )
        entries[address] = page
    }

    /// 現在の窓に含まれないものを捨てる。
    ///
    /// LRU ではなく「窓の外は即座に捨てる」方式にしている。
    /// 譜めくりは前後にしか動かないので、窓が正解であり、
    /// LRU の履歴を持つ方がかえってメモリを読みにくくする。
    func retain(_ addresses: Set<PageAddress>) {
        entries = entries.filter { addresses.contains($0.key) }
    }

    func removeAll() {
        entries.removeAll()
    }

    var count: Int { entries.count }
}
