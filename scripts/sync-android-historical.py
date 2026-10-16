#!/usr/bin/env python3
"""Write the Android copy of the bundled historical players.

Reads the per-season binary plists the iOS app bundles
(StatScout/Data/players-historical-<season>.plist, written by
scripts/export_historical.py) and writes one compact gzip JSON array per season
to android/app/src/main/assets/players-historical-<season>.bin. Season 0 is the
All Time rollup. Fields the app never reads (refresh and publish stamps, empty
games, per-metric ids) are dropped; the Kotlin decoder derives ids. Rerun after
every export_historical.py run.

The assets are named .bin, never .gz: the Android packager silently inflates a
.gz asset and drops the extension, so the app would find nothing to open.
"""
from __future__ import annotations

import datetime as dt
import gzip
import json
import pathlib
import plistlib
import re
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "StatScout" / "Data"
TARGET_DIR = ROOT / "android" / "app" / "src" / "main" / "assets"
PATTERN = re.compile(r"players-historical-(\d+)\.plist$")


def iso(value: Any) -> Any:
    if isinstance(value, dt.datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=dt.timezone.utc)
        return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return value


def compact(player: dict[str, Any]) -> dict[str, Any]:
    out = {k: iso(player[k]) for k in ("id", "name", "team", "position", "handedness", "updated_at") if k in player}
    for key in ("season", "season_type", "player_type", "source"):
        if player.get(key) is not None:
            out[key] = player[key]
    out["metrics"] = [
        {k: m[k] for k in ("label", "value", "category", "percentile", "qualified", "rankable") if m.get(k) is not None}
        for m in player.get("metrics", [])
    ]
    if player.get("standard_stats") is not None:
        out["standard_stats"] = [{"label": s["label"], "value": s["value"]} for s in player["standard_stats"]]
    if player.get("games"):
        out["games"] = [{k: iso(v) for k, v in g.items()} for g in player["games"]]
    return out


def main() -> None:
    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    for stale in TARGET_DIR.glob("players-historical*.bin"):
        stale.unlink()
    total_json = total_gz = rows_total = 0
    for source in sorted(SOURCE_DIR.glob("players-historical-*.plist")):
        season = int(PATTERN.search(source.name).group(1))
        players = plistlib.loads(source.read_bytes())
        rows = [compact(p) for p in players]
        payload = json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode()
        target = TARGET_DIR / f"players-historical-{season}.bin"
        with gzip.GzipFile(target, "wb", compresslevel=9, mtime=0) as fh:
            fh.write(payload)
        rows_total += len(rows)
        total_json += len(payload)
        total_gz += target.stat().st_size
    print(f"{rows_total} players, {total_json / 1e6:.1f} MB JSON, {total_gz / 1e6:.1f} MB gzip -> {TARGET_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
