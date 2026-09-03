# あなたにしかできないこと（優先順）

私（Claude）側でできることはやり切った。以下は**物理的・制度的に私では代行できない**もの。
上から順に、後続の判断をより多く解除する順に並べてある。

---

## 1. 【最優先】実機で 16ms を測る — この製品が成立するかの判定

**なぜ最優先か**: 「本番で落ちない・待たせない」が唯一の売り文句であり、
それが実機で成立しなければ**製品の前提そのものが崩れる**。他の作業はすべてこの後でよい。
逆にここが通れば、残りは順当に積み上げるだけになる。

### 環境

**MacBook Air M2 / 16GB** — Xcode の開発機として十分。
実機の iPad と USB-C ケーブルを用意する。**シミュレータの数値は Mac の性能なので意味がない。**
Apple ID は**無料のもので足りる**（証明書が7日で切れるが、検証用途なら問題ない）。

### 手順

```bash
# 1. 準備（初回のみ）
brew install xcodegen
git clone https://github.com/ItoShiyou/ipad001.git
cd ipad001/ios

# 2. Xcode プロジェクトを生成して開く
xcodegen generate
open ScoreStand.xcodeproj
```

3. `ios/project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を自分のものに変える
   （`com.example.ScoreStand` のままでは実機に入らない）。変更後は `xcodegen generate` をやり直す
4. Signing & Capabilities で自分の Apple ID を選ぶ
5. iPad を繋いで Run
6. **100ページ以上ある大判の楽譜PDF**を取り込む（薄い楽譜では先読みの検証にならない）
7. Product → Profile で Instruments を起動し、**os_signpost** 計器を選ぶ

### 見るべき数値

| signpost | 目標 | 意味 |
|---|---|---|
| `pageTurn` | **16ms 以内**（NFR-01） | 超えるなら先読みが間に合っていない。設計の見直しが要る |
| `coldStartToScore` | 2.0秒以内（NFR-02） | 起動から譜面が出るまで |
| ピークメモリ | 大判PDFでも一定（NFR-03） | 増え続けるならキャッシュの取りこぼし |

**数値を貼ってもらえれば、そこから先の改善は私がやる。**

### ついでに確認してほしいこと（実機でしか分からない）

- [ ] Apple Pencil の書き味、パームリジェクション（手をついて書けるか）
- [ ] 譜めくりのタップ領域（画面幅の左右1/3）が、演奏姿勢で押しやすいか
- [ ] 反転表示が暗所で実用になるか
- [ ] Split View で楽譜と他アプリを並べたときに破綻しないか

---

## 2. 競合の実数値を確定させる（2分・Mac不要）

`docs/decision.md` は **Piascore の星評価が未確認のまま**確定させている。
この前提が崩れると方針が変わる。どの環境でもよい（Python 3 のみ）。

```bash
python3 tools/appstore_probe.py search Piascore forScore
python3 tools/appstore_probe.py discover --country jp
```

出力を貼ってくれれば、`decision.md` の「この決定が覆る条件」に照らして判定する。

---

## 3. 要件の穴を埋める（あなたの演奏経験でしか埋まらない）

[`requirements.md`](requirements.md) §11 の質問。特にこの3つ。

- **Q2**: 今どのアプリを使っていて、**本番で実際に起きた事故**は何か
  → NFR の目標値と受け入れ基準が、私の想像ではなく実際の失敗から決まる
- **Q7**: **アンサンブルで複数台を同期**させたいか
  → v1スコープの最大の分岐。ローカル直結で実現できるので、要るなら今のうちに設計へ入れる
- **Q14**: 「これが無いと本番では使えない」ものが他にあるか

残り11問は一言ずつでよい。

---

## 4. App Store Connect の準備（リリースを見据えるなら）

私にはできない。すべて Apple ID に紐づく手続きのため。

- [ ] Apple Developer Program 登録（年 $99）
- [ ] App Store Connect でアプリを作成し、**Bundle ID を確定**
- [ ] **非消費型 IAP を作成**。Product ID を `com.example.ScoreStand.unlock` から変更した場合は
      `Purchase/PurchaseManager.swift` の `unlockProductID` も合わせる
- [ ] StoreKit の動作確認は Xcode の **StoreKit Configuration File** でローカルに試せる
      （Sandbox アカウントを作る前に、まずこちらで十分）

---

## 5. 私が代行できること（依頼してくれれば動く）

- ビルドエラー・テスト失敗の修正（CI の結果は私が直接読める）
- 実機で測った数値をもとにした性能改善
- 残りの S / C 要件の実装（メトロノーム、チューナー、MIDI、iPhoneリモート）
- Android 版
- ストア掲載文・スクリーンショットの構成案

---

## 現在の状態

- **コード**: M（必須）要件は一通り実装済み。[`implementation-status.md`](implementation-status.md) に対応表
- **ビルド**: ✅ **macOS ランナーで通ることを確認済み**（Xcode 26.6 / iOS 26.5 SDK / iPad Pro 13-inch シミュレータ）
- **CI**: `.github/workflows/ios.yml` が `ios/` への push ごとにビルドと単体テストを回す。
  public リポジトリなので macOS ランナーは無料。**失敗すればエラー行だけが要約されて出る**ので、
  私がそのまま読んで直せる
- **未検証**: 実機での性能、Apple Pencil、フットスイッチ、暗所、電池 —— いずれも **1** が前提
