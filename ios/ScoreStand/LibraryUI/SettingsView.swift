import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 設定画面。購入状態、ライブラリの書き出し/読み込み、保存容量、
/// そしてこのアプリの核である「ネットワークに接続しない」ことを明示する。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(PurchaseManager.self) private var purchase
    @Environment(\.modelContext) private var modelContext

    @Query private var scores: [Score]
    @Query private var setlists: [Setlist]

    @State private var isExporting = false
    @State private var exportFileURL: URL?
    @State private var isImportPresented = false
    @State private var isBusy = false
    @State private var progress: Double?
    @State private var resultMessage: String?
    @State private var isResultPresented = false

    @State private var errorMessage: String?
    @State private var isErrorPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("購入") {
                    if purchase.isUnlocked {
                        Label("曲数無制限（購入済み）", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("無料版：\(Entitlement.freeScoreLimit)曲まで登録可能")
                        if let product = purchase.product {
                            Button("購入（\(product.displayPrice)）") {
                                Task { await purchase.purchase() }
                            }
                        } else {
                            Button("購入") {
                                Task {
                                    await purchase.loadProduct()
                                    await purchase.purchase()
                                }
                            }
                        }
                    }
                    Button("購入を復元") {
                        Task { await purchase.restore() }
                    }
                    if case .failed(let message) = purchase.purchaseState {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("ライブラリ") {
                    LabeledContent("保存容量", value: byteCountText(environment.store.totalBytes()))
                    LabeledContent("曲数", value: "\(scores.count)")
                    LabeledContent("セットリスト数", value: "\(setlists.count)")
                }

                Section("バックアップ") {
                    Button {
                        exportLibrary()
                    } label: {
                        Label("書き出し", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isBusy || scores.isEmpty)

                    Button {
                        isImportPresented = true
                    } label: {
                        Label("読み込み", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isBusy)

                    if isBusy, let progress {
                        ProgressView(value: progress)
                    } else if isBusy {
                        ProgressView()
                    }

                    Text("書き出しは Files / iCloud Drive に保存する自分専用のファイルです。読み込みは既存のライブラリに追加するだけで、既存の曲やセットリストが消えることはありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("プライバシー") {
                    Label("このアプリはネットワークに接続しません", systemImage: "wifi.slash")
                        .font(.headline)
                    Text("楽譜も演奏の記録も、すべてこの端末の中だけに保存されます。演奏中に通信が理由で止まることはありません。バックアップも自分で選んだ場所（Files / iCloud Drive）に書き出す方式で、外部サーバーへは一切送信しません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
        .task {
            if purchase.product == nil {
                await purchase.loadProduct()
            }
            await purchase.refreshEntitlements()
        }
        .fileMover(isPresented: $isExporting, file: exportFileURL) { result in
            handleExportCompletion(result)
        }
        .fileImporter(
            isPresented: $isImportPresented,
            allowedContentTypes: [archiveContentType]
        ) { result in
            handleImportResult(result)
        }
        .alert("完了", isPresented: $isResultPresented, presenting: resultMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .alert("エラー", isPresented: $isErrorPresented, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private var archiveContentType: UTType {
        UTType(filenameExtension: ArchiveFormat.fileExtension) ?? .data
    }

    private func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - 書き出し

    /// いったんアプリの一時領域に書き出してから `.fileMover` でユーザーの選ぶ場所へ移す。
    /// 数GB級のPDFがあっても `Data` として抱え込まないための構成。
    private func exportLibrary() {
        isBusy = true
        progress = 0
        let archive = environment.makeArchive()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScoreStand-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension(ArchiveFormat.fileExtension)
        let currentScores = scores
        let currentSetlists = setlists

        Task {
            do {
                try await archive.export(scores: currentScores, setlists: currentSetlists, to: tempURL) { value in
                    progress = value
                }
                exportFileURL = tempURL
                isBusy = false
                isExporting = true
            } catch {
                isBusy = false
                presentError(error)
            }
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            resultMessage = "書き出しが完了しました。"
            isResultPresented = true
        case .failure(let error):
            // ユーザーがピッカーをキャンセルした場合もここに来るため、
            // それだけではエラー表示にしない。
            if (error as NSError).code != NSUserCancelledError {
                presentError(error)
            }
        }
        if let exportFileURL {
            try? FileManager.default.removeItem(at: exportFileURL)
        }
        exportFileURL = nil
    }

    // MARK: - 読み込み

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importArchive(from: url)
        case .failure(let error):
            presentError(error)
        }
    }

    private func importArchive(from url: URL) {
        isBusy = true
        progress = 0
        let archive = environment.makeArchive()
        Task {
            do {
                let outcome = try await archive.importArchive(from: url) { value in
                    progress = value
                }
                isBusy = false
                resultMessage = "曲 \(outcome.scoreCount)件、セットリスト \(outcome.setlistCount)件を読み込みました。"
                isResultPresented = true
            } catch {
                isBusy = false
                presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isErrorPresented = true
    }
}
