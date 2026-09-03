# ScoreStand（iOS / iPadOS）

[`../docs/requirements.md`](../docs/requirements.md) の **M（v1必須）要件**の実装。

## ビルド方法

この iOS アプリは Apple プラットフォーム専用フレームワーク（PDFKit / PencilKit /
SwiftData / StoreKit 2）に依存するため、**Mac + Xcode でしかビルドできない**。
リポジトリには `.xcodeproj` を含めず、[XcodeGen](https://github.com/yonaskolb/XcodeGen)
で生成する（`.xcodeproj` はマージ衝突の温床になるため）。

```bash
brew install xcodegen
cd ios
xcodegen generate
open ScoreStand.xcodeproj
```

`project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` と `DEVELOPMENT_TEAM` は各自のものに変更すること。

## 構成

| ディレクトリ | 役割 |
|---|---|
| `App/` | エントリポイント、依存の組み立て |
| `Model/` | SwiftData モデル（Score / Setlist / 注釈 …） |
| `Library/` | 楽譜の取り込みと、アプリコンテナ内での実体管理 |
| `Rendering/` | **★中核。** ページの事前描画とキャッシュ（NFR-01 / NFR-03） |
| `Input/` | **★中核。** 統一譜めくり入力層（タップ / HIDキーボード / 将来の拡張） |
| `Performance/` | 演奏ビュー |
| `LibraryUI/`, `SetlistUI/` | ライブラリとセットリストの画面 |
| `Annotation/` | PencilKit による非破壊注釈 |
| `Crop/` | 余白の自動検出 |
| `Backup/` | ライブラリ全体の書き出し / 読み込み（公開フォーマット） |
| `Purchase/` | StoreKit 2。無料3曲 → 買い切り解放 |
| `Support/` | ログ、性能計測 |

## 設計上の不変条件

- **演奏中はバックグラウンド処理を走らせない**（NFR-05）。`PerformanceSession` が
  取り込み・サムネイル生成・インデックス作成を止める。
- **保持するページは「前・現在・次」の3枚のみ**（NFR-03）。
- **元PDFは改変しない**（P3）。注釈は別レイヤ。
- **ネットワークを使わない**（NFR-07）。`URLSession` を含むいかなる通信APIも参照しない。
- **自動化は提案しかできない。手動入力が常に勝つ**（P6）。
