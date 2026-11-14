"""Daily autonomous Shorts candidate search, guarded creation and YouTube upload.

This is a NEW cloud workflow, independent from the on-device Flutter batch.
No live upload happens unless configuration, per-channel consent and secrets
were all explicitly supplied. Videos must come from licensed creator handles.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

from daily_core import (
    SetupError, allowed_tiktok_url, schedule_due, source_fingerprint,
    validate_config, validate_title, youtube_status,
)


class UploadUncertain(RuntimeError):
    """Do not try another video: YouTube may have accepted the prior upload."""
    pass


ROOT = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get("SHORTS_CONFIG_PATH", str(ROOT / "daily_config.json"))).expanduser()
STATE = Path(os.environ.get("SHORTS_STATE_PATH", str(ROOT / "daily_state.json"))).expanduser()
PROMPT = ROOT / "gemini_title_prompt_ko.txt"


def say(message: str) -> None:
    # Never echo API keys, refresh tokens, headers or Gemini raw video URLs.
    print(message, flush=True)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def atomic_write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(path)


def env_required() -> dict:
    keys = ("GEMINI_API_KEY", "TAVILY_API_KEY", "YOUTUBE_CLIENT_ID",
            "YOUTUBE_CLIENT_SECRET", "YOUTUBE_REFRESH_TOKEN")
    missing = [key for key in keys if not os.getenv(key)]
    if missing:
        raise SetupError("자동 실행 환경 변수 누락: " + ", ".join(missing))
    return {key: os.environ[key] for key in keys}


def discover(config: dict, state: dict, secrets: dict) -> list[str]:
    import requests

    selected = []
    used = set(state.get("used_sources", []))
    handles = config["licensed_tiktok_creators"][:12]
    for handle in handles:
        creator = str(handle).strip().lstrip("@")
        if not re.fullmatch(r"[A-Za-z0-9._]+", creator):
            continue
        query = (f"site:tiktok.com/@{creator}/video/ "
                 f"{config.get('topic', '재미있는 짧은 영상')}")
        try:
            res = requests.post(
                "https://api.tavily.com/search",
                headers={"Authorization": "Bearer " + secrets["TAVILY_API_KEY"]},
                json={"query": query, "search_depth": "basic",
                      "max_results": 15, "include_answer": False},
                timeout=22,
            )
            res.raise_for_status()
            results = res.json().get("results", [])
        except (requests.RequestException, ValueError) as exc:
            say("Tavily 검색 실패: " + type(exc).__name__)
            continue
        for entry in results:
            url = str(entry.get("url", ""))
            parsed = allowed_tiktok_url(url, handles)
            if parsed is None:
                continue
            canonical = f"https://www.tiktok.com/@{parsed[0]}/video/{parsed[1]}"
            if source_fingerprint(canonical) not in used and canonical not in selected:
                selected.append(canonical)
    # Additional explicitly authorized sources help when a search index is empty.
    for url in config.get("licensed_source_urls", []):
        parsed = allowed_tiktok_url(str(url), handles)
        if parsed is None:
            continue
        canonical = f"https://www.tiktok.com/@{parsed[0]}/video/{parsed[1]}"
        if source_fingerprint(canonical) not in used and canonical not in selected:
            selected.append(canonical)
    return selected[:int(config.get("max_candidates", 8))]


def probe_file(path: Path) -> tuple[float, int, int]:
    result = subprocess.run([
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration:stream=width,height,codec_type",
        "-of", "json", str(path)
    ], capture_output=True, text=True, timeout=35, check=True)
    data = json.loads(result.stdout)
    duration = float(data.get("format", {}).get("duration", 0))
    videos = [s for s in data.get("streams", [])
              if s.get("codec_type") == "video"]
    if not videos:
        raise SetupError("비디오 스트림을 읽을 수 없습니다.")
    return duration, int(videos[0].get("width") or 0), int(videos[0].get("height") or 0)


def download_candidate(url: str, tempdir: Path, config: dict) -> tuple[Path, float]:
    import yt_dlp

    # TikTok may fail with 10204, HTTP 403 or login protection. Do not bypass
    # access controls; just skip the candidate without publishing anything.
    with yt_dlp.YoutubeDL({
        "quiet": True, "no_warnings": True, "noplaylist": True,
        "socket_timeout": 30, "retries": 1, "fragment_retries": 1,
        "format": "best[height<=1920]/best",
        "outtmpl": str(tempdir / "source.%(ext)s"),
        "max_filesize": 65 * 1024 * 1024,
    }) as ydl:
        info = ydl.extract_info(url, download=False)
        if not isinstance(info, dict) or info.get("_type") in ("playlist", "multi_video"):
            raise SetupError("단일 영상이 아닌 검색 결과입니다.")
        duration = float(info.get("duration") or 0)
        if not config["min_duration_seconds"] <= duration <= config["max_duration_seconds"]:
            raise SetupError("길이 5~60초 조건에 맞지 않는 후보입니다.")
        width, height = info.get("width"), info.get("height")
        if width and height and int(width) > int(height):
            raise SetupError("세로형이 아닌 영상은 제외합니다.")
        ydl.extract_info(url, download=True)
    files = [p for p in tempdir.glob("source.*") if p.is_file()]
    if len(files) != 1:
        raise SetupError("접근 가능한 단일 영상 파일을 확보하지 못했습니다.")
    path = files[0]
    if path.stat().st_size > 65 * 1024 * 1024:
        raise SetupError("영상 다운로드 크기 제한 초과")
    duration, width, height = probe_file(path)
    if not config["min_duration_seconds"] <= duration <= config["max_duration_seconds"]:
        raise SetupError("실제 영상 길이가 허용 범위 밖입니다.")
    if width <= 0 or height <= 0 or width > height:
        raise SetupError("세로형 원본이 아닙니다.")
    return path, duration


def preexisting_overlay(path: Path, duration: float, tmp: Path) -> bool:
    """Conservative Korean/Latin OCR over nine temporal samples.

    This is a screen, NOT a mathematical proof that all frames lack captions.
    """
    import pytesseract
    from PIL import Image
    from pytesseract import Output

    for index in range(9):
        sec = duration * (index + 1) / 10
        jpg = tmp / f"probe_{index}.jpg"
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-ss", f"{sec:.2f}", "-i", str(path),
            "-frames:v", "1", "-vf", "scale=960:-2", str(jpg),
        ], check=True, timeout=25)
        with Image.open(jpg) as img:
            width, height = img.size
            # Exclude tiny platform badges at far edges, include mid-screen.
            roi = img.crop((int(width * .08), int(height * .13),
                            int(width * .92), int(height * .91)))
            found = pytesseract.image_to_data(
                roi, lang="kor+eng", config="--psm 11",
                output_type=Output.DICT,
            )
        words = 0
        for i, value in enumerate(found["text"]):
            clean = re.sub(r"[^\w가-힣]", "", value, flags=re.UNICODE)
            confidence = float(found["conf"][i])
            if confidence > 42 and len(clean) >= 3:
                words += 1
        if words:
            return True
    return False


def gemini_titles(path: Path, duration: float, config: dict, secrets: dict) -> dict:
    from google import genai
    from google.genai import types

    model = config.get("gemini_model", "gemini-3.5-flash")
    client = genai.Client(api_key=secrets["GEMINI_API_KEY"])
    uploaded = None
    try:
        uploaded = client.files.upload(file=str(path))
        for _ in range(90):
            if getattr(uploaded.state, "name", uploaded.state) == "ACTIVE":
                break
            if getattr(uploaded.state, "name", uploaded.state) == "FAILED":
                raise SetupError("Gemini 영상 처리가 실패했습니다.")
            time.sleep(4)
            uploaded = client.files.get(name=uploaded.name)
        else:
            raise SetupError("Gemini 영상 처리 제한 시간을 초과했습니다.")

        prompt = PROMPT.read_text(encoding="utf-8")
        issue = ""
        for attempt in range(3):
            response = client.models.generate_content(
                model=model,
                contents=[uploaded, prompt + "\n영상 길이(초): " + str(round(duration, 2)) + "\n" + issue],
                config=types.GenerateContentConfig(response_mime_type="application/json"),
            )
            try:
                result = json.loads(response.text)
                if result.get("source_text") != "absent":
                    raise SetupError("기존 자막·영상 내 글자가 있거나 불확실합니다.")
                titles = result.get("titles")
                if not isinstance(titles, dict):
                    raise SetupError("Gemini 제목 후보가 누락됐습니다.")
                picked = None
                for style in ("curiosity", "twist", "humor"):
                    item = titles.get(style) or {}
                    try:
                        validate_title(item.get("top", ""), item.get("bottom", ""))
                        picked = item
                        break
                    except SetupError:
                        continue
                if picked is None:
                    raise SetupError("Gemini 제목 3종 모두 5~11자 조건 위반")
                result["top"] = picked["top"]
                result["bottom"] = picked["bottom"]
                captions = result.get("captions", [])
                if not isinstance(captions, list) or len(captions) > 5:
                    raise SetupError("장면 자막 형식이 올바르지 않습니다.")
                valid = []
                for cue in captions:
                    if not isinstance(cue, dict):
                        continue
                    start, end = float(cue["start"]), float(cue["end"])
                    text = cue.get("text", "").strip()
                    if 0 <= start < end <= duration and end - start >= .5 and len(text) <= 40:
                        valid.append({"start": start, "end": end, "text": text})
                valid.sort(key=lambda x: x["start"])
                if any(valid[i]["start"] < valid[i-1]["end"] for i in range(1, len(valid))):
                    raise SetupError("자막 시간이 서로 겹칩니다.")
                result["captions"] = valid
                return result
            except (ValueError, KeyError, TypeError, SetupError) as exc:
                # Do not override a model's source-text safety refusal.
                if isinstance(exc, SetupError) and "기존 자막" in str(exc):
                    raise
                issue = "직전 응답에 형식 또는 제목 길이 오류가 있습니다. 더 자연스럽게 수정하세요."
        raise SetupError("Gemini 유효한 제목을 생성하지 못했습니다.")
    finally:
        if uploaded is not None:
            try:
                client.files.delete(name=uploaded.name)
            except Exception:
                pass
        client.close()


def ass_timestamp(seconds: float) -> str:
    centis = max(0, round(seconds * 100))
    hh, remainder = divmod(centis, 360000)
    mm, remainder = divmod(remainder, 6000)
    ss, cc = divmod(remainder, 100)
    return f"{hh}:{mm:02}:{ss:02}.{cc:02}"


def escape_ass(value: str) -> str:
    return value.replace("\\", " ").replace("{", "").replace("}", "").replace("\n", " ").replace(",", "，")


def make_ass(meta: dict, duration: float, path: Path) -> None:
    text = """[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: TOP,Noto Sans CJK KR,66,&H00FFFFFF,&H000000FF,&H00000000,&H70000000,-1,0,0,0,100,100,0,0,1,4,1,8,35,35,205,1
Style: BOTTOM,Noto Sans CJK KR,64,&H00FFFFFF,&H000000FF,&H00000000,&H70000000,-1,0,0,0,100,100,0,0,1,4,1,2,35,35,210,1
Style: CAPTION,Noto Sans CJK KR,52,&H00FFFFFF,&H000000FF,&H00000000,&H70000000,-1,0,0,0,100,100,0,0,1,4,1,2,60,60,400,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    end = ass_timestamp(duration)
    for style, caption in (("TOP", meta["top"]), ("BOTTOM", meta["bottom"])):
        text += f"Dialogue: 0,0:00:00.00,{end},{style},,0,0,0,,{escape_ass(caption)}\n"
    for cue in meta["captions"]:
        text += (f"Dialogue: 1,{ass_timestamp(cue['start'])},"
                 f"{ass_timestamp(cue['end'])},CAPTION,,0,0,0,,"
                 f"{escape_ass(cue['text'])}\n")
    path.write_text(text, encoding="utf-8")


def render_video(source: Path, meta: dict, duration: float, tmp: Path) -> Path:
    subs = tmp / "titles.ass"
    destination = tmp / "shorts_output.mp4"
    make_ass(meta, duration, subs)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(source),
        "-vf", f"scale=1080:1920:force_original_aspect_ratio=increase,"
               f"crop=1080:1920,ass={subs}",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "24",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart", str(destination),
    ], check=True, timeout=480)
    if not destination.exists() or destination.stat().st_size < 10000:
        raise SetupError("최종 쇼츠 MP4를 생성하지 못했습니다.")
    return destination


