#!/usr/bin/env python3
"""App Store の一次データを取得する。

このリポジトリの調査環境は egress ポリシーにより Apple のドメインへ到達できない
（CONNECT トンネルの段階で遮断され、ヘッドレスブラウザでも迂回できないことを実測で確認済み）。
docs/ 配下の星評価はすべて検索エンジン経由の二次情報であり、確定値ではない。
このスクリプトを **制限のないローカル環境で** 実行して一次データを取ること。

依存パッケージなし（Python 3.9+ の標準ライブラリのみ）。

--------------------------------------------------------------------------
使い方
--------------------------------------------------------------------------
  # 1. 発掘: 評価3.2〜3.8 の「買い切り有料アプリ」を横断的に探す ← 本命
  python3 tools/appstore_probe.py discover --country jp
  python3 tools/appstore_probe.py discover --country us --csv out.csv

  # 2. 検証: docs/ で言及した既存候補の現在値を確定させる
  python3 tools/appstore_probe.py check
  python3 tools/appstore_probe.py check --country jp --reviews 30

  # 3. 個別: ID や名前を指定して調べる
  python3 tools/appstore_probe.py check 308998718 777310222
  python3 tools/appstore_probe.py search "Piascore" "INKredible"

出力を丸ごと Claude に貼れば、そのまま再ランキングに使える。
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"

# docs/research.md と docs/verification.md で言及した検証対象。
CHECK_TARGETS: dict[str, str] = {
    "308998718": "Amazing Slow Downer",
    "310204778": "Amazing Slow Downer Lite",
    "415365180": "Anytune",
    "887497388": "Capo - Learn Music by Ear",
    "941070561": "Teleprompter Pro",
    "894811756": "PromptSmart Pro",
    "1010384663": "Parrot Teleprompter",
    "470428362": "Technique by OnForm (2021年で更新停止の疑い)",
    "1490334045": "OnForm: Video Analysis",
    "1040982427": "myDartfish Express",
    "777310222": "GoodReader PDF Editor & Viewer",
}

# ID が不確かな候補は名前で解決する。
CHECK_NAMES: list[str] = [
    "Piascore", "forScore", "INKredible", "Notability", "GoodNotes",
    "Noteshelf", "PDF Expert", "AnkiMobile Flashcards", "Gaia GPS",
    "Topo Maps+", "Guru Maps", "Money Pro", "SkySafari",
]

# discover 用の検索語。「ローカル完結が自然」「iPadが活きる」「支払い意思がある」
# 領域を広く舐める。増やすほど発見率は上がるが時間もかかる。
DISCOVER_TERMS: list[str] = [
    # 音楽
    "sheet music reader", "music practice slow down", "metronome", "guitar tuner",
    "楽譜", "耳コピ", "メトロノーム",
    # 手書き・文書
    "handwriting notes", "pdf annotation", "pdf editor", "document scanner",
    "手書きノート", "PDF 注釈",
    # 動画・撮影
    "teleprompter", "video analysis coach", "slow motion analysis",
    "フォーム分析", "テレプロンプター",
    # 地図・アウトドア
    "offline topo map", "gps track logger", "marine navigation",
    "登山 地図", "オフライン 地図",
    # 学習・記録
    "flashcards spaced repetition", "habit tracker", "practice log",
    "暗記カード", "学習記録",
    # 業務・現場
    "inspection checklist offline", "barcode inventory", "invoice maker",
    "点検 記録", "在庫管理",
    # 趣味・専門
    "astronomy star chart", "fishing log", "dive log", "model railroad",
    "アクアリウム 管理", "コレクション 管理",
    # 制作
    "pixel art editor", "stop motion animation", "audio recorder multitrack",
    "ドット絵", "コマ撮り",
]


def _get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def lookup(app_ids: list[str], country: str) -> list[dict]:
    """iTunes Lookup API。ID は一度に複数渡せる。"""
    qs = urllib.parse.urlencode({"id": ",".join(app_ids), "country": country})
    return _get_json(f"https://itunes.apple.com/lookup?{qs}").get("results") or []


def search(term: str, country: str, limit: int = 50) -> list[dict]:
    """iTunes Search API で名前・キーワードからアプリを引く。"""
    qs = urllib.parse.urlencode(
        {"term": term, "country": country, "entity": "software", "limit": limit}
    )
    return _get_json(f"https://itunes.apple.com/search?{qs}").get("results") or []


def reviews(app_id: str, country: str, limit: int) -> list[dict]:
    """RSS の customerreviews から新着レビューを取る（1ページ50件、最大10ページ）。"""
    out: list[dict] = []
    for page in range(1, 11):
        if len(out) >= limit:
            break
        url = (
            f"https://itunes.apple.com/{country}/rss/customerreviews/"
            f"page={page}/id={app_id}/sortBy=mostRecent/json"
        )
        try:
            feed = _get_json(url)
        except (urllib.error.HTTPError, urllib.error.URLError):
            break
        entries = feed.get("feed", {}).get("entry") or []
        if isinstance(entries, dict):
            entries = [entries]
        if not entries:
            break
        for e in entries:
            rating = e.get("im:rating", {}).get("label")
            if rating is None:  # 先頭にアプリ自身のメタ情報が混じることがある
                continue
            out.append({
                "rating": int(rating),
                "title": e.get("title", {}).get("label", ""),
                "body": e.get("content", {}).get("label", ""),
                "version": e.get("im:version", {}).get("label", ""),
            })
        time.sleep(0.4)
    return out[:limit]


def row(app: dict) -> dict:
    """Lookup / Search の生データから、判断に必要な列だけ抜き出す。"""
    devices = app.get("supportedDevices") or []
    return {
        "id": app.get("trackId"),
        "name": app.get("trackName"),
        "seller": app.get("sellerName"),
        "price": app.get("price"),
        "price_str": app.get("formattedPrice"),
        "rating": app.get("averageUserRating"),
        "ratings": app.get("userRatingCount"),
        "rating_cur": app.get("averageUserRatingForCurrentVersion"),
        "ratings_cur": app.get("userRatingCountForCurrentVersion"),
        "version": app.get("version"),
        "updated": str(app.get("currentVersionReleaseDate"))[:10],
        "released": str(app.get("releaseDate"))[:10],
        "genre": app.get("primaryGenreName"),
        "ipad": any(d.startswith("iPad") for d in devices),
        "url": app.get("trackViewUrl"),
    }


def fmt(r: dict) -> str:
    pad = "iPad対応" if r["ipad"] else "iPadなし"
    return (
        f"  {r['rating']}★ ({r['ratings']}件)  {r['price_str']:>10}  {pad}  "
        f"更新 {r['updated']}\n"
        f"      id={r['id']}  {r['name']}  [{r['seller']}]  <{r['genre']}>"
    )


# --------------------------------------------------------------------------
# サブコマンド
# --------------------------------------------------------------------------

def cmd_discover(args: argparse.Namespace) -> int:
    """有料 かつ 評価が指定バンド内 かつ レビュー件数が一定以上 のアプリを集める。"""
    lo, hi = args.band
    seen: dict[int, dict] = {}
    for i, term in enumerate(DISCOVER_TERMS, 1):
        try:
            hits = search(term, args.country, limit=args.limit)
        except Exception as exc:
            print(f"[{term}] 検索失敗: {exc}", file=sys.stderr)
            continue
        print(f"  ({i}/{len(DISCOVER_TERMS)}) {term}: {len(hits)}件", file=sys.stderr)
        for hit in hits:
            r = row(hit)
            if r["id"] in seen:
                continue
            if not r["ipad"] and args.ipad_only:
                continue
            if (r["price"] or 0) <= 0:          # 買い切り＝有料アプリのみ
                continue
            if (r["ratings"] or 0) < args.min_ratings:
                continue
            if r["rating"] is None or not (lo <= r["rating"] <= hi):
                continue
            r["found_by"] = term
            seen[r["id"]] = r
        time.sleep(0.3)

    found = sorted(seen.values(), key=lambda x: -(x["ratings"] or 0))
    print("\n" + "=" * 78)
    print(f"評価 {lo}〜{hi} / 有料 / レビュー{args.min_ratings}件以上"
          f"{' / iPad対応' if args.ipad_only else ''}  — {len(found)}件  (country={args.country})")
    print("=" * 78)
    for r in found:
        print(fmt(r))
        print(f"      ← 検索語: {r['found_by']}")
    if not found:
        print("  該当なし。--band を広げるか --min-ratings を下げること。")

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(found[0].keys()) if found else ["id"])
            w.writeheader()
            w.writerows(found)
        print(f"\nCSV: {args.csv}")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    ids = args.app_ids or list(CHECK_TARGETS)
    try:
        apps = lookup(ids, args.country)
    except Exception as exc:
        print(f"lookup 失敗: {exc}", file=sys.stderr)
        return 1

    got = {str(a.get("trackId")) for a in apps}
    for missing in [i for i in ids if i not in got]:
        print(f"[{CHECK_TARGETS.get(missing, missing)}] country={args.country} で見つからず",
              file=sys.stderr)

    for app in apps:
        r = row(app)
        print("=" * 78)
        print(f"{r['name']}  (id={r['id']}, country={args.country})")
        print(f"  開発元   : {r['seller']}")
        print(f"  価格     : {r['price_str']}")
        print(f"  総合評価 : {r['rating']}  ({r['ratings']} 件)")
        print(f"  現行版   : {r['rating_cur']}  ({r['ratings_cur']} 件)")
        print(f"  バージョン: {r['version']}   更新: {r['updated']}   初出: {r['released']}")
        print(f"  iPad対応 : {'あり' if r['ipad'] else 'なし'}")

        if args.reviews <= 0:
            continue
        revs = reviews(str(r["id"]), args.country, args.reviews)
        if not revs:
            print("  レビュー : 取得できず")
            continue
        hist = {n: sum(1 for x in revs if x["rating"] == n) for n in range(1, 6)}
        print(f"  新着{len(revs)}件: " + "  ".join(f"{n}★={hist[n]}" for n in range(5, 0, -1)))
        negatives = [x for x in revs if x["rating"] <= 3]
        print(f"\n  --- 否定的レビュー {len(negatives)}件 ---")
        for x in negatives:
            print(f"  [{x['rating']}★ v{x['version']}] {x['title']}")
            print(f"      {' '.join(x['body'].split())[:400]}")
        print()
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    for term in (args.terms or CHECK_NAMES):
        try:
            hits = search(term, args.country, limit=args.limit)
        except Exception as exc:
            print(f"[{term}] 検索失敗: {exc}", file=sys.stderr)
            continue
        print("=" * 78)
        print(f"検索語: {term}  (country={args.country})")
        if not hits:
            print("  ヒットなし")
        for hit in hits[:args.limit]:
            print(fmt(row(hit)))
        print()
        time.sleep(0.3)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--country", default="jp", help="ストアの国コード（既定: jp。米国は us）")
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("discover", help="評価が指定バンド内の有料アプリを横断的に発掘する")
    d.add_argument("--band", nargs=2, type=float, default=[3.2, 3.8],
                   metavar=("LO", "HI"), help="対象とする星評価の範囲（既定: 3.2 3.8）")
    d.add_argument("--min-ratings", type=int, default=200,
                   help="この件数未満のアプリは除外（既定: 200）")
    d.add_argument("--limit", type=int, default=50, help="検索語あたりの取得件数（最大200）")
    d.add_argument("--ipad-only", action="store_true", default=True,
                   help="iPad非対応のアプリを除外（既定: 有効）")
    d.add_argument("--any-device", dest="ipad_only", action="store_false",
                   help="iPad非対応も含める")
    d.add_argument("--csv", help="結果をCSVに書き出す")
    d.set_defaults(func=cmd_discover)

    c = sub.add_parser("check", help="既存候補の現在値とレビューを確定させる")
    c.add_argument("app_ids", nargs="*", help="track ID（省略時は CHECK_TARGETS 全件）")
    c.add_argument("--reviews", type=int, default=20, help="取得レビュー件数（0で取得しない）")
    c.set_defaults(func=cmd_check)

    s = sub.add_parser("search", help="名前からアプリとIDを解決する")
    s.add_argument("terms", nargs="*", help="検索語（省略時は CHECK_NAMES 全件）")
    s.add_argument("--limit", type=int, default=5, help="表示件数")
    s.set_defaults(func=cmd_search)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
