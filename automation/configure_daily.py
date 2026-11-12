"""Called by the Configure Daily Shorts GitHub Actions form; never stores credentials."""
import json
import os
import re
from pathlib import Path

from daily_core import validate_config, utc_daily_cron

ROOT=Path(__file__).resolve().parent
config_path=ROOT/"daily_config.json"
workflow_path=ROOT.parent/".github/workflows/daily-auto-publish.yml"


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
    cron=utc_daily_cron(config["run_time"])
    contents=workflow_path.read_text(encoding="utf-8")
    matcher=r"(?m)^    - cron: '[^']+' # DAILY_KST_CRON$"
    updated,n=re.subn(matcher,f"    - cron: '{cron}' # DAILY_KST_CRON",contents)
    if n!=1:raise ValueError("GitHub Actions 예약 설정을 찾지 못했습니다.")
    workflow_path.write_text(updated,encoding="utf-8")
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+"\n",
                           encoding="utf-8")
    print("한국 시간 "+config["run_time"]+" 매일 예약; Actions UTC cron="+cron)
    print("자동 제작 업로드: "+("활성화" if enabled else "비활성화"))
    print("공개 모드: "+config["publish_mode"])


if __name__=="__main__":
    main()
