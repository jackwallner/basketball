#!/usr/bin/env python3
"""Validate Google Play listing copy under android/play-assets/metadata/android.

Checks every locale folder for Play's limits (title 30, short 80, full 4000),
the house rules (no em dashes, no prices, no Apple wording, no promo words in
the title), the brand in the title, the Google Play billing paragraph, the
policy links, the NBA non-affiliation line, and that every non-English
description says the app is in English. Also checks the folder set is exactly
the 50 target locales and that en-US matches .play-live-listing.json when that
file is present. Exit 1 on any failure.

Usage: scripts/validate-play-listing.py [--root DIR]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "android/play-assets/metadata/android"
LIVE = REPO / ".play-live-listing.json"
LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
# Play language codes accepted by the Publishing API (fastlane supply list).
PLAY_LANGS = set(
    "af am ar az-AZ be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IN "
    "en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil fr-CA fr-FR gl-ES "
    "hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP ka-GE km-KH kn-IN ko-KR ky-KG "
    "lo-LA lt lv mk-MK ml-IN mn-MN mr-IN ms ms-MY my-MM ne-NP nl-NL no-NO pl-PL "
    "pt-BR pt-PT rm ro ru-RU si-LK sk sl sr sv-SE sw ta-IN te-IN th tr-TR uk vi "
    "zh-CN zh-HK zh-TW zu".split()
)
# The 50 locales this listing ships in (same set as Sober).
TARGET = set(
    "en-US en-GB en-AU en-CA en-IN de-DE fr-FR fr-CA es-ES es-419 es-US pt-BR pt-PT "
    "it-IT nl-NL sv-SE no-NO da-DK fi-FI pl-PL cs-CZ sk sl hr hu-HU ro el-GR tr-TR "
    "ru-RU uk ar iw-IL hi-IN bn-BD mr-IN ta-IN te-IN kn-IN ml-IN id ms ms-MY th vi "
    "ja-JP ko-KR zh-CN zh-TW zh-HK ca".split()
)
# The phrase each non-English description uses to say the app is in English.
IN_ENGLISH = {
    "de": "auf Englisch", "fr": "en anglais", "es": "en inglés", "pt": "em inglês",
    "it": "in inglese", "nl": "in het Engels", "sv": "på engelska", "no": "på engelsk",
    "da": "på engelsk", "fi": "englanninkielinen", "pl": "w języku angielskim",
    "cs": "v angličtině", "sk": "v angličtine", "sl": "v angleščini",
    "hr": "na engleskom", "hu": "angol nyelvű", "ro": "în limba engleză",
    "el": "στα αγγλικά", "tr": "İngilizcedir", "ru": "на английском",
    "uk": "англійською", "ar": "باللغة الإنجليزية", "iw": "באנגלית",
    "hi": "अंग्रेज़ी में", "bn": "ইংরেজিতে", "mr": "इंग्रजीमध्ये", "ta": "ஆங்கிலத்தில்",
    "te": "ఇంగ్లీష్‌లో", "kn": "ಇಂಗ್ಲಿಷ್‌ನಲ್ಲಿದೆ", "ml": "ഇംഗ്ലീഷിലാണ്",
    "id": "berbahasa Inggris", "ms": "bahasa Inggeris", "th": "ภาษาอังกฤษ",
    "vi": "tiếng Anh", "ja": "英語", "ko": "영어", "zh": "英文", "ca": "en anglès",
}
TITLE_BANNED = re.compile(r"\b(free|best|top|#1|new|sale)\b", re.I)
PRICE = re.compile(r"[$€£¥₹]\s?\d|\d[.,]\d\d\s?(?:€|zł|kr|lei|Kč|₺|₽|₴)")
APPLE = re.compile(r"\b(?:Apple|App Store|iPhone|iPad|iCloud)\b", re.I)
MEDICAL = re.compile(r"\b(cure|treat|diagnos)\w*", re.I)
URL_OK = re.compile(r"https://jackwallner\.github\.io/\S+")
POLICY_URLS = (
    "https://jackwallner.github.io/basketball/android-privacy.html",
    "https://jackwallner.github.io/basketball/android-terms.html",
)


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def check(locale_dir: Path) -> list[str]:
    errs: list[str] = []
    loc = locale_dir.name
    if loc not in PLAY_LANGS:
        errs.append(f"unknown Play language code {loc}")
    for name, limit in LIMITS.items():
        p = locale_dir / name
        if not p.exists():
            errs.append(f"missing {name}")
            continue
        text = read(p)
        n = len(text)
        if n == 0 or n > limit:
            errs.append(f"{name} {n}/{limit}")
        if "\u2014" in text:
            errs.append(f"{name} has an em dash")
        if re.search("[­​﻿]", text):
            errs.append(f"{name} has an invisible character")
        if PRICE.search(text):
            errs.append(f"{name} looks like it has a price: {PRICE.search(text).group(0)!r}")
        bare = URL_OK.sub("", text)
        if APPLE.search(bare):
            errs.append(f"{name} mentions Apple wording: {APPLE.search(bare).group(0)!r}")
        if MEDICAL.search(bare):
            errs.append(f"{name} has a medical claim word: {MEDICAL.search(bare).group(0)!r}")
        if name != "full_description.txt" and "\n" in text:
            errs.append(f"{name} spans lines")
    title = read(locale_dir / "title.txt")
    if TITLE_BANNED.search(title):
        errs.append(f"title has a promo word: {title!r}")
    if "StatScout" not in title:
        errs.append("title lacks the StatScout brand")
    full = read(locale_dir / "full_description.txt")
    if "Google Play" not in full:
        errs.append("full description lacks the Google Play billing paragraph")
    for url in POLICY_URLS:
        if url not in full:
            errs.append(f"full description lacks {url}")
    if "National Basketball Association" not in full or "NBPA" not in full:
        errs.append("full description lacks the NBA non-affiliation line")
    lang = loc.split("-")[0]
    if lang != "en":
        phrase = IN_ENGLISH.get(lang)
        if phrase is None:
            errs.append(f"no app-is-in-English phrase defined for {lang}")
        elif phrase not in full:
            errs.append(f"full description does not say the app is in English ({phrase!r})")
    return errs


def check_live(root: Path) -> list[str]:
    """en-US must equal the live listing exactly, when the live dump is present."""
    if not LIVE.exists():
        return []
    fields = {"title": "title.txt", "shortDescription": "short_description.txt",
              "fullDescription": "full_description.txt"}
    errs: list[str] = []
    for listing in json.loads(LIVE.read_text(encoding="utf-8")).get("listings", []):
        d = root / listing["language"]
        for key, name in fields.items():
            if read(d / name) != listing.get(key, "").strip():
                errs.append(f"{listing['language']}/{name} differs from the live listing")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    bad = 0
    dirs = sorted(d for d in args.root.iterdir() if d.is_dir())
    for d in dirs:
        errs = check(d)
        t, s, f = (read(d / n) for n in LIMITS)
        status = "OK " if not errs else "BAD"
        print(f"{status} {d.name:7} t{len(t):>3} s{len(s):>3} f{len(f):>5}  {t}")
        for e in errs:
            print(f"      - {e}")
        bad += bool(errs)
    names = {d.name for d in dirs}
    extra = [f"missing target locale {x}" for x in sorted(TARGET - names)]
    extra += [f"unexpected locale {x}" for x in sorted(names - TARGET)]
    extra += check_live(args.root)
    for e in extra:
        print(f"BAD {e}")
    print(f"\n{len(dirs)} locales, {bad} with problems, {len(extra)} set/live problems")
    return 1 if bad or extra else 0


if __name__ == "__main__":
    sys.exit(main())
