#!/usr/bin/env bash
# Visual QA tour: runs StatScoutTourUITests on a leased simulator and exports
# every screenshot attachment, numbered in tour order, into build/tour/.
#
# Usage:
#   scripts/tour.sh <simulator-udid> [<test-name> ...]
#
# Builds once, then runs each test on its own with its own time cap, so one
# stalled test costs only its own frames. Pass test names such as
# testT03StatsAdvanced to re-run sections; their frames replace that section's
# files and the rest are kept. Live data needs SUPABASE_URL and
# SUPABASE_ANON_KEY (source ~/.basketball_credentials first).
set -uo pipefail

UDID="${1:?usage: tour.sh <simulator-udid> [<test-name> ...]}"
shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/tour"
DERIVED="$ROOT/build/DerivedData-ui"
TEST_FILE="$ROOT/StatScoutUITests/StatScoutTourUITests.swift"
STATUS=0

mkdir -p "$OUT"
cd "$ROOT"

if [[ $# -gt 0 ]]; then
    TESTS=("$@")
else
    TESTS=($(grep -oE 'func (testT[0-9]+[A-Za-z]+)' "$TEST_FILE" | awk '{print $2}'))
fi

xcodebuild build-for-testing \
    -project StatScout.xcodeproj \
    -scheme StatScoutUITests \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" \
    SUPABASE_URL="${SUPABASE_URL:-}" \
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
    -quiet || exit 1

for TEST in "${TESTS[@]}"; do
    RESULT="$ROOT/build/tour-$TEST-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
    STAGE="$(mktemp -d)"
    START=$(date +%s)
    # A hung element query can stall a test for its whole timeout; cap it so
    # the frames captured before the stall are still exported.
    perl -e 'alarm 900; exec @ARGV' xcodebuild test-without-building \
        -project StatScout.xcodeproj \
        -scheme StatScoutUITests \
        -destination "id=$UDID" \
        -derivedDataPath "$DERIVED" \
        -resultBundlePath "$RESULT" \
        -only-testing:"StatScoutUITests/StatScoutTourUITests/$TEST" \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 600 \
        > "$ROOT/build/tour-$TEST.log" 2>&1
    CODE=$?
    [[ $CODE -ne 0 ]] && STATUS=$CODE
    echo "$TEST exit=$CODE $(( $(date +%s) - START ))s"
    grep -E "error: -\[" "$ROOT/build/tour-$TEST.log" | sed -E 's/.*error: -\[[^ ]+ [^]]+\] : //' | head -8
    if [[ -f "$RESULT/Info.plist" ]]; then
        xcrun xcresulttool export attachments --path "$RESULT" --output-path "$STAGE" >/dev/null
        python3 - "$STAGE" "$OUT" <<'PY'
import json
import pathlib
import re
import shutil
import sys

stage = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
manifest_path = stage / "manifest.json"
if not manifest_path.exists():
    sys.exit(0)
copied = 0
cleared: set[str] = set()
for entry in json.loads(manifest_path.read_text()):
    for attachment in entry.get("attachments", []):
        source = stage / attachment.get("exportedFileName", "")
        stem = pathlib.Path(attachment.get("suggestedHumanReadableName", "")).stem
        match = re.match(r"^(\d\d)-(\d\d)_(.+?)(?:_\d+_[0-9A-F-]{36})?$", stem)
        if not source.exists() or source.suffix.lower() != ".png" or not match:
            continue
        section, step, name = match.groups()
        if section not in cleared:
            for old in out.glob(f"{section}-*.png"):
                old.unlink()
            cleared.add(section)
        shutil.copyfile(source, out / f"{section}-{step}_{name}.png")
        copied += 1
print(f"  {copied} frames")
PY
    fi
    rm -rf "$STAGE"
done
echo "tour screens in $OUT"
exit "$STATUS"
