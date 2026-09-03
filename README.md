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

- [`docs/decision.md`](docs/decision.md) — **★ 最終決定。まずこれを読む**
- [`docs/verification.md`](docs/verification.md) — 再調査による初回結論の訂正（なぜ結論が変わったか）
- [`docs/research.md`](docs/research.md) — 初回の競合調査（**一部否定済み**）
- [`docs/monetization.md`](docs/monetization.md) — 収益化概算（**単位経済のみ有効**）
- [`docs/requirements.md`](docs/requirements.md) — 要件定義（レビュー用ドラフト）
- [`docs/page-turn-input.md`](docs/page-turn-input.md) — 譜めくり入力の設計空間（**v1では保留**）
- [`docs/proposal-iphone-remote.md`](docs/proposal-iphone-remote.md) — 企画提案: iPhoneを譜めくりリモコンにする
- [`docs/tech-plan.md`](docs/tech-plan.md) — 技術方針（電子楽譜リーダー）
- [`tools/appstore_probe.py`](tools/appstore_probe.py) — 評価・レビューの一次データ取得スクリプト

## 決定 — 電子楽譜リーダー

> **製品の約束: 「本番で絶対に落ちない譜面台」**
> iPad優先 / 買い切り ¥2,500 / 完全オフライン / サーバーなし

2ラウンドの調査の結果、依頼時の選定基準「評価3.5前後のアプリ」は**目的に対して有害**だと判明した。
3.5に沈むアプリは「市場が小さすぎて回復体力がない」か「カテゴリ自体が技術的に難しく誰も上手く
できていない」かに偏り、前者は天井が低く、後者は作り直しても同じ壁に当たる。

基準を次の3点に差し替えて選定した。

1. **支払い意思が実証済み** — forScore が評価4.7・有料で15年続いている
2. **決定的な無料競合が不在** — 純正ファイルアプリでは演奏用途が成立しない
3. **既存勢の弱点が「機能不足」ではなく「信頼性」** — 機能は資本で殴られるが、
   信頼性は丁寧さで抜ける。個人開発の唯一の勝ち筋

日本の incumbent である Piascore に「**本番中にフリーズして完全応答不能**」
「メトロノームとチューナーが同時使用不可」「Dropboxから開くと既存楽譜が上書きされる」という
報告があり、**すべて信頼性の問題**である。

**決め手はコンテンツのライセンスが不要なこと。** 対抗候補だったオフライン地図は地図タイルの
権利処理という重い前提条件を抱えるが、電子楽譜は**ユーザーが自分のPDFを持ち込む**ため
権利処理が一切発生せず、サーバーレス方針と完全に整合する。

- 損益分岐点: **年7本**（固定費 年約1.7万円、手数料15%は有料アプリにも適用されることを Apple 公式で確認）
- 販売本数は**予測しない**。有料アプリのCVRには公開データが存在しないため（[`monetization.md`](docs/monetization.md) 参照）

詳細・却下した候補・**この決定が覆る条件**は [`docs/decision.md`](docs/decision.md) に記載。

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

**①の出力（または CSV）をそのまま貼り付けてもらえれば、実数値で検証する。**
決定は済んでいるので、これは**覆るかどうかの確認**（[`decision.md`](docs/decision.md) の「この決定が覆る条件」）。
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
