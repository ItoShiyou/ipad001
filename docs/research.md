> # ⚠️ このドキュメントは検証により一部が否定されている
>
> 2026-09-03 の再調査（[`verification.md`](verification.md)）で、本ドキュメントの
> **中核的な前提が誤りであることが判明した。** 単独で読まないこと。
>
> 主な誤り: 本文で挙げた競合（Anytune 4.8 / Capo 4.7 / GoodReader 4.66 /
> Teleprompter Pro 4.75 / PromptSmart Pro 4.61）は**いずれも評価3.5前後ではなく4.5以上**だった。
> 「評価3.5」という条件は、有名アプリの炎上ではなく**小規模で放置気味のアプリ**を指す。
>
> また「Anytune は Split View 非対応」は**反証済み**（v4.4 で対応済み、現行 v4.8.5）。
>

# 競合調査・市場調査

調査日: 2026-09-03

---

## 0. 調査手法と限界

- 使用: Web検索（複数クエリ / 日英）
- **使用できなかったもの**: App Store / Google Play の直接参照、iTunes Lookup API、
  AppFollow・Sensor Tower・justuseapp・APPLION 等のアプリ分析サイト
  （いずれも本セッションの egress ポリシーで 403 ブロック）
- したがって**個別アプリの星評価は検索スニペット由来の二次情報**であり、
  「約」「〜前後」表記は確定値ではない。`tools/appstore_probe.py` での再検証を必須とする。

---

## 1. 前提となるマクロ数値

| 指標 | 値 | 意味 |
|---|---|---|
| App Store 総アプリ数 / 有料アプリ平均価格 | 約160万本 / 約$0.88 | 有料アプリの大半は$1未満。**$10超は明確に「プロツール」枠** |
| 日本のタブレット市場における iPad シェア | **75.64%**（Samsung 2.49%） | 「iPad優先」戦略は日本市場で特に正当性が高い |
| iPad 世界タブレットシェア（2026 Q1） | 約40〜45% | iPad優先でも世界市場の約4割を取り逃さない |
| iOS プロダクトページ→インストール CVR（US） | 約25〜27%（30%超で優秀） | ただしこれは**無料アプリ込み**の値。有料はこれを大きく下回る |
| iOS 検索インプレッション→インストール率 | 約3.6〜3.8% | ASOの上限を規定する |
| 評価3.5未満のアプリ | キーワード可視性が急落する | **3.5は「検索から消え始める」臨界点**。競合が弱っている証拠として使える |
| インディーiOSアプリの収益中央値 | **月$500未満**（RevenueCat 2025） | 期待値の基準線 |
| 月$1,000に2年以内に到達しないアプリ | 81% | |
| 月$10K MRR 到達 | 4.6%（上位5%が$10K、上位1%が$50K+） | |
| App Store Small Business Program | 年商$100万未満なら手数料 **15%** | 買い切りにも適用される。**個人開発では実質85%が入る** |

> 注: 「評価3.5前後のアプリを狙う」という依頼者の着眼点は、上記の
> 「3.5未満で可視性が急落する」という事実と整合的である。3.5前後の競合は
> **すでにASO上のハンデを負っており、4.5以上を出せれば検索順位を奪える。**

---

## 2. 候補カテゴリの探索

「買い切りで存在するが評価が伸びていない」「サーバー不要が自然」「iPad優先が自然」
「個人が実装可能」の4条件を同時に満たすカテゴリを洗い出した。

### 2.1 音楽練習用オーディオプレイヤー（スロー再生 / ABループ / ピッチシフト）★第1候補

**市場構造**

| アプリ | 課金 | 評価（二次情報） | 観測された問題 |
|---|---|---|---|
| Amazing Slow Downer (Roni Music) | 買い切り | **約4.0** / 25万DL超 | UIが古い。**サポートが非常に遅く「3日以上返信がない／返ってこない」**という声。Lite版は約2.7と低評価で入口が悪い |
| Amazing Slow Downer Lite | 無料 | **約2.7** | 「音源の最初の1/4しか再生できない」制限への不満が集中 |
| Anytune | 買い切り+Pro | — | **Split View 非対応**（iPadユーザーの明確な不満）。ループ品質自体の評価は高い |
| Capo (SuperMegaUltraGroovy) | 買い切り/サブスク | **約4.7** | Mac中心。beat detection / snap region の精度が悪く「かえって使いにくい」。サブスク有効でも60秒プレビューしか再生できないバグ報告 |
| Riffstation | — | — | **提供終了**（市場から退出済み） |

