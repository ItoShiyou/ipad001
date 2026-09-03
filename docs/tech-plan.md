# 技術的実現可能性とアーキテクチャ方針

対象: 候補① 音楽練習用オーディオプレイヤー（第1弾）

---

## 1. 方針

| 項目 | 決定 |
|---|---|
| iOS/iPadOS | **Swift + SwiftUI**（ネイティブ）。音声処理は AVFoundation / AVAudioEngine |
| Android | **Kotlin + Jetpack Compose**（ネイティブ）。音声は Oboe (AAudio) |
| 共通化 | UIは共通化しない。**DSPコアのみ C++ で共有**する余地を残す |
| 通信 | **なし**。ネットワーク権限そのものを Info.plist / manifest から落とす |
| 永続化 | iOS: SwiftData（または Core Data）／ Android: Room。いずれも端末内 |
| 同期 | 任意で iCloud Drive / CloudKit private DB。**ユーザー自身のストレージであり自前サーバーではない** |
| 分析基盤 | **入れない**。クラッシュ情報は Apple/Google 標準のものだけを使う |

> 「ネットワーク権限を持たない」ことは App Store のプライバシーラベル上
> "Data Not Collected" と表示でき、**それ自体がストアページ上のセールスポイントになる。**

---

## 2. 中核の技術要素と難易度

| 機能 | iOS 実装 | Android 実装 | 難度 |
|---|---|---|---|
| 速度変更（ピッチ維持） | `AVAudioUnitTimePitch` (rate) | Oboe + Sonic / SoundTouch | 低 |
| ピッチ変更（速度維持） | `AVAudioUnitTimePitch` (pitch) | 同上 | 低 |
| サンプル精度ABループ | `AVAudioPlayerNode.scheduleSegment` を連結 | 自前リングバッファ | **中** |
| 波形描画 | `AVAssetReader` でPCM取得 → ダウンサンプル → Canvas/Metal | MediaCodec で PCM 取得 → Canvas | 中 |
| スペクトログラム | `vDSP` FFT | KissFFT / 自前 | 中 |
| EQ | `AVAudioUnitEQ` | 自前 biquad | 低 |
| センター音源除去 | L−R 減算 + 帯域制限（自前DSP） | 同上 | 中 |
| メトロノーム重畳 | 別 `AVAudioPlayerNode` をミックス | 同上 | 低 |
| バックグラウンド再生 | `AVAudioSession` + Now Playing | MediaSession + Foreground Service | 低 |
| Split View / Stage Manager | SwiftUI で標準対応 | — | 低 |
| ファイル取り込み | `UIDocumentPicker` / Files / `MPMediaPickerController` | SAF | 低 |

**総評: 個人開発の射程内。** 最も工数がかかるのは DSP ではなく
「波形UIの操作感」と「iPadの各種マルチタスク・外部入力への対応」。
そしてそここそが既存競合（Amazing Slow Downer の旧世代UI、Anytune の Split View 非対応）
が落としているポイントであり、**投資先として正しい**。

### 注意すべき制約
- **DRM保護された Apple Music / Spotify の楽曲は加工できない。** これは技術的制約ではなく
  ライセンス上の制約であり、回避不能。ストアページとオンボーディングで**最初に明示する**こと。
  Amazing Slow Downer はここで期待値の裏切りを起こしレビューを落としている。
- Android の低遅延音声はデバイス差が大きい。**Android版はiOS版の完全移植ではなく、
  機能を絞った版として後追いで出す**のが安全。

---

## 3. iPad ファーストの具体的な意味

単に「大画面に対応する」ではなく、以下を初期リリースの必須要件とする。

- [ ] Split View / Slide Over / Stage Manager（楽譜PDFやブラウザと並べて使うのが実使用）
- [ ] 外部ディスプレイ（Stage Manager 経由の独立表示）
- [ ] ハードウェアキーボードショートカット（再生/停止、ループ点設定、速度±）
- [ ] トラックパッド / マウスのポインタ対応、波形上でのスクラブ
- [ ] Apple Pencil でのループ範囲・マーカー指定
- [ ] ダーク/ライト、Dynamic Type、VoiceOver（AppleVis 系コミュニティでの評価が獲得できる）
- [ ] 縦横両対応、Slide Over 幅でも破綻しないレイアウト

---

## 4. リリース計画（案）

| フェーズ | 内容 | 目安 |
|---|---|---|
| P0 | 一次データ再検証（`tools/appstore_probe.py`）、スコープ確定 | 数日 |
| P1 | iPad版 v1.0: 再生・速度・ピッチ・ABループ・波形・マーカー・永続化 | — |
| P2 | iPhone対応、バックグラウンド再生、EQ、メトロノーム | — |
| P3 | Android版（機能を絞った移植） | — |
| P4 | Mac版（Universal Purchase）、アドオン課金 | — |

---

## 5. リポジトリ構成（予定）

```
ipad001/
├── README.md
├── docs/
│   ├── research.md        # 競合・市場調査
│   ├── monetization.md    # 収益化概算
│   └── tech-plan.md       # 本ファイル
├── tools/
│   └── appstore_probe.py  # 評価・レビューの一次データ取得
├── ios/                   # (P1〜) Swift / SwiftUI
└── android/               # (P3〜) Kotlin / Compose
```
