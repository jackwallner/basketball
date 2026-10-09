import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch


with patch.dict(os.environ, {
    "SUPABASE_URL": "https://example.invalid",
    "SUPABASE_ANON_KEY": "test-only",
    "STATCAST_SEASON": "2027",
}):
    spec = importlib.util.spec_from_file_location(
        "export_historical", Path(__file__).parents[1] / "export_historical.py"
    )
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)


class ExportCoverageTests(unittest.TestCase):
    def rows(self, season: int) -> list[dict]:
        return [
            {
                "id": index, "season": season, "season_type": "REG",
                "team": "SEA" if index < 10 else "DEN",
                "player_type": ["g", "f", "c"][index % 3],
                "metrics": [{"label": "Pts/100"}, {"label": "TS%"}, {"label": "USG%"}],
            }
            for index in range(20)
        ]

    def test_opening_night_can_ship_as_current_fallback(self) -> None:
        exporter.validate_export(self.rows(2027), {2027}, require_rate_metrics=True)

    def test_two_team_historical_season_is_rejected(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Incomplete 2026"):
            exporter.validate_export(self.rows(2026), {2026}, require_rate_metrics=False)

    def test_one_sided_current_game_is_rejected(self) -> None:
        rows = self.rows(2027)
        for row in rows:
            row["team"] = "SEA"
        with self.assertRaisesRegex(RuntimeError, "Incomplete current season"):
            exporter.validate_export(rows, {2027}, require_rate_metrics=True)

    def test_twenty_nine_club_seasons_are_valid_before_2005(self) -> None:
        rows = [
            {"id": i, "season": 2003, "season_type": "REG", "team": f"T{i % 29}",
             "player_type": ["g", "f", "c"][i % 3], "metrics": [{"label": "Pts/100"}]}
            for i in range(60)
        ]
        exporter.validate_export(rows, {2003}, require_rate_metrics=False)

    def test_plist_round_trips_with_native_dates_and_no_nulls(self) -> None:
        import plistlib, tempfile, datetime as dt
        rows = [{"id": 1, "season": 2026, "updated_at": "2026-10-08T21:43:06.835518+00:00",
                 "image_url": None, "metrics": [{"label": "TS%", "value": "61.2%", "percentile": 88}]}]
        with tempfile.TemporaryDirectory() as folder:
            path = f"{folder}/x.plist"
            exporter.write_plist(rows, path)
            [back] = plistlib.load(open(path, "rb"))
        self.assertIsInstance(back["updated_at"], dt.datetime)
        self.assertNotIn("image_url", back)
        self.assertEqual(back["metrics"][0]["percentile"], 88)

    def test_historical_archive_is_written_one_plist_per_season(self) -> None:
        import plistlib, tempfile
        rows = self.rows(2025) + self.rows(2026) + [dict(self.rows(0)[0], season=0)]
        here = os.getcwd()
        with tempfile.TemporaryDirectory() as folder:
            os.chdir(folder)
            try:
                os.makedirs("StatScout/Data")
                Path("StatScout/Data/players-historical.plist").write_bytes(b"stale")
                paths = exporter.write_per_season("players-historical", rows)
                self.assertEqual(
                    sorted(paths),
                    [f"StatScout/Data/players-historical-{season}.plist" for season in (0, 2025, 2026)],
                )
                self.assertFalse(Path("StatScout/Data/players-historical.plist").exists())
                counts = {p: len(plistlib.load(open(p, "rb"))) for p in paths}
                self.assertEqual(sorted(counts.values()), [1, 20, 20])
            finally:
                os.chdir(here)

    def test_duplicate_player_phase_cannot_ship(self) -> None:
        rows = self.rows(2027)
        with self.assertRaisesRegex(RuntimeError, "Duplicate"):
            exporter.validate_export(rows + [rows[0]], {2027}, require_rate_metrics=True)


if __name__ == "__main__":
    unittest.main()