**評価**
- 最強の Capo でも4.7だが Mac 中心、iPad の主戦場では Amazing Slow Downer（4.0、UI旧世代）と Anytune が空いている。
- **サーバー不要が構造的に必然**: Spotify は2022年9月1日以降サードパーティへのストリーム提供を停止し、
  Apple Music も「ピッチ変更」「EQ」が使えない。つまり**この分野は法的・技術的にローカルファイル前提**であり、
  「サーバーを持たない」という依頼者の要件が制約ではなく**正解**になる稀有な領域。
- 支払い意思: 楽器演奏者・ダンサー・語学学習者は道具に金を払う層。¥2,000〜3,500の買い切りが通る。
- 実装: `AVAudioEngine` + `AVAudioUnitTimePitch` で中核機能が成立。難所は「波形表示」「ABループの
  サンプル精度」「起動から音が鳴るまでの速さ」だが、いずれも個人開発の射程内。

**残る不安**: 市場が小さい（ニッチ）。ただし**逆に言えば大手が入ってこない**。

---

### 2.2 スポーツ動作分析（コマ送り・スロー・並列比較・描画）★第2候補

**市場構造 — ここは「市場の空白」が歴史的に発生している**

| 出来事 | 時期 | 影響 |
|---|---|---|
| Ubersense（無料）→ Hudl が買収し Hudl Technique に | 2014 | 無料のまま普及、コーチ界隈の標準に |
| Hudl が Technique を OnForm（Ubersense創業者の新会社）に売却 | 2021/05 | |
| Technique アプリ提供終了、動画移行期限は2021年10月で締切 | 2021夏〜秋 | **移行し損ねたコーチは数年分のクリップを失った** |
| TechSmith が **Coach's Eye を完全終了** | 2022/09 | 後継なし。TechSmithはこの分野から撤退 |
| OnForm 有料化 | 以降 | 「月$5」「10本以上共有するには月$30のcollection設定料」→ **"money grab" と批判** |

**現在の競合**

| アプリ | 課金 | 問題 |
|---|---|---|
| Technique by OnForm | サブスク | 約4.5（1,134件）。ただし「Libraryから録画開始する導線が不自然」「ゴルフ特化に見えるレイアウトで余白が無駄」「**コマ送りのフライホイールが指が離れると解除される＝Hudl比で明確な劣化**」 |
| VisualEyes | 2GB無料＋有料 | クラウド前提 |
| Coachly / SeamsUp | **完全無料** | クラウド前提 |
| myDartfish Express | サブスク | クラウド前提 |
| **AIスマートコーチ（ソフトバンク）** | **完全無料** | 日本の学校スポーツ向け。筑波大と産学連携、23競技・2,100本以上の手本動画、AI骨格解析。**日本市場では最大の脅威** |

**追い風（日本）**
- 2026年度（令和8年度）から部活動改革の「**改革実行期間**」開始。休日の部活は原則すべて地域展開。
- 2026年度予算案57億円＋2025年度補正82億円 ＝ **実質139億円**。
- 現状、地域展開に着手済みは 33.0% の市区町村。自治体の最大課題は「**指導者確保**」
  → 経験の浅い外部指導者が増える ＝ 「見せて教える」道具の需要増。

**この候補の決定的な弱点**
> 主要競合が **無料**（Coachly、AIスマートコーチ、VisualEyes無料枠）。
> 「買い切り有料」で戦うには、無料勢が構造的に提供できない価値が必要。
> それが「**完全オフライン・アカウント不要・撮影データが端末外に一切出ない**」である。
> 日本の学校現場では未成年の映像の外部送信が調達上のブロッカーになりやすく、
> ここは実際に刺さる差別化になり得る。ただし**「刺さる」と「金を払う」の間には距離がある**。

---

### 2.3 オフライン・テレプロンプター ★第3候補

| アプリ | 課金 | 評価 | 問題 |
|---|---|---|---|
| Teleprompter Pro | 買い切りIAP＋サブスク | **約4.75 / 15万件超** | 圧倒的王者。ただし「**買い切りで買ったのに、アップデートでミラー反転がサブスク限定にされた**」という強い不満 |
| PromptSmart Pro | $29 買い切り | — | 「$29払ったのにクラウド同期とファイルアップロードは追加課金」。**1行スクロールして固まる／そもそも動かない**、リセットも効かず |
| Teleprompter (Mac/iPad連携) | — | — | Mac側から速度操作するとiPad側のスクロールが飛ぶ。**サポートが半年無反応** |
| Parrot Teleprompter | — | — | 「動いている時は最高だが、動かない時は本当に狂わせる」 |

