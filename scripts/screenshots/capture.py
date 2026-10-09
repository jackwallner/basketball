import subprocess, sys, time
udid, app, out = sys.argv[1:4]
BID = "com.jackwallner.basketball"
BASE = ["-ScreenshotData", "-ScreenshotSeasonStatus", "published", "-hasCompletedOnboarding", "YES",
        "-stats.qualifier", "All Players", "-ResetUITestState"]
ENV = {"SIMCTL_CHILD_FORCE_PRO": "1", "SIMCTL_CHILD_STATSCOUT_FORCE_PRO": "1", "SIMCTL_CHILD_SCREENSHOT_MODE": "1"}
FLOWS = [
    ("01_leaders", ["-StartTab", "stats", "-stats.board", "advanced"], 30),
    ("02_player_profile", ["-StartTab", "stats", "-stats.board", "advanced", "-ScreenshotRoute", "profile"], 30),
    ("03_trends", ["-StartTab", "trends"], 10),
    ("04_player_compare", ["-StartTab", "stats", "-ScreenshotRoute", "compare"], 30),
    ("05_team_profile", ["-StartTab", "teams"], 10),
    ("06_year_compare", ["-StartTab", "stats", "-ScreenshotRoute", "yearCompare"], 30),
    ("07_standard_leaders", ["-StartTab", "stats", "-stats.board", "standard"], 10),
    ("08_games", ["-StartTab", "games"], 10),
]
only = set(sys.argv[4:])
import os
env = dict(os.environ, **ENV)
class _R: returncode = "timeout"
def run(cmd, t=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=t, env=env)
    except subprocess.TimeoutExpired:
        print("  timeout:", " ".join(cmd[2:4]), flush=True)
        return _R()
for name, args, wait in FLOWS:
    if only and name not in only: continue
    run(["xcrun", "simctl", "uninstall", udid, BID], 90)
    run(["xcrun", "simctl", "install", udid, app], 120)
    r = run(["xcrun", "simctl", "launch", udid, BID, *BASE, *args], 90)
    time.sleep(wait)
    run(["xcrun", "simctl", "io", udid, "screenshot", f"{out}/{name}.png"], 60)
    print(name, "launch rc", r.returncode, flush=True)
    run(["xcrun", "simctl", "terminate", udid, BID], 60)
