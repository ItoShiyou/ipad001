import Foundation

/// ライブラリ書き出し（FR-60〜62）専用のコンテナ形式。
///
/// iOS には zip を展開する公開APIが無い（`NSFileCoordinator` の `.forUploading` で
/// zip を「作る」ことはできても、任意の zip を「読む」公開APIが存在しない）。
/// 外部ライブラリを入れない方針のもとでは、自前でコンテナ形式を定義して
/// 実装するしかない。そのぶん形式を単純にして仕様として公開すれば、
/// 「将来ユーザーが他アプリへ移れる」(FR-62) も満たせる。
///
/// レイアウト（すべてリトルエンディアン）:
/// ```
/// [0..<4)   マジックバイト "SSTD" (ASCII)
/// [4..<8)   フォーマットバージョン (UInt32)
/// [8..<16)  マニフェストJSONのバイト長 (UInt64)
/// [16..<16+N) マニフェストJSON本体 (UTF-8)
/// [16+N..)  ファイル実体を連結したもの。各ファイルの位置はマニフェストの
///           ArchiveFile.offset / size が示す（このオフセットは書庫先頭からの絶対位置）。
/// ```
/// `.scorestand` 拡張子で書き出す。
enum ArchiveFormat {
    static let magic: [UInt8] = Array("SSTD".utf8)
    static let currentVersion: UInt32 = 1
    static let fileExtension = "scorestand"

    /// マジック + バージョン + 長さフィールドの固定ヘッダサイズ。
    static let headerPrefixSize = 16
}

// MARK: - マニフェスト

struct ArchiveManifest: Codable {
    var version: UInt32
    var exportedAt: Date
    var scores: [ArchiveScore]
    var setlists: [ArchiveSetlist]
    var files: [ArchiveFile]
}

/// 書庫内に連結されたファイル実体1つ分の位置情報。
struct ArchiveFile: Codable {
    var id: UUID
    var originalName: String
    var offset: UInt64
    var size: UInt64
}

struct ArchiveScore: Codable {
    var title: String
    var composer: String
    var ensemble: String
    var tags: [String]
    var createdAt: Date
    var lastPageIndex: Int
    var tempoBPM: Int?
    var timeSignature: String?
    var sources: [ArchiveSource]
    var pageSettings: [ArchivePageSetting]
    var annotations: [ArchiveAnnotation]
}

struct ArchiveSource: Codable {
    var fileID: UUID
    var kind: String
    var pageCount: Int
    var order: Int
    var originalName: String
}

struct ArchivePageSetting: Codable {
    var pageIndex: Int
    var cropX: Double
    var cropY: Double
    var cropWidth: Double
    var cropHeight: Double
    var rotation: Int
}

struct ArchiveAnnotation: Codable {
    var pageIndex: Int
    /// `PKDrawing.dataRepresentation()` の結果。JSON化すると Base64 になる。
    var drawingData: Data
}

struct ArchiveSetlist: Codable {
    var name: String
    var createdAt: Date
    var items: [ArchiveSetlistItem]
}

struct ArchiveSetlistItem: Codable {
    var order: Int
    var note: String
    /// 書き出し元の `scores` 配列への添字。曲が書庫内に含まれていない場合は nil。
    var scoreIndex: Int?
}

// MARK: - 低レベル読み書き

/// コンテナの読み書きを行う。**ファイル全体をメモリに載せない。**
///
/// 楽譜PDFは合計で数GBになりうる（多数の曲・高解像度スキャン）ため、
/// 書き出しは `FileHandle` で末尾に追記し、読み込みもマニフェストと
/// 必要なファイル実体の範囲だけを都度読む。
enum ArchiveWriter {
    /// 書庫ファイルを新規作成し、ヘッダとマニフェストを書き込む。
    /// `manifest` は呼び出し側が offset を計算済みの最終版であること。
    /// ファイル実体はこのあと `appendFile` で、その offset の並び順どおりに追記する。
    static func createHeader(manifest: ArchiveManifest, at url: URL) throws -> FileHandle {
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path(percentEncoded: false)) else {
            throw ArchiveError.cannotOpen
        }
        try writeManifest(manifest, to: handle)
        return handle
    }

    /// ヘッダ（マジック + バージョン + 長さ + マニフェストJSON）を、現在の書き込み位置から書く。
    /// 呼び出し前に `handle` の書き込み位置が 0 であることが前提。
    static func writeManifest(_ manifest: ArchiveManifest, to handle: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(manifest)

        var header = Data()
        header.append(contentsOf: ArchiveFormat.magic)
        header.append(littleEndian: manifest.version)
        header.append(littleEndian: UInt64(json.count))

        try handle.write(contentsOf: header)
        try handle.write(contentsOf: json)
    }

    /// ファイル実体1つを、書庫の現在末尾に追記する。戻り値はそのファイルの (offset, size)。
    ///
    /// `FileHandle` で読み側・書き側とも小さなチャンク単位に区切り、
    /// 巨大PDFでもピークメモリを一定に保つ。
    static func appendFile(at sourceURL: URL, to handle: FileHandle) throws -> (offset: UInt64, size: UInt64) {
        let offset = try handle.offset()
        guard let input = FileHandle(forReadingAtPath: sourceURL.path(percentEncoded: false)) else {
            throw ArchiveError.cannotOpen
        }
        defer { try? input.close() }

        var totalSize: UInt64 = 0
        let chunkSize = 4 * 1024 * 1024 // 4MB ずつ
        while true {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
            totalSize += UInt64(chunk.count)
        }
        return (offset, totalSize)
    }
}

