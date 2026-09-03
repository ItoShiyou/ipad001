import Foundation

/// 描画済みページの保持庫。
///
/// **保持するのは「前・現在・次」の3枚だけ**（NFR-03）。
/// 500ページのPDFでも常用メモリが一定に収まるのは、ここで上限を切っているため。
/// 余分に持てば先読みは楽になるが、大判楽譜でメモリ警告を受けて落ちる方が本番では致命的である。
actor PageCache {
    private var entries: [PageAddress: RenderedPage] = [:]
    private let capacity: Int

    init(capacity: Int = 3) {
        self.capacity = capacity
    }

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
