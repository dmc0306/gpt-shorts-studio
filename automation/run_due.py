"""Minute-level Linux scheduler for the existing guarded Shorts workflow.

Runs under a systemd user timer; no GitHub Actions or Flutter process needed.
Reservations are persisted before producing, and a flock prevents parallel runs.
"""
from __future__ import annotations

import argparse
import fcntl
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from daily_core import SetupError, schedule_due, validate_config
from daily_pipeline import CONFIG, STATE, load_json


def run_once(*, dry_run: bool = False) -> int:
    lock_path = Path(os.environ.get(
        "SHORTS_LOCK_PATH", str(STATE.with_suffix(".lock"))
    )).expanduser()
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("다른 Shorts 작업이 진행 중이므로 중복 실행하지 않습니다.", flush=True)
            return 0

        config = load_json(CONFIG)
        validate_config(config)
        state = load_json(STATE)
        due, day, reason = schedule_due(config, state, datetime.now(timezone.utc))
        if not due:
            # No log spam when run every minute.
            if dry_run:
                print(f"{day}: 실행하지 않음 ({reason})", flush=True)
            return 0
        if dry_run:
            print(f"{day}: 예약 시간 도달 · 검색→검증→편집→업로드 실행 가능", flush=True)
            return 0

        print(f"{day}: 설정한 시간 도달, 오늘의 Shorts 1개 자동 제작 시작", flush=True)
        # The first process durably reserves the day before any remote upload.
        # The second runs the existing candidate checks, Gemini title-length
        # validation, FFmpeg rendering and YouTube upload.
        pipeline = str(Path(__file__).resolve().parent / "daily_pipeline.py")
        for action in ("reserve", "run"):
            result = subprocess.run(
                [sys.executable, "-u", pipeline, action], check=False,
            )
            if result.returncode:
                print(f"{day}: {action} 실패 (종료 코드 {result.returncode})", flush=True)
                return result.returncode
        print(f"{day}: 자동 제작 파이프라인 종료", flush=True)
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="systemd용 Shorts 매일 1개 백그라운드 자동화 실행기"
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="실행 가능 여부만 점검, 업로드/상태 수정 없음")
    args = parser.parse_args()
    try:
        return run_once(dry_run=args.dry_run)
    except (SetupError, FileNotFoundError, ValueError, OSError) as exc:
        print("예약 실행 중단: " + str(exc), file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