**評価**: 「買い切りの後出しサブスク化」への怒りが観測できる、依頼者の狙いに最も忠実な領域。
iPad をプロンプターにする用途は本質的にiPad優先。実装も容易（テキストスクロール＋ミラー＋
カメラオーバーレイ録画）。
**弱点**: 4.75・15万件の王者が居座っており、ASOで正面から勝つのは難しい。

---

### 2.4 その他検討したが優先度を下げたもの

| カテゴリ | 代表 | 下げた理由 |
|---|---|---|
| PDF閲覧・注釈・ファイル管理 | GoodReader | 「買い切りアプリなのに同じ機能を年額サブスクで要求し始めた」「v5で従来機能を得るにはPro課金」「UIが酷く、カスタマイズ不能」「開発曲線から脱落した」——**問題の質は理想的**。だが PDF Expert / Documents 等の資本のある競合が濃く、実装量も最大。**第4候補として保留** |
| オフライン現場点検・チェックリスト（B2B） | — | 「サーバー不要」の必然性は最高、単価も¥5,000〜取れる。だが**既存の3.5点アプリを置き換える**という依頼の枠から外れ、発見可能性（ASO）が極端に低い |
| 楽譜ビューア / セットリスト | forScore | 評価4.7で盤石。付け入る隙が小さい |
| 手書きノート | GoodNotes 等 | 規模的に個人開発の射程外 |
| スキャナ | — | レッドオーシャン |

---

## 3. 候補スコアリング

各項目 5点満点。重みは事業判断上の重要度。

| 評価軸 | 重み | ①音楽練習 | ②動作分析 | ③プロンプター | ④PDF/GoodReader系 |
|---|---|---|---|---|---|
| 既存買い切り競合が実際に弱っている | ×3 | 4 | 4 | 4 | **5** |
| サーバー不要が「制約」でなく「必然」 | ×3 | **5** | 4 | **5** | 3 |
| 個人が高品質に実装できる | ×3 | 4 | 3 | **5** | 2 |
| 無料競合の圧力が弱い（＝金を取れる） | ×3 | **5** | **1** | 3 | 2 |
| iPad優先が自然 | ×2 | 4 | **5** | **5** | 4 |
| ASOでの発見可能性 | ×2 | 4 | 4 | 3 | 3 |
| Android移植の容易さ | ×1 | 3 | 2 | **5** | 2 |
| **加重合計（85点満点）** | | **✅ 69** | 52 | **✅ 68** | 50 |

### 結論

- **① 音楽練習用オーディオプレイヤー（69）** と **③ テレプロンプター（68）** が同格の首位。
- ②動作分析は「市場の空白」と「2026年度の政策追い風」という物語は最も魅力的だが、
  **無料競合の壁（配点1点）で決定的に沈む**。買い切りで戦う土俵ではない。
- ④は問題の質が最高（配点5点）だが、実装量と競合資本で沈む。

### ①と③の使い分け提案

| | ① 音楽練習 | ③ テレプロンプター |
|---|---|---|
| 性格 | 市場は小さいが**大手が来ない安全地帯** | 市場は大きいが**強豪1社が支配** |
| 勝ち筋 | Amazing Slow Downer の「古さ」を正面から殴る | 「買い切り・完全オフライン・アカウント不要」で王者のサブスク化に怒った層を拾う |
| 想定単価 | ¥2,500〜3,500 | ¥1,800〜2,500 |
| リスク | 天井が低い | 王者に価格・機能で潰されうる |

**推奨: ① を第1弾として出し、③ を第2弾に回す。**
理由は、③は「王者への不満の受け皿」であり**王者の挙動に運命を握られる**のに対し、
①は自力で1位を取りに行けるため。かつ①の音声処理基盤（AVAudioEngine / タイムストレッチ /
波形描画 / 区間ループ）は再利用性が高く、後続アプリの資産になる。

---

## 4. ①を選んだ場合の具体的な差別化仕様（案）

既存不満の裏返しとして設計する。

