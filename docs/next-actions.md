# あなたにしかできないこと（優先順）

私（Claude）側でできることはやり切った。以下は**物理的・制度的に私では代行できない**もの。
上から順に、後続の判断をより多く解除する順に並べてある。

---

## 1. 【最優先】実機で 16ms を測る — この製品が成立するかの判定

**なぜ最優先か**: 「本番で落ちない・待たせない」が唯一の売り文句であり、
それが実機で成立しなければ**製品の前提そのものが崩れる**。他の作業はすべてこの後でよい。
逆にここが通れば、残りは順当に積み上げるだけになる。

### 必要なもの

| もの | 備考 |
|---|---|
| **Mac** | MacBook でなくてよい。**Mac mini が最安**（画面・キーボードは手持ちを流用）。中古の M1/M2 で十分 |
| **iPad 実機** | お持ちのもの。シミュレータの数値は Mac の性能なので**意味がない** |
| Lightning / USB-C ケーブル | |
| Apple ID | **無料で可**。証明書が7日で切れるが検証には足りる |

### 手順

```bash
brew install xcodegen
git clone https://github.com/ItoShiyou/ipad001.git
cd ipad001/ios
xcodegen generate
open ScoreStand.xcodeproj
```

1. Xcode で `project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を自分のものに変える
   （`com.example.ScoreStand` のままでは実機に入らない）
2. Signing & Capabilities で自分の Apple ID を選ぶ
3. iPad を繋いで Run
4. **100ページ以上ある大判の楽譜PDF**を取り込む（薄い楽譜では意味のある計測にならない）
5. Xcode の Instruments → **os_signpost** 計器で `pageTurn` の区間を見る

### 見るべき数値

| 指標 | 目標 | 判定 |
|---|---|---|
| `pageTurn` 区間 | **16ms 以内** | 超えるなら設計の見直しが要る。私に数値を渡してほしい |
| `coldStartToScore` | 2.0秒以内 | |
| ピークメモリ | 大判PDFでも一定 | 増え続けるならキャッシュの取りこぼし |

**結果を貼ってもらえれば、そこから先は私が対応する。**

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
- **CI**: `.github/workflows/ios.yml` が push ごとにビルドと単体テストを回す（public リポジトリなので無料）
- **未検証**: 実機での性能、Apple Pencil、フットスイッチ、暗所、電池 —— いずれも **1** が前提
