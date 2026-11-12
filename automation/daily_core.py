"""Pure, testable scheduling and safety rules for daily cloud production."""
from __future__ import annotations

import hashlib
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

import regex


class SetupError(ValueError):
    pass


def parse_clock(text: str) -> tuple[int, int]:
    match = re.fullmatch(r"([01]\d|2[0-3]):([0-5]\d)", str(text))
    if not match:
        raise SetupError("예약 시간은 00:00~23:59 형식이어야 합니다.")
    return int(match[1]), int(match[2])


def validate_config(config: dict, *, for_publish: bool = False) -> None:
    tz = config.get("timezone", "Asia/Seoul")
    if tz != "Asia/Seoul":
        raise SetupError("현재 예약 실행은 한국 시간 Asia/Seoul만 지원합니다.")
    try:
        ZoneInfo(tz)
    except (KeyError, ValueError) as exc:
        raise SetupError("올바른 시간대를 입력하세요.") from exc
    parse_clock(config.get("run_time", "09:00"))
    parse_clock(config.get("publish_time", "18:00"))
    if config.get("publish_mode") not in ("private", "public", "scheduled"):
        raise SetupError("공개 방식은 private/public/scheduled 중 하나입니다.")
    if not isinstance(config.get("licensed_tiktok_creators"), list):
        raise SetupError("허가된 영상 제작자 목록 형식이 잘못됐습니다.")
    if not 1 <= int(config.get("max_candidates", 8)) <= 20:
        raise SetupError("한 번의 검색 후보 수는 1~20개입니다.")
    if not 5 <= int(config.get("min_duration_seconds", 5)) <= int(config.get("max_duration_seconds", 60)) <= 60:
        raise SetupError("재사용 영상은 5~60초 범위만 허용합니다.")
    if for_publish:
        if not config.get("enabled"):
            raise SetupError("자동화가 활성화되어 있지 않습니다.")
        if not config.get("rights_attested"):
            raise SetupError("영상 재사용 권한 확인에 동의하지 않았습니다.")
        if not config.get("licensed_tiktok_creators"):
            raise SetupError("재사용 허가된 틱톡 제작자 계정이 없습니다.")
        if not re.fullmatch(r"UC[\w-]{22}", config.get("youtube_channel_id", "")):
            raise SetupError("내 YouTube 채널 ID(UC...)를 설정하세요.")


def now_local(now: datetime, config: dict) -> datetime:
    if now.tzinfo is None:
        raise SetupError("현재 시간에 타임존이 필요합니다.")
    return now.astimezone(ZoneInfo(config.get("timezone", "Asia/Seoul")))


def schedule_due(config: dict, state: dict, now: datetime, *, manual: bool = False) -> tuple[bool, str, str]:
    validate_config(config)
    local = now_local(now, config)
    today = local.date().isoformat()
    if not config.get("enabled"):
        return False, today, "disabled"
    if state.get("last_attempt_date") == today or state.get("last_success_date") == today:
        return False, today, "already_attempted"
    if manual:
        return True, today, "manual"
    hour, minute = parse_clock(config["run_time"])
    due = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if local < due:
        return False, today, "too_early"
    # Cron execution can be delayed, but an overnight backfill is unwanted.
    if local - due > timedelta(hours=6):
        return False, today, "missed_window"
    return True, today, "scheduled"


def utc_daily_cron(local_time: str) -> str:
    """GitHub Actions cron uses UTC; Korea has a fixed UTC+9 offset."""
    hour, minute = parse_clock(local_time)
    return f"{minute} {(hour - 9) % 24} * * *"


def next_publish_at(config: dict, now: datetime) -> datetime | None:
    mode = config.get("publish_mode", "private")
    if mode != "scheduled":
        return None
    local = now_local(now, config)
    hour, minute = parse_clock(config["publish_time"])
    target = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    # Allow upload, YouTube processing and channel verification.
    while target <= local + timedelta(hours=2):
        target += timedelta(days=1)
    return target.astimezone(timezone.utc)


def allowed_tiktok_url(url: str, creator_list: list[str]) -> tuple[str, str] | None:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or host not in ("tiktok.com", "www.tiktok.com", "m.tiktok.com"):
        return None
    match = re.fullmatch(r"/@([a-zA-Z0-9._]+)/video/(\d+)(?:/)?", parsed.path)
    if not match:
        return None
    handle, video_id = match.groups()
    allowed = {x.strip().lstrip("@").casefold() for x in creator_list}
    if handle.casefold() not in allowed:
        return None
    return handle, video_id


def source_fingerprint(url: str) -> str:
    return hashlib.sha256(url.encode("utf-8")).hexdigest()[:24]


def _visible_len(line: str) -> int:
    return len(regex.findall(r"\X", line))


def validate_title(top: str, bottom: str) -> str:
    for line in (top, bottom):
        if (not isinstance(line, str) or "\n" in line or "\r" in line or
                line.strip() != line or "  " in line or
                not 5 <= _visible_len(line) <= 11):
            raise SetupError("Gemini 제목은 상·하단 각각 공백 포함 5~11자여야 합니다.")
    if top == bottom:
        raise SetupError("위아래 제목이 동일합니다.")
    return top + "\n" + bottom


def youtube_status(config: dict, now: datetime) -> dict:
    mode = config.get("publish_mode", "private")
    if mode == "public":
        return {"privacyStatus": "public"}
    if mode == "scheduled":
        target = next_publish_at(config, now)
        if target is None:
            raise SetupError("예약 시간을 계산할 수 없습니다.")
        return {
            "privacyStatus": "private",
            "publishAt": target.isoformat(timespec="seconds").replace("+00:00", "Z"),
        }
    return {"privacyStatus": "private"}
