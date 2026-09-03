# 実装状況 — v1.0 の M（必須）要件

最終更新: 2026-09-03
コード: [`ios/`](../ios/) — ビルド方法は [`ios/README.md`](../ios/README.md)

---

## ⚠️ 検証できていないこと（先に読むこと）

このコードは **Linux コンテナ上で書かれており、一度もコンパイルされていない。**
PDFKit / PencilKit / SwiftData / StoreKit 2 は Apple プラットフォーム専用であり、
Swift ツールチェーン自体もこの環境に存在しないため、原理的に検証不可能だった。

したがって:

- **初回ビルドで型エラーが出ることを前提とすること。** 設計は通っているが、綴りや
  引数ラベルの取り違えは残っている可能性がある。
- 性能予算（NFR-01 の16ms、NFR-02 の2秒）は**設計しただけで、まだ測っていない**。
  実機で測るまで達成しているとは言えない。スパイク SP-1 がこれにあたる。
- 単体テストは書いてあるが**実行されていない**。

`xcodegen generate` → ビルド → テスト実行が、この後の最初の作業になる。

---

## M 要件の対応表

| ID | 要件 | 実装 | 状態 |
|---|---|---|---|
| FR-01 | PDF の取り込み | `Library/DocumentImporter.swift` | ✅ |
| FR-02 | 画像の取り込み | 同上 | ✅ |
| FR-03 | 実体をコピーして保管 | `Library/ScoreStore.swift` | ✅ |
| FR-04 | メタデータ | `Model/Score.swift`, `LibraryUI/ScoreDetailView.swift` | ✅ |
| FR-05 | 絞り込み・並べ替え | `LibraryUI/LibraryView.swift` | ✅ |
| FR-07 | 削除は確認を伴う | 同上（確認ダイアログ） | ✅ |
| FR-10 | 単ページ / 見開き | `Performance/PerformanceViewModel.swift` | ⚠️ 状態は保持するが、見開きの**二枚並べ描画は未実装**（現状は1枚表示のまま） |
| FR-11 | 余白の自動検出とトリミング | `Crop/MarginDetector.swift`, `Crop/PageCropView.swift`, `Crop/ScoreCropListView.swift` | ✅ |
| FR-13 | 反転表示 | `Performance/PageImageView.swift` | ✅ |
| FR-16 | 縦横で破綻しない | `Resources/Info.plist`, 各ビュー | ✅ |
| FR-20 | タップ / スワイプ | `Input/TapInputSource.swift` | ✅ |
| FR-21 | BLEフットペダル | `Input/KeyboardInputSource.swift` | ✅ HIDキーボードとして受ける |
| FR-22 | キーボードショートカット | 同上 + `Performance/PerformanceView.swift` | ✅ |
| FR-24 | 前後1ページを事前描画 | `Rendering/PrerenderCoordinator.swift` | ✅ 設計済み・**未計測** |
| FR-25 | 誤操作防止ロック | `Performance/PerformanceSession.swift` | ⚠️ 状態は持つが、**ロック時の入力抑止が未配線** |
| FR-28 | 汎用BTリモコン | `Input/KeyboardInputSource.swift` | ✅ |
| FR-29b | 広いタップ領域 | `Input/TapInputSource.swift`（左右1/3） | ✅ |
| FR-30 | セットリストの作成・編集 | `SetlistUI/` | ✅ |
| FR-31 | 曲間の連続送り | `Performance/PerformanceViewModel.swift` | ✅ |
| FR-32 | 任意の曲へ飛ぶ | `SetlistUI/SetlistEditorView.swift` | ⚠️ 編集画面からは可能。**演奏中の曲間ジャンプUIが未実装** |
| FR-40 | 手書き注釈 | `Annotation/` | ✅ |
| FR-41 | 元PDFを改変しない | `Annotation/AnnotationOverlay.swift` | ✅ 構造で保証 |
| FR-42 | 注釈の表示切替 | 同上 | ✅ |
| FR-43 | 消しゴム・色・太さ・取消 | `PKToolPicker` | ✅ |
| FR-60 | 単一ファイルで書き出し / 読み込み | `Backup/` | ✅ |
| FR-61 | 書き出し先はユーザーの領域 | `LibraryUI/SettingsView.swift` | ✅ |
| FR-70 | 無料3曲 | `Purchase/Entitlement.swift` | ✅ |
| FR-71 | 買い切りで解放 | `Purchase/PurchaseManager.swift` | ✅ |
| FR-72 | Universal Purchase | 単一の非消費型IAP | ✅ |
| FR-73 | 復元・オフライン保持 | `Purchase/PurchaseManager.swift` | ✅ ローカルフラグで先に解放判定 |
| NFR-03 | 3ページのみ保持 | `Rendering/PageCache.swift` | ✅ |
| NFR-05 | 演奏中は背景処理を止める | `Performance/PerformanceSession.swift` | ✅ 仕組みは実装。**呼び出し側の網羅は要確認** |
| NFR-06 | 演奏中はスリープしない | 同上 | ✅ |
| NFR-07 | ネットワークを使わない | `Info.plist` に用途説明キーなし、`URLSession` 不参照 | ✅ |

### 残っている M の穴（次にやること）

1. **FR-10 見開きの二枚並べ描画** — 状態とキャッシュ（4ページ分）は用意済み。表示側が未対応。
2. **FR-25 ロック時の入力抑止** — `PerformanceSession.isLocked` を `PageTurnInputHub` が見ていない。
3. **FR-32 演奏中の曲間ジャンプUI** — `PageTurnCommand.jump` と `.nextScore` は実装済みで、UIだけが無い。

いずれも既存の型に乗るだけで、設計変更は要らない。

---

## 保留・v1対象外

| 項目 | 状態 |
|---|---|
| ハンズフリー譜めくり（顔・視線） | **保留**（[`page-turn-input.md`](page-turn-input.md)） |
| MIDI入力 | S に降格。所有者が少ないため |
| iPhone をリモコンにする | v1.x の本命候補（[`proposal-iphone-remote.md`](proposal-iphone-remote.md)） |
| 演奏タイミングの記録と自動スクロール | v1.5 |
| メトロノーム / チューナー | S。v1 では未実装 |
| Android 版 | P4 |
