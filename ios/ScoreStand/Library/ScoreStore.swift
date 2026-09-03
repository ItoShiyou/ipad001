import Foundation

/// 楽譜ファイルの実体を、アプリコンテナ内で管理する。
///
/// 取り込んだファイルは**コピーして保管する**（FR-03）。参照だけを持つと、
/// ユーザーが元ファイルを移動・削除したり、iCloud が実体を退避した瞬間に
/// 本番で楽譜が開かなくなる。容量と引き換えに、その事故を構造的に無くしている。
final class ScoreStore: Sendable {
    /// 楽譜の実体を置くディレクトリ。
    let root: URL

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func makeDefault() -> ScoreStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ScoreStore(root: support.appending(path: "Scores", directoryHint: .isDirectory))
    }

    func fileURL(for relativePath: String) -> URL {
        root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// 外部のファイルを取り込む。戻り値は `root` からの相対パス。
    ///
    /// 保存名を UUID にしているのは、同名ファイルの衝突と、
    /// ファイル名に使えない文字（濁点の正規化差など）による事故を避けるため。
    /// 元の名前は `PageSource.originalName` に残す。
    func importFile(at source: URL) throws -> String {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension.lowercased()
        let relativePath = "\(UUID().uuidString).\(ext)"
        let destination = fileURL(for: relativePath)

        try FileManager.default.copyItem(at: source, to: destination)
        try excludeFromBackup(destination)
        return relativePath
    }

    /// すでに手元にあるデータを取り込む（書き出しファイルからの復元など）。
    func write(data: Data, extension ext: String) throws -> String {
        let relativePath = "\(UUID().uuidString).\(ext)"
        let destination = fileURL(for: relativePath)
        try data.write(to: destination, options: .atomic)
        try excludeFromBackup(destination)
        return relativePath
    }

    func delete(relativePath: String) {
        try? FileManager.default.removeItem(at: fileURL(for: relativePath))
    }

    func exists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: relativePath).path(percentEncoded: false))
    }

    func data(for relativePath: String) throws -> Data {
        try Data(contentsOf: fileURL(for: relativePath), options: .mappedIfSafe)
    }

    /// 保管しているファイルの合計サイズ。設定画面で使用量を見せるために持つ。
    func totalBytes() -> Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return entries.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    /// どのモデルからも参照されていない実体を消す。
    ///
    /// 削除時の取りこぼしは必ず起きるので、参照側を正としてまとめて掃除する。
    func removeOrphans(keeping referenced: Set<String>) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
            Log.library.info("孤立ファイルを削除: \(url.lastPathComponent, privacy: .public)")
        }
    }

    /// iCloud バックアップから除外する。
    ///
    /// 楽譜PDFは容量が大きく、ユーザー自身が原本を持っている。
    /// ライブラリの書き出し（FR-60）を正規の退避手段としているため、
    /// 自動バックアップの容量を無駄に食わせない。
    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
