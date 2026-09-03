# ipad001 / ScoreStand

iPad を「本番で絶対に落ちない譜面台」にする、買い切り・完全オフラインの電子楽譜リーダー。

## まずこれを読む

| ファイル | 内容 |
|---|---|
| [`docs/decision.md`](docs/decision.md) | **何を作るか、なぜそれか。** 最初に読む |
| [`docs/requirements.md`](docs/requirements.md) | 要件定義（FR/NFR の採番あり）。仕様の唯一の出典 |
| [`docs/implementation-status.md`](docs/implementation-status.md) | 実装状況と、**未検証事項** |
| [`ios/README.md`](ios/README.md) | ビルド方法と設計上の不変条件 |
| [`docs/verification.md`](docs/verification.md) | 初回調査が誤っていた経緯。**同じ間違いを繰り返さないため** |

## ビルド

```bash
brew install xcodegen
cd ios && xcodegen generate && open ScoreStand.xcodeproj
```

`.xcodeproj` はコミットしない（マージ衝突の温床）。`ios/project.yml` から生成する。

**この開発環境（Linux コンテナ）では一切ビルドできない。** Swift ツールチェーンが無く、
PDFKit / PencilKit / SwiftData / StoreKit は Apple プラットフォーム専用のため。
コンパイル検証は `.github/workflows/ios.yml`（macOS ランナー、public リポジトリなので無料）で行う。
**コードを変更したら、push して CI の結果を確認するまでが1セット。**

## 破ってはいけない設計原則

要件変更ではなく実装判断としてこれを崩す提案は、まず拒否してよい。

| # | 原則 | 実装上の帰結 |
|---|---|---|
| P1 | **演奏中の1フレームは、どんな機能よりも重い** | 演奏中は背景処理を止める（`PerformanceSession.perform(deferrable:)` を通す） |
| P2 | **通信しないことは機能である** | `URLSession` を含む通信APIを一切参照しない。`Info.plist` に用途説明キーを増やさない |
| P3 | **ユーザーの楽譜を壊さない** | 元PDFは非破壊。注釈は別レイヤ。書庫の読み込みは常に「追加」で、既存を消さない |
| P4 | **買い切りで売った機能を後から取り上げない** | サブスクへ機能を移さない |
| P5 | **本番の操作は、暗所で・見ずに・片手で** | 演奏ビューに設定系の導線を置かない |
| P6 | **自動化は提案しかできない。人間の操作が常に勝つ** | `PageTurnInputHub` が手動入力の直後は自動入力を抑止する |

## 構造上の要点

- **`Rendering/`** — 譜めくり応答16ms（NFR-01）は「めくる前に描き終えている」ことでしか達成できない。
  保持は前・現在・次の3枚のみ（NFR-03）。この2点を崩す変更は入れない。
- **`Input/`** — 方式が何であれ単一の `PageTurnEvent` に変換する。
  新しい入力方式は `PageTurnInputSource` を実装して `PageTurnInputHub.register` するだけで足り、
  演奏ビューには手を入れない。
- **`Backup/`** — iOS に公開 unzip API が無いため独自コンテナ。
  仕様は [`docs/archive-format.md`](docs/archive-format.md) で公開している（FR-62）。**形式を変えるときは仕様書も直す。**

## コードの書き方

- コメントは**日本語**。「何をしているか」ではなく**「なぜそうしたか」**を書く。既存の密度に合わせる。
- ユーザーに見せるエラーは `LocalizedError` で日本語にする。握り潰さない。
- iOS 17 が下限。`#Index` など iOS 18 以降の API は使えない。

## 保留中の判断

- **ハンズフリー譜めくり** — 顔・視線認識は TrueDepth 非搭載機で意味がなく、MIDI はペダル所有者が少ない。
  v1 では保留（[`docs/page-turn-input.md`](docs/page-turn-input.md)）。
  追加購入ゼロで全員に効く案として [`docs/proposal-iphone-remote.md`](docs/proposal-iphone-remote.md) を保持。
