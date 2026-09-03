import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// ライブラリ画面。取り込み・検索・並べ替え・タグ絞り込み・削除をここで行う（FR-01〜FR-05, FR-07）。
struct LibraryView: View {
    private enum SortOption: String, CaseIterable, Identifiable {
        case title, composer, createdAt
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title: return "タイトル"
            case .composer: return "作曲者"
            case .createdAt: return "追加日"
            }
        }
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(PurchaseManager.self) private var purchase
    @Environment(\.modelContext) private var modelContext
    @Query private var scores: [Score]

    @State private var searchText = ""
    @State private var sortOption: SortOption = .title
    @State private var selectedTag: String?

    @State private var isImporterPresented = false
    @State private var isPurchaseSheetPresented = false

    @State private var pendingDeleteScore: Score?
    @State private var isDeleteConfirmPresented = false

    @State private var errorMessage: String?
    @State private var isErrorPresented = false

    @State private var performanceContext: PerformanceViewModel.Context?
    @State private var isPerformancePresented = false

    var body: some View {
        NavigationStack {
            List {
                if !allTags.isEmpty {
                    tagFilterSection
                }
                ForEach(filteredScores, id: \.id) { score in
                    NavigationLink {
                        ScoreDetailView(score: score)
                    } label: {
                        ScoreRowView(score: score) {
                            performanceContext = .single(score)
                            isPerformancePresented = true
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        // FR-07: 確認なしに消えない。ここでは要求だけを出し、実削除は確認後に行う。
                        Button(role: .destructive) {
                            pendingDeleteScore = score
                            isDeleteConfirmPresented = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("楽譜")
            .searchable(text: $searchText, prompt: "タイトル・作曲者で検索")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("並べ替え", selection: $sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Label("並べ替え", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        startImportFlow()
                    } label: {
                        Label("取り込み", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if scores.isEmpty {
                    ContentUnavailableView(
                        "楽譜がありません",
                        systemImage: "music.note.list",
                        description: Text("右上の＋から PDF や画像を取り込めます。")
                    )
                } else if filteredScores.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: DocumentImporter.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }
        .sheet(isPresented: $isPurchaseSheetPresented) {
            FreeLimitPurchaseSheet()
        }
        .fullScreenCover(isPresented: $isPerformancePresented) {
            if let performanceContext {
                PerformanceLauncherView(context: performanceContext)
            }
        }
        .confirmationDialog(
            "この曲を削除しますか？",
            isPresented: $isDeleteConfirmPresented,
            presenting: pendingDeleteScore
        ) { score in
            Button("「\(score.title)」を削除", role: .destructive) {
                performDelete(score)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("取り込んだファイルも一緒に削除されます。この操作は元に戻せません。")
        }
        .alert("エラー", isPresented: $isErrorPresented, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - 絞り込み・並べ替え

    private var allTags: [String] {
        Array(Set(scores.flatMap(\.tags))).sorted()
    }

    private var filteredScores: [Score] {
        var result = scores
        if let selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.composer.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOption {
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .composer:
            result.sort { $0.composer.localizedStandardCompare($1.composer) == .orderedAscending }
        case .createdAt:
            result.sort { $0.createdAt > $1.createdAt }
        }
        return result
    }

    private var tagFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    tagChip(title: "すべて", isSelected: selectedTag == nil) { selectedTag = nil }
                    ForEach(allTags, id: \.self) { tag in
                        tagChip(title: tag, isSelected: selectedTag == tag) { selectedTag = tag }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func tagChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 取り込み

    /// 無料枠を超えている場合は取り込みではなく購入導線を出す。
    /// 既存の曲は機能を一切削らず使えることを、購入シート側の文言で明示する。
    private func startImportFlow() {
        if purchase.canAddScore(currentCount: scores.count) {
            isImporterPresented = true
        } else {
            isPurchaseSheetPresented = true
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            do {
                try environment.makeImporter().importScore(from: urls)
            } catch {
                presentError(error)
            }
        case .failure(let error):
            presentError(error)
        }
    }

    private func performDelete(_ score: Score) {
        do {
            try environment.makeImporter().delete(score)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isErrorPresented = true
    }
}

/// 無料枠の上限に達したときに出す購入導線。
///
/// 「機能を削らず曲数だけ制限する」方針を、ここで明文化して伝える。
private struct FreeLimitPurchaseSheet: View {
    @Environment(PurchaseManager.self) private var purchase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("無料版は\(Entitlement.freeScoreLimit)曲まで登録できます")
                    .font(.headline)
                Text("すでに登録した曲は、購入の有無にかかわらずすべての機能をそのまま使えます。上限に達したときだけ、新しい曲の追加に購入が必要になります。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let product = purchase.product {
                    Text(product.displayPrice)
                        .font(.title3.bold())
                }

                Button {
                    Task {
                        if purchase.product == nil {
                            await purchase.loadProduct()
                        }
                        await purchase.purchase()
                        if purchase.isUnlocked {
                            dismiss()
                        }
                    }
                } label: {
                    if purchase.purchaseState == .purchasing {
                        ProgressView()
                    } else {
                        Text("曲数無制限を購入")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(purchase.purchaseState == .purchasing)

                if case .failed(let message) = purchase.purchaseState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .task {
                if purchase.product == nil {
                    await purchase.loadProduct()
                }
            }
            .navigationTitle("曲数の上限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

/// 演奏ビューの部品（`PerformanceViewModel` / 入力ハブ）を1回だけ組み立てて保持するラッパー。
///
/// `fullScreenCover` の中身クロージャは提示中に再評価されることがあるため、
/// 直接 `environment.makePerformance` を呼ぶと呼び出しのたびに別の
/// `PrerenderCoordinator` が作られてしまう。`@State` に確定させて使い回す。
struct PerformanceLauncherView: View {
    let context: PerformanceViewModel.Context

    @Environment(AppEnvironment.self) private var environment
    @State private var built: (
        model: PerformanceViewModel, hub: PageTurnInputHub, tap: TapInputSource, keyboard: KeyboardInputSource
    )?

    var body: some View {
        Group {
            if let built {
                PerformanceView(model: built.model, hub: built.hub, tapSource: built.tap, keyboardSource: built.keyboard)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear {
            if built == nil {
                built = environment.makePerformance(context: context)
            }
        }
    }
}