def upload_youtube(path: Path, meta: dict, source: str, config: dict, secrets: dict) -> tuple[str, str]:
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload

    credentials = Credentials(
        token=None,
        refresh_token=secrets["YOUTUBE_REFRESH_TOKEN"],
        token_uri="https://oauth2.googleapis.com/token",
        client_id=secrets["YOUTUBE_CLIENT_ID"],
        client_secret=secrets["YOUTUBE_CLIENT_SECRET"],
        scopes=["https://www.googleapis.com/auth/youtube.upload",
                "https://www.googleapis.com/auth/youtube.readonly"],
    )
    credentials.refresh(Request())
    youtube = build("youtube", "v3", credentials=credentials, cache_discovery=False)
    response = youtube.channels().list(part="id", mine=True).execute()
    channel_ids = {channel["id"] for channel in response.get("items", [])}
    if config["youtube_channel_id"] not in channel_ids:
        raise SetupError("선택한 YouTube 채널과 인증된 계정이 다릅니다. 업로드 취소.")

    status = youtube_status(config, datetime.now(timezone.utc))
    body = {
        "snippet": {
            "title": meta["top"] + " " + meta["bottom"],
            "description": (
                "영상 출처 및 이용 허가: " + source +
                "\n본 영상은 재사용 권한이 확인된 원본만 업로드하도록 설정되었습니다."
            ),
            "categoryId": "24",
        },
        "status": {
            **status,
            "selfDeclaredMadeForKids": False,
            "containsSyntheticMedia": bool(config.get("contains_synthetic_media", False)),
        },
    }
    insert = youtube.videos().insert(
        part="snippet,status",
        body=body,
        media_body=MediaFileUpload(str(path), mimetype="video/mp4",
                                   chunksize=8 * 1024 * 1024, resumable=True),
    )
    response = None
    while response is None:
        _, response = insert.next_chunk()
    if not isinstance(response, dict) or not response.get("id"):
        raise SetupError("YouTube 업로드 ID를 확보하지 못했습니다.")
    actual = str(response.get("status", {}).get("privacyStatus", "unknown"))
    return str(response["id"]), actual


