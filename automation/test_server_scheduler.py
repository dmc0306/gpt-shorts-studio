"""No-network regression tests for the standalone daily systemd scheduler."""
from __future__ import annotations

import fcntl
import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_due
from configure_local import apply_settings
from daily_core import SetupError


CONFIG = {
    "enabled": True,
    "timezone": "Asia/Seoul",
    "run_time": "09:00",
    "publish_mode": "scheduled",
    "publish_time": "18:00",
    "topic": "pets",
    "licensed_tiktok_creators": ["licensed_creator"],
    "rights_attested": True,
    "youtube_channel_id": "UC" + "a" * 22,
    "min_duration_seconds": 5,
    "max_duration_seconds": 60,
    "max_candidates": 8,
}
NOW = datetime(2026, 11, 12, 0, 1, tzinfo=timezone.utc)


def form(**changes):
    data = {
        "run_time": None, "publish_time": None,
        "publish_mode": None, "topic": None, "channel_id": None,
        "creators": None, "enable": False, "disable": False,
        "rights_confirmed": False, "rights_revoked": False,
        "public_approved": False,
    }
    data.update(changes)
    return SimpleNamespace(**data)


class LocalConfigTests(unittest.TestCase):
    def test_change_start_time_without_changing_publish_time(self):
        updated = apply_settings(CONFIG, form(run_time="13:45"))
        self.assertEqual(updated["run_time"], "13:45")
        self.assertEqual(updated["publish_time"], "18:00")

    def test_no_automatic_public_visibility(self):
        with self.assertRaises(SetupError):
            apply_settings(CONFIG, form(publish_mode="public"))
        updated = apply_settings(CONFIG, form(
            publish_mode="public", public_approved=True))
        self.assertTrue(updated["public_approved"])
        self.assertEqual(updated["publish_mode"], "public")

    def test_rights_revocation_disables_daily_upload(self):
        updated = apply_settings(CONFIG, form(rights_revoked=True))
        self.assertFalse(updated["enabled"])
        self.assertFalse(updated["rights_attested"])


class SystemdRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.conf = root / "daily_config.json"
        self.state = root / "daily_state.json"
        self.lock = root / "daily.lock"
        self.conf.write_text(json.dumps(CONFIG), encoding="utf-8")
        self.state.write_text(json.dumps({}), encoding="utf-8")
        self.patches = [
            patch.object(run_due, "CONFIG", self.conf),
            patch.object(run_due, "STATE", self.state),
            patch.dict("os.environ", {"SHORTS_LOCK_PATH": str(self.lock)}),
            patch.object(run_due, "datetime"),
        ]
        for p in self.patches:
            mocked = p.start()
            self.addCleanup(p.stop)
            if p.attribute == "datetime":
                mocked.now.return_value = NOW

    def test_before_daily_time_never_launches(self):
        config = {**CONFIG, "run_time": "09:30"}
        self.conf.write_text(json.dumps(config), encoding="utf-8")
        with patch.object(run_due.subprocess, "run") as call:
            self.assertEqual(run_due.run_once(), 0)
            call.assert_not_called()

    def test_when_due_reserve_before_run_exactly_once(self):
        with patch.object(run_due.subprocess, "run") as call:
            call.return_value.returncode = 0
            self.assertEqual(run_due.run_once(), 0)
            self.assertEqual(call.call_count, 2)
            self.assertEqual(call.call_args_list[0].args[0][-1], "reserve")
            self.assertEqual(call.call_args_list[1].args[0][-1], "run")

    def test_existing_daily_attempt_prevents_second_video(self):
        self.state.write_text(
            json.dumps({"last_attempt_date": "2026-11-12"}), encoding="utf-8")
        with patch.object(run_due.subprocess, "run") as call:
            self.assertEqual(run_due.run_once(), 0)
            call.assert_not_called()

    def test_lock_refuses_second_parallel_job(self):
        with self.lock.open("a+") as exclusive:
            fcntl.flock(exclusive.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.object(run_due.subprocess, "run") as call:
                self.assertEqual(run_due.run_once(), 0)
                call.assert_not_called()

    def test_reserve_failure_never_calls_upload(self):
        with patch.object(run_due.subprocess, "run") as call:
            call.return_value.returncode = 1
            self.assertEqual(run_due.run_once(), 1)
            self.assertEqual(call.call_count, 1)

    def test_dry_run_never_reserves_or_uploads(self):
        with patch.object(run_due.subprocess, "run") as call:
            self.assertEqual(run_due.run_once(dry_run=True), 0)
            call.assert_not_called()


if __name__ == "__main__":
    unittest.main()
