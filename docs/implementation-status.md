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
| FR-10 | 単ページ / 見開き | `Performance/PerformanceViewModel.swift`, `PageImageView.swift` | ✅ 二枚並べ描画に対応。見開き時は次の見開きの左ページまで先読みする |
| FR-11 | 余白の自動検出とトリミング | `Crop/MarginDetector.swift`, `Crop/PageCropView.swift`, `Crop/ScoreCropListView.swift` | ✅ |
| FR-13 | 反転表示 | `Performance/PageImageView.swift` | ✅ |
| FR-16 | 縦横で破綻しない | `Resources/Info.plist`, 各ビュー | ✅ |
| FR-20 | タップ / スワイプ | `Input/TapInputSource.swift` | ✅ |
| FR-21 | BLEフットペダル | `Input/KeyboardInputSource.swift` | ✅ HIDキーボードとして受ける |
| FR-22 | キーボードショートカット | 同上 + `Performance/PerformanceView.swift` | ✅ |
| FR-24 | 前後1ページを事前描画 | `Rendering/PrerenderCoordinator.swift` | ✅ 設計済み・**未計測** |
| FR-25 | 誤操作防止ロック | `PerformanceSession.swift`, `PerformanceView.swift` | ✅ 譜めくりは残し、それ以外（操作バー・注釈編集）を止める。解除は長押し |
| FR-28 | 汎用BTリモコン | `Input/KeyboardInputSource.swift` | ✅ |
| FR-29b | 広いタップ領域 | `Input/TapInputSource.swift`（左右1/3） | ✅ |
| FR-30 | セットリストの作成・編集 | `SetlistUI/` | ✅ |
| FR-31 | 曲間の連続送り | `Performance/PerformanceViewModel.swift` | ✅ |
| FR-32 | 任意の曲へ飛ぶ | `Performance/PerformanceView.swift` | ✅ 演奏中に曲名の横並びから飛べる |
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

### M 要件は一通り実装済み

**ただし「実装済み」＝「動作確認済み」ではない。** 上の警告のとおり一度もビルドしていない。
次にやるべきは機能追加ではなく、**ビルドを通し、実機で性能を測ること**（スパイク SP-1）。

なお FR-25 は当初「ロック時に入力を止める」と読んでいたが、要件の文言は
「譜めくり**以外**を無効化」である。したがって**ロック中も譜めくりは動く**。
誤タップから守る目的なので、これが正しい。解除をタップにすると誤タップで解除されてしまうため長押しにした。

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
