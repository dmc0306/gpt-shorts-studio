"""Configure the always-on server scheduler without GitHub Actions.

Example:
  python automation/configure_local.py --run-time 09:00
  python automation/configure_local.py --enable --creators mine --rights-confirmed \
      --channel-id UCxxxxxxxxxxxxxxxxxxxxxx --publish-mode scheduled
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from daily_core import SetupError, validate_config
from daily_pipeline import CONFIG, atomic_write, load_json


def apply_settings(config: dict, args: argparse.Namespace) -> dict:
    new = dict(config)
    fields = {
        "run_time": args.run_time,
        "publish_time": args.publish_time,
        "publish_mode": args.publish_mode,
        "topic": args.topic,
        "youtube_channel_id": args.channel_id,
    }
    for field, value in fields.items():
        if value is not None:
            new[field] = value.strip() if isinstance(value, str) else value
    if args.creators is not None:
        new["licensed_tiktok_creators"] = [
            x.strip().lstrip("@") for x in args.creators.split(",") if x.strip()
        ]
    if args.enable:
        new["enabled"] = True
    if args.disable:
        new["enabled"] = False
    if args.rights_confirmed:
        new["rights_attested"] = True
    if args.rights_revoked:
        new["rights_attested"] = False
        new["enabled"] = False
    if args.public_approved:
        new["public_approved"] = True
    # A newly activated (or rescheduled) job begins no earlier than now.
    if (new.get("enabled") and
            (not config.get("enabled") or
             new.get("run_time") != config.get("run_time"))):
        new["not_before"] = datetime.now(timezone.utc).isoformat()
    # Keep immediate public posting opt-in distinct from rights confirmation.
    if new.get("enabled") and new.get("publish_mode") == "public":
        if not new.get("public_approved"):
            raise SetupError("즉시 공개에는 --public-approved 별도 확인이 필요합니다.")
    validate_config(new, for_publish=bool(new.get("enabled")))
    return new


def main() -> int:
    parser = argparse.ArgumentParser(
        description="백그라운드 자동 Shorts 예약·공개 시간 분리 설정"
    )
    toggle = parser.add_mutually_exclusive_group()
    toggle.add_argument("--enable", action="store_true")
    toggle.add_argument("--disable", action="store_true")
    parser.add_argument("--run-time", metavar="HH:MM",
                        help="매일 영상 검색·편집·업로드 시작 시간 (한국 시각)")
    parser.add_argument("--publish-time", metavar="HH:MM",
                        help="YouTube 예약 공개 시간 (한국 시각)")
    parser.add_argument("--publish-mode",
                        choices=("private", "public", "scheduled"))
    parser.add_argument("--topic", help="검색 주제")
    parser.add_argument("--creators", metavar="ACCOUNT,ACCOUNT",
                        help="직접 소유하거나 재게시 허가받은 TikTok 계정")
    parser.add_argument("--channel-id", help="연결된 YouTube 채널 ID (UC...)")
    rights = parser.add_mutually_exclusive_group()
    rights.add_argument("--rights-confirmed", action="store_true",
                        help="등록한 영상의 수정 및 재게시 허가를 확인")
    rights.add_argument("--rights-revoked", action="store_true")
    parser.add_argument("--public-approved", action="store_true",
                        help="새 영상 즉시 전체 공개를 별도로 승인")
    args = parser.parse_args()
    try:
        current = load_json(CONFIG)
        new = apply_settings(current, args)
        if new != current:
            atomic_write(CONFIG, new)
        print("자동 제작:", "켜짐" if new.get("enabled") else "꺼짐")
        print("매일 제작 시작:", new.get("run_time", "09:00"), "KST")
        print("YouTube 공개:", new.get("publish_mode"), "/",
              new.get("publish_time", "18:00"), "KST")
        print("허가된 제작자:", len(new.get("licensed_tiktok_creators", [])), "계정")
        print("YouTube 채널:", new.get("youtube_channel_id") or "미설정")
        if new.get("enabled"):
            print("다음 예약 시각부터 하루 최대 1개 자동 제작을 시도합니다.")
        return 0
    except (SetupError, FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
