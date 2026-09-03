# ipad001 — 買い切りネイティブアプリ 事業化リサーチ

「既に買い切りアプリとして存在するが、問題を抱えて評価3.5前後に留まっているアプリ」を特定し、
**完全ネイティブ / ローカル完結 / サーバーレス** で作り直す、という前提の調査リポジトリ。

## 前提条件（依頼者要件）

| 項目 | 内容 |
|---|---|
| 形態 | 完全ネイティブアプリ（クロスプラットフォームFWは使わない） |
| 主ターゲット | iPad（iPadOS）を第一級市民として設計 |
| 副ターゲット | iPhone / Android |
| データ | ローカル完結。サーバーを持たない（運用リスク・個人情報リスクの排除） |
| 更新 | 定期的なアプリ更新のみ。バックエンド運用なし |
| 課金 | 買い切り（非消費型IAP または 有料アプリ） |

## ドキュメント

- [`docs/verification.md`](docs/verification.md) — **⚠️ 最初に読むこと。** 再調査による初回結論の訂正
- [`docs/research.md`](docs/research.md) — 初回の競合調査（**一部否定済み**）
- [`docs/monetization.md`](docs/monetization.md) — 収益化概算（**単位経済のみ有効**）
- [`docs/tech-plan.md`](docs/tech-plan.md) — 技術的実現可能性とアーキテクチャ方針
- [`tools/appstore_probe.py`](tools/appstore_probe.py) — 評価・レビューの一次データ取得スクリプト

## 現時点の結論（要約）

**初回調査の結論は、別アプローチによる再調査で再現されなかった。実装には進んでいない。**

確度をもって言えることは3点のみ:

1. **「評価3.5」という条件の向き先を間違えていた。** 初回に競合として挙げたアプリは
   Anytune 4.8 / Capo 4.7 / GoodReader 4.66 / Teleprompter Pro 4.75 / PromptSmart Pro 4.61 と、
   **すべて4.5以上**だった。大型アプリは炎上しても、レビュー総数の多さに希釈されて集計評価が戻る。
   実際に3.5前後で低迷しているのは、**回復する体力のない小規模で放置気味のアプリ**である。
2. **単位経済は有効。** Small Business Program の15%が有料アプリにも適用されることを
   Apple 公式で確認。固定費は年約1.7万円、**損益分岐点は年7本**。サーバーを持たない方針の優位は揺らいでいない。
3. **販売本数の予測は現時点では不可能。** 有料アプリのページビュー→購入CVRには公開データが存在しない。

数値の裏付けを伴って挙がった候補は2件のみ（いずれも要一次検証）:
**INKredible**（手書きノート、Google Play 3.34 / 約25,000件）と
**Piascore**（電子楽譜、日本、星評価未取得だが本番中フリーズ等の実害報告あり）。

詳細は [`docs/verification.md`](docs/verification.md) を参照。

## 次にやること — 一次データの取得（依頼者の手元で実行）

この環境からは Apple のドメインに到達できないため、**星評価の一次データはローカルで取る必要がある。**
`tools/appstore_probe.py` は Python 3.9+ の標準ライブラリのみで動く（インストール不要）。

```bash
git clone <このリポジトリ> && cd ipad001

# ① 発掘 ← 本命。「評価3.2〜3.8 かつ 有料 かつ iPad対応」のアプリを横断的に探す
python3 tools/appstore_probe.py discover --country jp --csv jp.csv
python3 tools/appstore_probe.py discover --country us --csv us.csv

# ② 検証。docs/ で言及した既存候補の現在値と否定的レビューを確定させる
python3 tools/appstore_probe.py check --country jp --reviews 30 > check_jp.txt

# ③ 名前からIDを解決したいとき
python3 tools/appstore_probe.py search Piascore INKredible
```

**①の出力（または CSV）をそのまま貼り付けてもらえれば、実数値で再ランキングする。**
該当が少なすぎる場合は `--band 3.0 4.0` や `--min-ratings 50` で条件を緩める。
`discover` は約60個の検索語を舐めるので、完了まで1〜2分かかる。

なぜ `discover` が重要か: 初回調査の失敗は「有名アプリを先に思いつき、後から評価を当てはめようとした」
ことに起因する。`discover` は逆順で、**先に評価3.5前後の有料アプリを機械的に列挙してから
中身を見る。** 依頼の条件をそのままクエリにしている。

## ⚠️ データの信頼性について

本調査の実行環境はネットワーク egress ポリシーにより
`apps.apple.com` / `itunes.apple.com` / `play.google.com` および主要なアプリ分析サイトへの
直接アクセスが**遮断されている**。そのため個別アプリの星評価・レビュー件数は
**検索エンジン経由の二次情報**であり、確定値ではない。

意思決定の前に [`tools/appstore_probe.py`](tools/appstore_probe.py) を
**ローカル環境で実行して一次データを取得すること**（手順は同ファイル冒頭に記載）。