enum ArchiveReader {
    /// ヘッダを読み、マニフェストを取り出す。ファイル実体には触れない。
    static func readManifest(from url: URL) throws -> ArchiveManifest {
        guard let handle = FileHandle(forReadingAtPath: url.path(percentEncoded: false)) else {
            throw ArchiveError.cannotOpen
        }
        defer { try? handle.close() }

        guard let prefix = try handle.read(upToCount: ArchiveFormat.headerPrefixSize),
              prefix.count == ArchiveFormat.headerPrefixSize else {
            throw ArchiveError.corrupted
        }
        guard Array(prefix.prefix(4)) == ArchiveFormat.magic else {
            throw ArchiveError.notScoreStandFile
        }
        let version = prefix.subdata(in: 4..<8).littleEndianUInt32()
        guard version <= ArchiveFormat.currentVersion else {
            throw ArchiveError.unsupportedVersion
        }
        let manifestLength = prefix.subdata(in: 8..<16).littleEndianUInt64()

        guard manifestLength > 0, manifestLength < 512 * 1024 * 1024 else {
            // マニフェストJSON自体は曲数・注釈数に応じて増えるだけで、
            // ファイル実体（PDF本体）は含まないため数百MBを超えることは想定していない。
            // 極端な値は破損とみなす。
            throw ArchiveError.corrupted
        }
        guard let json = try handle.read(upToCount: Int(manifestLength)),
              json.count == Int(manifestLength) else {
            throw ArchiveError.corrupted
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ArchiveManifest.self, from: json)
        } catch {
            throw ArchiveError.corrupted
        }
    }

    /// 指定されたファイル実体だけを、書庫から必要な範囲だけ読み出す。
    static func readFileData(_ file: ArchiveFile, from url: URL) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: url.path(percentEncoded: false)) else {
            throw ArchiveError.cannotOpen
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: file.offset)
        guard let data = try handle.read(upToCount: Int(file.size)), data.count == Int(file.size) else {
            throw ArchiveError.corrupted
        }
        return data
    }

    /// 指定されたファイル実体を、書庫から少しずつ読んで直接目的地に書き出す（大容量PDF向け）。
    static func extractFile(_ file: ArchiveFile, from archiveURL: URL, to destinationURL: URL) throws {
        guard let input = FileHandle(forReadingAtPath: archiveURL.path(percentEncoded: false)) else {
            throw ArchiveError.cannotOpen
        }
        defer { try? input.close() }

        FileManager.default.createFile(atPath: destinationURL.path(percentEncoded: false), contents: nil)
        guard let output = FileHandle(forWritingAtPath: destinationURL.path(percentEncoded: false)) else {
            throw ArchiveError.cannotOpen
        }
        defer { try? output.close() }

        try input.seek(toOffset: file.offset)
        var remaining = file.size
        let chunkSize: UInt64 = 4 * 1024 * 1024
        while remaining > 0 {
            let toRead = Int(min(chunkSize, remaining))
            guard let chunk = try input.read(upToCount: toRead), !chunk.isEmpty else {
                throw ArchiveError.corrupted
            }
            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }
}

// MARK: - バイト変換ヘルパ

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: UInt64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func littleEndianUInt32() -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    func littleEndianUInt64() -> UInt64 {
        withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
    }
}

// MARK: - エラー

enum ArchiveError: LocalizedError {
    case cannotOpen
    case notScoreStandFile
    case unsupportedVersion
    case corrupted
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "ファイルを開けませんでした。"
        case .notScoreStandFile:
            return "これは ScoreStand の書き出しファイルではありません。"
        case .unsupportedVersion:
            return "このファイルは新しいバージョンのアプリで作られたため、読み込めません。"
        case .corrupted:
            return "ファイルが壊れているため読み込めませんでした。"
        case .missingFile(let name):
            return "「\(name)」の実体が書庫内に見つかりませんでした。"
        }
    }
}