| 既存の不満 | 本アプリでの解 |
|---|---|
| Amazing Slow Downer のUIが旧世代 | SwiftUI で現行 iPadOS のデザインに完全準拠。Split View / Stage Manager / 外部ディスプレイ / ポインタ / キーボードショートカット / Apple Pencil を全対応 |
| Anytune が Split View 非対応 | **Split View / Slide Over を初期リリースから対応**（楽譜PDFやYouTubeを横に置いて練習するのが実使用） |
| Lite版が「最初の1/4しか再生できない」で心証を害す | 無料版は**機能制限ではなく曲数制限（3曲まで）**にする。全機能を体験させてから買い切りに誘導 |
| Capo の beat detection が不正確で邪魔 | 自動解析は**任意・オフ可能**。手動でのビート/小節グリッド調整を最優先で正確に |
| サポートが遅い | サーバーを持たないため障害対応が発生しない＝サポート帯域を全部レビュー返信に回せる |
| ストリーミング連携が死んでいる | 最初から**ローカルファイル・ファイルアプリ・iTunes同期・端末内音楽**のみを正面から扱う。期待値の裏切りを起こさない |

コア機能（v1.0）
1. 速度変更 10〜200%（ピッチ維持）／ピッチ変更 ±12半音（速度維持）
2. サンプル精度のABループ、ループ間に無音インターバル挿入、ループごとに段階的加速
3. 波形＋スペクトログラム表示、Apple Pencil / 指でのループ点ドラッグ
4. マーカー・セクション（イントロ/Aメロ…）管理、曲ごとの設定を永続化
5. EQ、モノラル化、左右チャンネル分離（耳コピ用）、簡易センター音源除去
6. メトロノーム重畳、カウントイン
7. 全データ端末内、任意で iCloud Drive（＝ユーザー自身のストレージ。**自前サーバーではない**）

---

## 5. 参考情報源

- [What Is a Good App Store Rating for a Mobile App in 2026? — Enterpret](https://www.enterpret.com/guides/what-is-a-good-app-store-rating-for-a-mobile-app-in-2026)
- [iOS Apple App Store Statistics and Trends 2026 — 42matters](https://42matters.com/ios-apple-app-store-statistics-and-trends)
- [App Pricing Benchmarks (2026) — Business of Apps](https://www.businessofapps.com/data/app-pricing/)
- [Average App Conversion Rate per Category — AppTweak](https://www.apptweak.com/en/aso-blog/average-app-conversion-rate-per-category)
- [App Store Conversion Rate Benchmarks (2026, by Category) — screenfast](https://screenfast.app/blog/app-store-conversion-rate-benchmarks-2026)
- [How to Monetize Your iOS App — Indie Guide (2026)](https://theswiftk.it.com/blog/how-to-monetize-ios-app-indie-developer)
- [Tablet market share by vendor 2026 — Statista](https://www.statista.com/statistics/276635/market-share-held-by-tablet-vendors/)
- [Amazing Slow Downer — App Store](https://apps.apple.com/us/app/amazing-slow-downer/id308998718)
- [Anytune 公式](https://de.anytune.us/)
- [Capo — App Store](https://apps.apple.com/us/app/capo-learn-music-by-ear/id887497388)
- [Looking for an Alternative to Coach's Eye? — Dartfish](https://www.dartfish.com/blog/looking-for-an-alternative-to-coachs-eye/)
- [What Happened to Hudl Technique (and What to Use Instead) — VisualEyes](https://www.visualeyesapp.com/blog/hudl-technique-replacement)
- [OnForm Acquires The Hudl Technique Application From Hudl](https://onform.com/blog/onform-acquires-hudl-technique/)
- [Technique by OnForm — AppFollow](https://appfollow.io/ios/technique-by-onform/470428362)
- [Teleprompter Pro — App Store](https://apps.apple.com/us/app/teleprompter-pro/id941070561)
- [PromptSmart Pro — App Store](https://apps.apple.com/us/app/promptsmart-pro-teleprompter/id894811756)
- [GoodReader PDF Editor & Viewer 否定的レビュー — appsupports](https://appsupports.co/777310222/goodreader-pdf-editor-viewer/negative-reviews)
- [部活動改革ポータルサイト — スポーツ庁](https://www.mext.go.jp/sports/b_menu/sports/mcatetop01/list/1372413_00003.htm)
- [運動部活動と部活動の地域展開・地域移行の現状 — 笹川スポーツ財団](https://www.ssf.or.jp/knowledge/club_activities.html)
- [AIスマートコーチ — ソフトバンク](https://www.softbank.jp/mobile/service/ai_smartcoach/)
