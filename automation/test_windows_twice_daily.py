"""Network-free tests for Windows 06/18 production and 09/21 YouTube schedule."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import windows_twice_daily as windows
from daily_core import SetupError, next_publish_at, youtube_status


BASE = {
    "enabled": True,
    "timezone": "Asia/Seoul",
    "run_time": "09:00",     # Legacy values must be overridden per slot.
    "publish_mode": "scheduled",
    "publish_time": "18:00",
    "licensed_tiktok_creators": ["my_licensed_account"],
    "rights_attested": True,
    "youtube_channel_id": "UC" + "a" * 22,
    "min_duration_seconds": 5,
    "max_duration_seconds": 60,
    "max_candidates": 8,
}
MORNING = datetime(2026, 11, 11, 21, 1, tzinfo=timezone.utc)  # KST Nov 12 06:01
EVENING = datetime(2026, 11, 12, 9, 1, tzinfo=timezone.utc)  # KST Nov 12 18:01


class WindowsTwoSlotTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        (self.home / "daily_config.json").write_text(
            json.dumps(BASE), encoding="utf-8"
        )
        (self.home / "server.env").write_text(
            "".join(f"{key}=placeholder-credential\n" for key in windows.SECRETS),
            encoding="utf-8",
        )

    def put_state(self, slot, value):
        path = windows.state_path(self.home, slot)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def test_publish_slots_are_exactly_twelve_hours_apart(self):
        self.assertEqual(
            windows.remaining_margin(MORNING, "morning"),
            timedelta(hours=2, minutes=59),
        )
        self.assertEqual(
            windows.remaining_margin(EVENING, "evening"),
            timedelta(hours=2, minutes=59),
        )
        morning = {**BASE, **windows.SLOTS["morning"],
                   "same_day_publish_required": True}
        evening = {**BASE, **windows.SLOTS["evening"],
                   "same_day_publish_required": True}
        status1 = youtube_status(morning, MORNING)
        status2 = youtube_status(evening, EVENING)
        self.assertEqual(status1["privacyStatus"], "private")
        self.assertEqual(status2["privacyStatus"], "private")
        self.assertEqual(status1["publishAt"], "2026-11-12T00:00:00Z")
        self.assertEqual(status2["publishAt"], "2026-11-12T12:00:00Z")

    def test_never_roll_a_missed_slot_to_next_day(self):
        morning = {**BASE, **windows.SLOTS["morning"],
                   "same_day_publish_required": True}
        with self.assertRaises(SetupError):
            next_publish_at(morning, datetime(2026, 11, 11, 22, 30,
                                              tzinfo=timezone.utc))
        with self.assertRaises(SetupError):
            next_publish_at(morning, datetime(2026, 11, 12, 0, 0,
                                              tzinfo=timezone.utc))

    def test_dry_run_does_not_write_or_upload(self):
        with patch.object(windows.subprocess, "run") as call:
            self.assertEqual(windows.run_slot("morning", dry_run=True,
                                              now=MORNING, home=self.home), 0)
            call.assert_not_called()
        self.assertFalse((self.home / "state").exists())
        self.assertFalse((self.home / "effective_morning.json").exists())

    def test_disabled_is_a_fail_closed_default(self):
        disabled = {**BASE, "enabled": False}
        (self.home / "daily_config.json").write_text(
            json.dumps(disabled), encoding="utf-8")
        with patch.object(windows.subprocess, "run") as call:
            self.assertEqual(windows.run_slot("morning", now=MORNING,
                                              home=self.home), 0)
            call.assert_not_called()

    def test_morning_is_not_evening_attempt(self):
        self.put_state("morning", {"last_attempt_date": "2026-11-12",
                                   "used_sources": ["sample1"]})
        with patch.object(windows.subprocess, "run") as call:
            self.assertEqual(windows.run_slot("morning", now=MORNING,
                                              home=self.home), 0)
            call.assert_not_called()
            self.assertEqual(windows.run_slot("evening", now=EVENING,
                                              home=self.home), 0)
            self.assertEqual(call.call_count, 2)
        effective = json.loads(
            (self.home / "effective_evening.json").read_text(encoding="utf-8")
        )
        self.assertEqual(effective["publish_time"], "21:00")
        state = windows.read_state(self.home, "evening")
        self.assertEqual(state["used_sources"], ["sample1"])

    def test_source_history_merged_between_the_two_slots(self):
        self.put_state("morning", {"used_sources": ["x", "y"]})
        self.put_state("evening", {"used_sources": ["y", "z"]})
        self.assertEqual(windows.combined_sources(self.home), ["x", "y", "z"])
        with patch.object(windows.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as call:
            self.assertEqual(windows.run_slot("evening", now=EVENING,
                                              home=self.home), 0)
            self.assertEqual(call.call_count, 2)
            self.assertEqual(call.call_args_list[0].args[0][-1], "reserve")
            self.assertEqual(call.call_args_list[1].args[0][-1], "run")
            env = call.call_args_list[0].kwargs["env"]
            self.assertTrue(env["SHORTS_STATE_PATH"].endswith("evening.json"))
        state = windows.read_state(self.home, "evening")
        self.assertEqual(state["used_sources"], ["x", "y", "z"])

    def test_missing_secrets_never_reserve(self):
        (self.home / "server.env").unlink()
        with patch.object(windows.subprocess, "run") as call:
            with self.assertRaises(SetupError):
                windows.run_slot("morning", now=MORNING, home=self.home)
            call.assert_not_called()
        self.assertFalse(windows.state_path(self.home, "morning").exists())

    def test_late_start_is_skipped_not_backfilled(self):
        late = datetime(2026, 11, 11, 22, 30, tzinfo=timezone.utc)
        with patch.object(windows.subprocess, "run") as call:
            self.assertEqual(windows.run_slot("morning", now=late,
                                              home=self.home), 0)
            call.assert_not_called()

    def test_same_slot_cannot_run_in_parallel(self):
        with windows.exclusive_lock(self.home / "state" / "scheduler.lock") as first:
            self.assertTrue(first)
            with patch.object(windows.subprocess, "run") as call:
                self.assertEqual(windows.run_slot("morning", now=MORNING,
                                                  home=self.home), 0)
                call.assert_not_called()

    def test_upload_is_not_possible_without_rights_confirmation(self):
        invalid = {**BASE, "rights_attested": False}
        (self.home / "daily_config.json").write_text(
            json.dumps(invalid), encoding="utf-8")
        with patch.object(windows.subprocess, "run") as call:
            with self.assertRaises(SetupError):
                windows.run_slot("morning", now=MORNING, home=self.home)
            call.assert_not_called()

    def test_failed_reserve_never_starts_upload(self):
        with patch.object(windows.subprocess, "run", return_value=SimpleNamespace(returncode=1)) as call:
            self.assertEqual(windows.run_slot("morning", now=MORNING,
                                              home=self.home), 1)
            self.assertEqual(call.call_count, 1)
            self.assertEqual(call.call_args_list[0].args[0][-1], "reserve")


if __name__ == "__main__":
    unittest.main()
