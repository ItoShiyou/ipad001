# 実装状況 — v1.0 の M（必須）要件

最終更新: 2026-09-03
コード: [`ios/`](../ios/) — ビルド方法は [`ios/README.md`](../ios/README.md)

---

## 検証の状態（先に読むこと）

### ✅ 済んでいること

`.github/workflows/ios.yml`（GitHub Actions の macOS ランナー、public リポジトリなので無料）で確認済み。

| 項目 | 結果 |
|---|---|
| ビルド | ✅ 成功（Xcode 26.6 / iOS 26.5 SDK / iPad Pro 13-inch シミュレータ / arm64） |
| 単体テスト | ✅ **22件すべて成功、失敗0件** |
| テスト対象 | 通しページ解決、入力ハブのクールダウンと手動優先（P6）、タップ判定領域、描画キーの丸め、無料枠の境界 |

`ios/` を変更して push するたびにこれが自動で回る。**失敗するとエラー行だけが要約されて
ジョブログに出る**ので、そのまま読んで直せる。

### ❌ まだ検証できていないこと

**性能予算は設計しただけで、一度も測っていない。**

| 項目 | なぜ未検証か |
|---|---|
| NFR-01（譜めくり16ms） | **実機でしか測れない。** シミュレータの数値は Mac の性能であり意味がない |
| NFR-02（起動2秒） | 同上 |
| NFR-03（メモリ上限） | 大判PDFを実機で開かないと分からない |
| NFR-11（電池2時間） | 実機のみ |
| Apple Pencil の書き味・パームリジェクション | 実機のみ |
| BLEフットスイッチ | 実機のみ |
| 暗所での可読性 | 実機のみ |

**次にやるべきはこれ**（[`next-actions.md`](next-actions.md) の1番）。
コンパイルが通ることと、製品として成立することは別である。

### 実機で見つかった既知の課題（未修正）

| 項目 | 内容 |
|---|---|
| コントロールバー開閉の上端スワイプ | iPadのシステムジェスチャ（コントロールセンター等）と稀に競合しうる。上端タップでの開閉に置き換える案を実機で試したが、依頼者の判断で元の縦スワイプ方式に戻した（「隠す」導線が使いにくかったため）。実害は許容範囲として現状維持 |
| 演奏開始直後の白画面（間欠的） | 2026-09-04未明、実機で複数回発生。発生時はタップ操作にも無反応になり、その後アプリプロセスが消えていた（iOSのウォッチドッグに強制終了された可能性）。os_logには自前コードのエラー・クラッシュログが一切残っておらず原因未特定。再現条件も不明（同じ操作で再現しないこともある）。デバッグ用のInstruments/lldb接続がデバイス負荷として影響した可能性もあり、切り分けできていない |

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
| NFR-03 | 3ページのみ保持 | `Rendering/PageCache.swift` | ⚠️ 単ページ表示では3枚。**見開き表示では最大5枚**（現在の見開き2枚＋前1枚＋次の見開き2枚）。`PageCache` 自体は上限を持たず、`PerformanceViewModel.refreshWindow` が渡す窓の大きさがそのまま保持数になる。要件文言（3ページのみ）と食い違うため、見開き時の挙動として妥当と判断するなら要件側の文言を直すべき |
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

## S / C 要件のベータ実装（2026-09-04）

M（v1必須）ではないが、設計書にある機能として着手した。**すべて機能としては動くが、
実機での検証（特に暗所・実際の演奏環境）が済んでいない**ため、UI上に「ベータ」と明示している。

| ID | 要件 | 実装 | 状態 |
|---|---|---|---|
| FR-50/51/52/54 | メトロノーム・チューナー（同時使用可） | `Practice/MetronomeEngine.swift`, `Practice/TunerEngine.swift`, `Practice/PracticeToolsView.swift` | ✅ ベータ。ピッチ検出は自己相関法。マイクの実機特性は未検証 |
| FR-53 | 曲ごとのテンポ・拍子の記憶 | 既存の `Score.tempoBPM`/`timeSignature` を `PracticeToolsView` から編集可能に | ✅ |
| FR-26 | リピート / D.S. / Coda へのジャンプ登録 | `Model/JumpPoint.swift`、`ScoreDetailView` で編集、演奏ビューに1操作の導線 | ✅ ベータ。暗所での押しやすさ（P5）は未検証 |
| FR-34 | セットリストの書き出し | `SetlistEditorView` に `ShareLink` でテキスト書き出し | ✅ ベータ・テキストのみ。PDF化は未実装 |
| FR-06（追記側） | 既存の曲へPDF/画像を追記 | `DocumentImporter.appendSources` は既存、`ScoreDetailView` にボタンを追加して配線 | ✅ 「複数PDFを1曲として連結」（取り込み時のマージ）は元から実装済み。PDF分割（1PDFを複数曲に）は未実装 |
| FR-14 | 画面の明るさ調整 | `PerformanceView` の操作バーに4段階の循環ボタン | ✅ ベータ |

## 保留・v1対象外（実装しない、または今回は着手しなかった判断）

| 項目 | 状態 |
|---|---|
| ハンズフリー譜めくり（顔・視線、FR-80〜89） | **保留**（[`page-turn-input.md`](page-turn-input.md)）。`decision.md` に記録された明示的な製品判断であり、設計書に載っていることを理由に上書きしない |
| 演奏タイミングの記録と自動スクロール（FR-90〜99） | v1.5 スコープ。自動でページをめくる機能は「本番で落ちない」という製品の約束を最も壊しやすい部類のため、実機検証なしには着手しない |
| MIDI入力（FR-27） | 物理的なMIDI機器がないと動作確認できないため未着手。§11-Q15 未回答 |
| iPhone をリモコンにする（FR-29） | v1.x の本命候補（[`proposal-iphone-remote.md`](proposal-iphone-remote.md)）。2台以上の実機が要る規模の機能のため未着手 |
| カメラでの紙楽譜取り込み（FR-08） | カメラでの実機検証ができないため未着手 |
| 外部ディスプレイ対応（FR-17） | 外部ディスプレイでの実機検証ができないため未着手 |
| PDF分割（FR-06のもう半分） | 未着手。ページ範囲選択UIが要る |
| 半ページめくり（FR-23） | 未着手。譜めくりの中核パス（今回複数のバグを直した箇所）に触れるため、実機で検証できない状態での変更を避けた |
| 拡大・スクロール位置の記憶（FR-15） | 未着手。前提となる拡大・スクロール機能自体がまだ無く、演奏ビューにジェスチャーを追加する変更は実機検証なしに避けた |
| Android 版 | P4 |
