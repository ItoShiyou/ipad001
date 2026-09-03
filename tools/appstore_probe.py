#!/usr/bin/env python3
"""App Store の評価・レビューの一次データを取得する。

本リポジトリの調査は、実行環境の egress ポリシーにより Apple のドメインへ
直接アクセスできない状態で行われた。docs/research.md の星評価はすべて
検索エンジン経由の二次情報である。意思決定の前に、このスクリプトを
**制限のないローカル環境で** 実行して数値を確定させること。

使い方:
    python3 tools/appstore_probe.py                 # 既定の調査対象をまとめて取得
    python3 tools/appstore_probe.py 308998718       # ID指定
    python3 tools/appstore_probe.py --country jp 308998718
    python3 tools/appstore_probe.py --reviews 50 308998718
    python3 tools/appstore_probe.py --search           # ID不明のアプリを名前で解決
    python3 tools/appstore_probe.py --search --country jp

標準ライブラリのみ。依存パッケージなし。
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# 検証対象。ID が分かっているものは TARGETS、分からないものは SEARCH_NAMES に置く。
TARGETS: dict[str, str] = {
    # 音楽練習系
    "308998718": "Amazing Slow Downer",
    "310204778": "Amazing Slow Downer Lite",
    "415365180": "Anytune",
    "887497388": "Capo - Learn Music by Ear",
    # テレプロンプター系
    "941070561": "Teleprompter Pro",
    "894811756": "PromptSmart Pro",
    "1010384663": "Parrot Teleprompter",
    # スポーツ動画分析系
    "470428362": "Technique by OnForm (2021年で更新停止の疑い)",
    "1490334045": "OnForm: Video Analysis",
    "1040982427": "myDartfish Express",
    # PDF / 書類系
    "777310222": "GoodReader PDF Editor & Viewer",
}

# ID が不確かなものは名前で検索して解決する（--search で実行）。
SEARCH_NAMES: list[str] = [
    # 買い切り→サブスク移行の反発が観測された群
    "Notability",
    "GoodNotes",
    "Noteshelf",
    "PDF Expert",
    "Scanner Pro",
    # オフライン地図 / GPS
    "Gaia GPS",
    "Topo Maps+",
    "Guru Maps",
    "YAMAP",
    "ヤマレコ",
    # 暗記 / 学習
    "AnkiMobile Flashcards",
    # ローカル完結の家計簿
    "Money Pro",
    "MoneyWiz",
    # 天体
    "SkySafari",
]

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"


def _get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def lookup(app_id: str, country: str) -> dict | None:
    """iTunes Lookup API からアプリのメタデータを取得する。"""
    qs = urllib.parse.urlencode({"id": app_id, "country": country})
    data = _get_json(f"https://itunes.apple.com/lookup?{qs}")
    results = data.get("results") or []
    return results[0] if results else None


def reviews(app_id: str, country: str, limit: int) -> list[dict]:
    """RSS の customerreviews から新着レビューを取得する（1ページ50件、最大10ページ）。"""
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
        except urllib.error.HTTPError:
            break
        entries = feed.get("feed", {}).get("entry") or []
        if isinstance(entries, dict):
            entries = [entries]
        # 1件目はアプリ自身のメタデータであることがあるため im:rating の有無で判別する。
        for entry in entries:
            rating = entry.get("im:rating", {}).get("label")
            if rating is None:
                continue
            out.append(
                {
                    "rating": int(rating),
                    "title": entry.get("title", {}).get("label", ""),
                    "body": entry.get("content", {}).get("label", ""),
                    "version": entry.get("im:version", {}).get("label", ""),
                    "author": entry.get("author", {}).get("name", {}).get("label", ""),
                }
            )
        if not entries:
            break
        time.sleep(0.4)
    return out[:limit]


def search(term: str, country: str, limit: int = 5) -> list[dict]:
    """iTunes Search API で名前からアプリを解決する。"""
    qs = urllib.parse.urlencode(
        {"term": term, "country": country, "entity": "software", "limit": limit}
    )
    data = _get_json(f"https://itunes.apple.com/search?{qs}")
    return data.get("results") or []


def search_report(term: str, country: str) -> None:
    """名前で引いた候補を一覧表示する。ID の特定と星評価の粗い把握が目的。"""
    try:
        hits = search(term, country)
    except Exception as exc:
        print(f"[{term}] search 失敗: {exc}", file=sys.stderr)
        return
    if not hits:
        print(f"[{term}] country={country} でヒットなし", file=sys.stderr)
        return
    print("=" * 72)
    print(f"検索語: {term}  (country={country})")
    for hit in hits:
        print(
            f"  id={hit.get('trackId')}  {hit.get('trackName')}"
            f"  [{hit.get('sellerName')}]"
        )
        print(
            f"      {hit.get('formattedPrice')}   "
            f"評価 {hit.get('averageUserRating')} ({hit.get('userRatingCount')} 件)   "
            f"更新 {str(hit.get('currentVersionReleaseDate'))[:10]}"
        )


def report(app_id: str, country: str, review_limit: int) -> None:
    label = TARGETS.get(app_id, app_id)
    try:
        meta = lookup(app_id, country)
    except Exception as exc:  # ネットワーク由来の失敗は握りつぶさず表示する
        print(f"[{label}] lookup 失敗: {exc}", file=sys.stderr)
        return
    if meta is None:
        print(f"[{label}] country={country} では見つからなかった", file=sys.stderr)
        return

    print("=" * 72)
    print(f"{meta.get('trackName')}  (id={app_id}, country={country})")
    print(f"  開発元        : {meta.get('sellerName')}")
    print(f"  価格          : {meta.get('formattedPrice')}")
    print(f"  総合評価      : {meta.get('averageUserRating')}  ({meta.get('userRatingCount')} 件)")
    print(
        f"  現行版の評価  : {meta.get('averageUserRatingForCurrentVersion')}"
        f"  ({meta.get('userRatingCountForCurrentVersion')} 件)"
    )
    print(f"  最新バージョン: {meta.get('version')}   更新日: {meta.get('currentVersionReleaseDate')}")
    print(f"  初回リリース  : {meta.get('releaseDate')}")
    print(f"  対応デバイス  : {', '.join(sorted({d[:4] for d in meta.get('supportedDevices', [])}))}")

    if review_limit <= 0:
        return

    revs = reviews(app_id, country, review_limit)
    if not revs:
        print("  レビュー      : 取得できなかった")
        return

    hist = {n: 0 for n in range(1, 6)}
    for r in revs:
        hist[r["rating"]] += 1
    print(f"  新着{len(revs)}件の分布: " + "  ".join(f"{n}★={hist[n]}" for n in range(5, 0, -1)))

    negatives = [r for r in revs if r["rating"] <= 3]
    print(f"\n  --- 否定的レビュー（{len(negatives)}件 / 3★以下） ---")
    for r in negatives:
        body = " ".join(r["body"].split())
        print(f"  [{r['rating']}★ v{r['version']}] {r['title']}")
        print(f"      {body[:400]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app_ids", nargs="*", help="App Store の track ID（省略時は既定の調査対象すべて）")
    parser.add_argument("--country", default="us", help="ストアの国コード（既定: us。日本は jp）")
    parser.add_argument("--reviews", type=int, default=20, help="取得するレビュー件数（0で取得しない）")
    parser.add_argument(
        "--search",
        action="store_true",
        help="SEARCH_NAMES の各アプリを名前で検索し、ID と星評価を一覧する",
    )
    args = parser.parse_args()

    if args.search:
        for term in SEARCH_NAMES:
            search_report(term, args.country)
            print()
        return 0

    app_ids = args.app_ids or list(TARGETS)
    for app_id in app_ids:
        report(app_id, args.country, args.reviews)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
