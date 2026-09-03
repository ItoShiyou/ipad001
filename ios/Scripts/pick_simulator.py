#!/usr/bin/env python3
"""利用可能な iOS シミュレータを1つ選び、その UDID を出力する。

CI ランナーのイメージによって用意されているシミュレータは変わる。
デバイス名を決め打ちすると、ランナー更新のたびにジョブが壊れるため、
実行時に「あるものから選ぶ」。iPad を優先するが、コンパイル検証が目的なので
iPad が無ければ iPhone でも構わない。
"""

import json
import subprocess
import sys


def available_devices() -> list[tuple[str, str]]:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, check=True,
    ).stdout
    devices = json.loads(raw)["devices"]
    result = []
    for runtime, entries in devices.items():
        if "iOS" not in runtime:
            continue
        for device in entries:
            if device.get("isAvailable"):
                result.append((device["name"], device["udid"]))
    return result


def main() -> int:
    devices = available_devices()
    if not devices:
        print("利用可能な iOS シミュレータが見つかりません", file=sys.stderr)
        return 1

    for name, udid in devices:
        if "iPad" in name:
            print(udid)
            print(f"選択: {name} ({udid})", file=sys.stderr)
            return 0

    name, udid = devices[0]
    print(udid)
    print(f"iPad が無いため代替を選択: {name} ({udid})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
