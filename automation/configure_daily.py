"""Called by the Configure Daily Shorts GitHub Actions form; never stores credentials."""
import json
import os
import re
from pathlib import Path

from daily_core import validate_config

ROOT=Path(__file__).resolve().parent
config_path=ROOT/"daily_config.json"


def main() -> None:
    config=json.loads(config_path.read_text(encoding="utf-8"))
    enabled=os.getenv("CFG_ENABLED","false").lower()=="true"
    creators=[x.strip().lstrip("@") for x in os.getenv("CFG_CREATORS","").split(",")
              if x.strip()]
    config.update({
        "enabled":enabled,
        "timezone":"Asia/Seoul",
        "run_time":os.getenv("CFG_RUN_TIME","09:00").strip(),
        "publish_mode":os.getenv("CFG_MODE","scheduled"),
        "publish_time":os.getenv("CFG_PUBLISH_TIME","18:00").strip(),
        "topic":os.getenv("CFG_TOPIC",config.get("topic","짧은 동물 영상")).strip(),
        "licensed_tiktok_creators":creators,
        "rights_attested":os.getenv("CFG_RIGHTS","false").lower()=="true",
        "youtube_channel_id":os.getenv("CFG_CHANNEL_ID","").strip(),
    })
    validate_config(config,for_publish=enabled)
    if enabled:
        missing=[name for name in (
            "GEMINI_API_KEY","TAVILY_API_KEY","YOUTUBE_CLIENT_ID",
            "YOUTUBE_CLIENT_SECRET","YOUTUBE_REFRESH_TOKEN"
        ) if not os.getenv(name)]
        if missing:
            raise ValueError("공개 자동화 활성화 전에 Secrets 등록 필요: "+", ".join(missing))
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+"\n",
                           encoding="utf-8")
    print("한국 시간 "+config["run_time"]+" 이후 30분 간격 점검 시 실행 (GitHub 지연 가능)")
    print("자동 제작 업로드: "+("활성화" if enabled else "비활성화"))
    print("공개 모드: "+config["publish_mode"])


if __name__=="__main__":
    main()
