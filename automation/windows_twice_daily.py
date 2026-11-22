"""Windows local scheduler: two guarded Shorts attempts per Korea day.

Runs at 06:00/18:00 KST. The YouTube publishAt slots are 09:00/21:00 KST.
Each slot has an independent attempt journal, but shares all used-source
fingerprints. No remote operation without explicit local configuration and
credentials. This file intentionally does not depend on Linux fcntl.
"""
from __future__ import annotations

import argparse
import contextlib
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from daily_core import SetupError, parse_clock, schedule_due, validate_config
from daily_pipeline import atomic_write, load_json

SLOTS = {
    "morning": {"run_time": "06:00", "publish_time": "09:00"},
    "evening": {"run_time": "18:00", "publish_time": "21:00"},
}
SECRETS = (
    "GEMINI_API_KEY", "TAVILY_API_KEY", "YOUTUBE_CLIENT_ID",
    "YOUTUBE_CLIENT_SECRET", "YOUTUBE_REFRESH_TOKEN",
)
KST = ZoneInfo("Asia/Seoul")
SCRIPT = Path(__file__).resolve().parent / "daily_pipeline.py"


def app_home() -> Path:
    explicit = os.getenv("SHORTS_WINDOWS_HOME")
    if explicit:
        return Path(explicit).expanduser().resolve()
    return Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "ShortsStudioAutomation"


def state_path(home: Path, slot: str) -> Path:
    return home / "state" / f"{slot}.json"


def read_state(home: Path, slot: str) -> dict:
    path = state_path(home, slot)
    return load_json(path) if path.exists() else {"used_sources": [], "published": []}


def combined_sources(home: Path) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for slot in SLOTS:
        for source in read_state(home, slot).get("used_sources", []):
            if source not in seen:
                seen.add(source)
                result.append(source)
    return result


def load_private_secrets(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise SetupError(f"로컬 비밀값 파일을 찾지 못했습니다: {path}")
    secrets: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in stripped:
            raise SetupError("server.env 형식 오류: KEY=VALUE 형태를 사용하세요.")
        key, value = stripped.split("=", 1)
        key = key.strip()
        if key in SECRETS:
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            secrets[key] = value
    missing = [key for key in SECRETS if not secrets.get(key)]
    if missing:
        raise SetupError("server.env 누락 항목: " + ", ".join(missing))
    return secrets


@contextlib.contextmanager
def exclusive_lock(path: Path):
    """One process at a time, even across the two Task Scheduler jobs."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"0")
            handle.flush()
        handle.seek(0)
        if os.name == "nt":
            import msvcrt
            try:
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                yield False
                return
            try:
                yield True
            finally:
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                yield False
                return
            try:
                yield True
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def remaining_margin(now: datetime, slot: str) -> timedelta:
    local = now.astimezone(KST)
    hour, minute = parse_clock(SLOTS[slot]["publish_time"])
    published = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return published - local


def run_slot(slot: str, *, dry_run: bool = False, now: datetime | None = None,
             home: Path | None = None) -> int:
    if slot not in SLOTS:
        raise SetupError("유효하지 않은 작업 슬롯입니다.")
    home = home if home is not None else app_home()
    config_file = home / "daily_config.json"
    if not config_file.is_file():
        raise SetupError("Windows 설정 파일이 없습니다. install_windows.ps1을 먼저 실행하세요.")
    current = now if now is not None else datetime.now(timezone.utc)
    if current.tzinfo is None:
        raise SetupError("현재 시각에 타임존이 필요합니다.")

    with exclusive_lock(home / "state" / "scheduler.lock") as acquired:
        if not acquired:
            print("다른 Shorts 제작 작업이 진행 중이므로 중복 실행하지 않습니다.")
            return 0

        base = load_json(config_file)
        validate_config(base, for_publish=bool(base.get("enabled")))
        if base.get("enabled") and base.get("publish_mode") != "scheduled":
            raise SetupError("Windows 2회 자동화는 scheduled 공개 방식에서만 실행됩니다.")

        cfg = {**base, **SLOTS[slot], "publish_mode": "scheduled",
               "same_day_publish_required": True}
        state = read_state(home, slot)
        due, day, reason = schedule_due(cfg, state, current)
        margin = remaining_margin(current, slot)
        # Core's YouTube scheduling requires >2h of lead time. Fail closed if
        # delayed instead of silently publishing during tomorrow's slot.
        if due and margin <= timedelta(hours=2):
            due, reason = False, "publish_deadline_passed"

        if dry_run or not due:
            print(f"{day} {slot}: " +
                  ("실행 가능" if due else f"실행하지 않음 ({reason})"))
            return 0

        # Validate every required credential BEFORE reserving an attempt.
        secrets = load_private_secrets(home / "server.env")
        # A common source history prevents reusing morning's video in evening.
        state["used_sources"] = combined_sources(home)
        atomic_write(state_path(home, slot), state)
        effective = home / f"effective_{slot}.json"
        atomic_write(effective, cfg)
        environment = os.environ.copy()
        environment.update(secrets)
        environment["SHORTS_CONFIG_PATH"] = str(effective)
        environment["SHORTS_STATE_PATH"] = str(state_path(home, slot))
        # Ensure a Linux or GitHub-specific sync path is never active locally.
        environment.pop("GITHUB_ACTIONS", None)

        log_dir = home / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / f"{day}_{slot}.log"
        print(f"{day} {slot}: 검색→검증→편집→예약 업로드 시작 · 로그: {log_path}")
        with log_path.open("a", encoding="utf-8") as log:
            for action in ("reserve", "run"):
                result = subprocess.run(
                    [sys.executable, "-u", str(SCRIPT), action],
                    env=environment, cwd=str(SCRIPT.parent.parent),
                    stdout=log, stderr=subprocess.STDOUT, check=False,
                )
                log.flush()
                if result.returncode:
                    print(f"{day} {slot}: {action} 실패 ({result.returncode}). 로그를 확인하세요.")
                    return result.returncode
        print(f"{day} {slot}: YouTube 예약 등록 작업 종료")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Windows 06/18시 자동 제작 · 09/21시 예약 공개")
    parser.add_argument("--slot", required=True, choices=SLOTS)
    parser.add_argument("--dry-run", action="store_true",
                        help="예약 판단만 출력; 파일 수정 및 외부 호출 없음")
    args = parser.parse_args()
    try:
        return run_slot(args.slot, dry_run=args.dry_run)
    except (SetupError, ValueError, OSError, subprocess.SubprocessError) as exc:
        print("Shorts Windows 자동화 중단: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