def sync_state() -> None:
    """Commit status only to automation-state, never to main (avoids APK builds)."""
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    import shutil
    repo_root = ROOT.parent
    subprocess.run(["git", "config", "user.name", "github-actions[bot]"],
                   cwd=repo_root, check=True)
    subprocess.run(["git", "config", "user.email",
                    "41898282+github-actions[bot]@users.noreply.github.com"],
                   cwd=repo_root, check=True)
    subprocess.run(["git", "fetch", "origin", "automation-state"],
                   cwd=repo_root, capture_output=True, check=True)
    worktree = Path(tempfile.mkdtemp(prefix="shorts-state-"))
    try:
        subprocess.run(["git", "worktree", "add", "--detach", str(worktree),
                        "origin/automation-state"], cwd=repo_root, check=True,
                       capture_output=True)
        target = worktree / "automation" / "daily_state.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(STATE, target)
        subprocess.run(["git", "add", "automation/daily_state.json"],
                       cwd=worktree, check=True, capture_output=True)
        diff = subprocess.run(["git", "diff", "--cached", "--quiet"],
                              cwd=worktree)
        if diff.returncode:
            subprocess.run(["git", "commit", "-m",
                            "Save cloud Shorts daily run status"], cwd=worktree,
                           check=True, capture_output=True)
            subprocess.run(["git", "push", "origin", "HEAD:automation-state"],
                           cwd=worktree, check=True, capture_output=True)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", str(worktree)],
                       cwd=repo_root, capture_output=True)
        try:
            worktree.rmdir()
        except OSError:
            pass


