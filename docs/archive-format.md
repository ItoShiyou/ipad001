# `.scorestand` ライブラリ書庫フォーマット仕様 v1

このドキュメントは **FR-62（囲い込まない）** のために公開している。

このアプリはサーバーを持たないため、ユーザーのデータはユーザーの端末にしか無い。
だからこそ**取り出せることを保証する必要がある**。仕様を公開しておけば、
将来このアプリが更新されなくなっても、他のツールで中身を取り出せる。

---

## なぜ独自形式なのか

zip を使いたかったが、**iOS には公開された unzip API が無い**。
`NSFileCoordinator` の `.forUploading` オプションで zip を「作る」ことはできても、
「展開する」公開APIが存在しない。外部ライブラリを持ち込まない方針であるため、
展開側を自前で書ける最小限の形式を定義した。

形式が単純なので、**Python なら30行程度で読める**（末尾に参考実装あり）。

---

## バイト構造

すべて**リトルエンディアン**。単一ファイル。

| オフセット | サイズ | 内容 |
|---|---|---|
| 0 | 4 | マジックバイト `"SSTD"`（ASCII） |
| 4 | 4 | フォーマットバージョン `UInt32`（現行 = 1） |
| 8 | 8 | マニフェストJSONのバイト長 `N`（`UInt64`） |
| 16 | N | マニフェストJSON本体（UTF-8） |
| 16+N | — | ファイル実体を連結。各実体の位置はマニフェストが持つ |

ファイル実体の位置は `ArchiveFile.offset` が**書庫先頭からの絶対バイト位置**で示す。
したがって、マニフェストだけ読めば任意のファイルへ直接シークできる。

---

## マニフェスト（JSON）

```jsonc
{
  "version": 1,
  "exportedAt": "2026-09-03T12:00:00Z",
  "files": [
    { "id": "UUID", "originalName": "sonata.pdf", "offset": 1234, "size": 567890 }
  ],
  "scores": [
    {
      "title": "曲名",
      "composer": "作曲者",
      "ensemble": "編成",
      "tags": ["タグ"],
      "createdAt": "…",
      "lastPageIndex": 0,
      "tempoBPM": 120,              // 未設定なら null
      "timeSignature": "4/4",       // 未設定なら null
      "sources": [
        { "fileID": "UUID", "kind": "pdf", "pageCount": 12, "order": 0, "originalName": "sonata.pdf" }
      ],
      "pageSettings": [
        { "pageIndex": 0, "cropX": 0.05, "cropY": 0.05,
          "cropWidth": 0.9, "cropHeight": 0.9, "rotation": 0 }
      ],
      "annotations": [
        { "pageIndex": 0, "drawingData": "<Base64>" }
      ]
    }
  ],
  "setlists": [
    {
      "name": "セットリスト名",
      "createdAt": "…",
      "items": [ { "order": 0, "note": "メモ", "scoreIndex": 0 } ]
    }
  ]
}
```

### 補足

- `ArchiveSource.fileID` は `files[].id` を参照する。対応表を別に持たずに済ませている。
- `kind` は `"pdf"` または `"image"`。
- `cropX` などは**正規化座標（0〜1）**。用紙サイズに依存しない。
- `rotation` は 0 / 90 / 180 / 270。
- `drawingData` は PencilKit の `PKDrawing.dataRepresentation()`。
  JSON 上は Base64。**これだけは Apple の非公開形式**であり、
  他ツールでは注釈を再現できない可能性がある。楽譜PDF本体は完全に取り出せる。
- `setlists[].items[].scoreIndex` は `scores` 配列への添字。
  曲が失われている場合は `null`。

---

## 参考実装（Python）— 書庫からPDFを取り出す

```python
import json, struct, sys, pathlib

def extract(archive_path, out_dir):
    out = pathlib.Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with open(archive_path, "rb") as f:
        assert f.read(4) == b"SSTD", "ScoreStand の書庫ではありません"
        (version,) = struct.unpack("<I", f.read(4))
        (length,) = struct.unpack("<Q", f.read(8))
        manifest = json.loads(f.read(length).decode("utf-8"))

        print(f"version={version}  曲数={len(manifest['scores'])}")
        for entry in manifest["files"]:
            f.seek(entry["offset"])
            data = f.read(entry["size"])
            (out / entry["originalName"]).write_bytes(data)
            print("取り出し:", entry["originalName"])

if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
```

---

## 互換性の約束

- `version` を上げる変更を入れる場合も、**古い書庫は読めるようにする**。
- マジックバイトと先頭16バイトの構造は変更しない。
- フィールドの**追加**はするが、既存フィールドの意味は変えない。