def reserve(config: dict, state: dict, now: datetime, manual: bool) -> bool:
    due, date, cause = schedule_due(config, state, now, manual=manual)
    if not due:
        say("오늘 실행 건너뜀: " + cause)
        return False
    validate_config(config, for_publish=True)
    env_required()
    state["last_attempt_date"] = date
    state["status"] = "reserved"
    state["last_error"] = ""
    atomic_write(STATE, state)
    sync_state()  # No upload begins unless today's attempt is durably saved.
    say(f"{date}: 하루 한 번 작업 예약 완료")
    return True


def produce(config: dict, state: dict, secrets: dict) -> dict:
    candidates = discover(config, state, secrets)
    if not candidates:
        raise SetupError("허가된 계정의 새 영상 후보를 찾지 못했습니다.")
    for url in candidates:
        say("새 영상 후보 평가 중")
        with tempfile.TemporaryDirectory(prefix="daily-short-") as directory:
            tmp = Path(directory)
            try:
                source, duration = download_candidate(url, tmp, config)
                if preexisting_overlay(source, duration, tmp):
                    say("기존 글자/자막 감지 · 후보 제외")
                    continue
                meta = gemini_titles(source, duration, config, secrets)
                rendered = render_video(source, meta, duration, tmp)

                # Source is excluded from all future runs BEFORE upload,
                # even if CI crashes just after YouTube accepts the media.
                fingerprint = source_fingerprint(url)
                state.setdefault("used_sources", []).append(fingerprint)
                state["pending_source"] = fingerprint
                state["status"] = "upload_pending"
                atomic_write(STATE, state)
                sync_state()
                try:
                    video_id, actual_privacy = upload_youtube(rendered, meta, url, config, secrets)
                except Exception:
                    raise UploadUncertain(
                        "YouTube 응답 확인 실패 · 중복 업로드 방지 위해 오늘 전송 종료"
                    ) from None
                return {
                    "source": fingerprint,
                    "video_id": video_id,
                    "actual_privacy": actual_privacy,
                    "title": meta["top"] + " " + meta["bottom"],
                }
            except UploadUncertain:
                raise
            except (SetupError, RuntimeError, OSError, subprocess.SubprocessError,
                    ValueError, KeyError, TypeError) as exc:
                say("후보 검사 실패: " + type(exc).__name__ + " · 다음 영상 검사")
                continue
            except Exception as exc:
                # yt-dlp and remote APIs may raise their own exception classes.
                # Never log authentication payloads from raw exceptions.
                say("후보 처리 실패: " + type(exc).__name__)
                continue
    raise SetupError("후보 영상이 검증을 통과하지 못해 오늘은 업로드하지 않습니다.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "reserve", "run"))
    parser.add_argument("--manual", action="store_true")
    args = parser.parse_args()
    config, state = load_json(CONFIG), load_json(STATE)
    now = datetime.now(timezone.utc)
    if args.command == "validate":
        validate_config(config)
        due, date, cause = schedule_due(config, state, now, manual=args.manual)
        say(f"{date} 예약: {'실행 가능' if due else cause}")
        return 0
    if args.command == "reserve":
        due = reserve(config, state, now, args.manual)
        if os.getenv("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
                f.write("run=" + ("true" if due else "false") + "\n")
        return 0
    if state.get("last_attempt_date") != now.astimezone(
            __import__("zoneinfo").ZoneInfo(config["timezone"])).date().isoformat():
        raise SetupError("오늘 예약된 작업이 없습니다.")
    validate_config(config, for_publish=True)
    try:
        result = produce(config, state, env_required())
        state.update({
            "last_success_date": state["last_attempt_date"],
            "status": "uploaded",
            "pending_source": "",
            "last_video_id": result["video_id"],
            "last_privacy": result["actual_privacy"],
        })
        state.setdefault("published", []).append({
            "date": state["last_success_date"],
            **result,
        })
        state["published"] = state["published"][-150:]
        say("유튜브 접수 성공: " + result["video_id"] +
            " · 실제 privacy=" + result["actual_privacy"])
    except Exception as exc:
        state["status"] = "upload_uncertain" if state.get("pending_source") else "failed"
        state["last_error"] = type(exc).__name__ + ": " + str(exc)[:140]
        say("오늘 자동 제작/업로드 실패 · 중복 전송 방지를 위해 자동 재시도하지 않습니다.")
        raise
    finally:
        atomic_write(STATE, state)
        sync_state()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SetupError as error:
        say("설정/검증 중단: " + str(error))
        raise SystemExit(1)
