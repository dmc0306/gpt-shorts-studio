import sys
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parent))
from daily_core import (
    SetupError, allowed_tiktok_url, next_publish_at, schedule_due,
    source_fingerprint, utc_daily_cron, validate_title, youtube_status,
)
import daily_pipeline


CONFIG={
    "enabled":True,
    "timezone":"Asia/Seoul",
    "run_time":"09:00",
    "publish_mode":"scheduled",
    "publish_time":"18:00",
    "topic":"pets",
    "licensed_tiktok_creators":["licensed_creator"],
    "rights_attested":True,
    "youtube_channel_id":"UC"+"a"*22,
    "min_duration_seconds":5,
    "max_duration_seconds":60,
    "max_candidates":8,
}


class DailyPipelineTests(unittest.TestCase):
    def test_daily_korean_time_and_cron(self):
        self.assertEqual(utc_daily_cron("09:00"),"0 0 * * *")
        self.assertEqual(utc_daily_cron("00:30"),"30 15 * * *")
        self.assertEqual(utc_daily_cron("23:45"),"45 14 * * *")
        now=datetime(2026,11,12,0,2,tzinfo=timezone.utc)
        due,day,reason=schedule_due(CONFIG,{},now)
        self.assertEqual((due,day,reason),(True,"2026-11-12","scheduled"))
        due,_,reason=schedule_due(CONFIG,{"last_attempt_date":"2026-11-12"},now)
        self.assertFalse(due);self.assertEqual(reason,"already_attempted")
        before=datetime(2026,11,11,23,55,tzinfo=timezone.utc)
        self.assertFalse(schedule_due(CONFIG,{},before)[0])
        late=datetime(2026,11,12,8,0,tzinfo=timezone.utc)
        self.assertEqual(schedule_due(CONFIG,{},late)[2],"missed_window")

    def test_publish_at_uses_youtube_private_and_future_utc_time(self):
        now=datetime(2026,11,12,0,0,tzinfo=timezone.utc)
        status=youtube_status(CONFIG,now)
        self.assertEqual(status["privacyStatus"],"private")
        self.assertEqual(status["publishAt"],"2026-11-12T09:00:00Z")
        at_noon=datetime(2026,11,12,8,30,tzinfo=timezone.utc)
        self.assertEqual(next_publish_at(CONFIG,at_noon).date().isoformat(),"2026-11-13")
        self.assertEqual(youtube_status({**CONFIG,"publish_mode":"public"},now),
                         {"privacyStatus":"public"})
        self.assertEqual(youtube_status({**CONFIG,"publish_mode":"private"},now),
                         {"privacyStatus":"private"})

    def test_strict_original_rights_gating(self):
        good="https://www.tiktok.com/@licensed_creator/video/123456789"
        self.assertEqual(allowed_tiktok_url(good,["licensed_creator"]),
                         ("licensed_creator","123456789"))
        self.assertIsNone(allowed_tiktok_url(good,["different"]))
        self.assertIsNone(allowed_tiktok_url(
            "https://tiktok.com.evil.com/@licensed_creator/video/123",["licensed_creator"]))
        self.assertIsNone(allowed_tiktok_url(
            "http://www.tiktok.com/@licensed_creator/video/123",["licensed_creator"]))
        self.assertIsNone(allowed_tiktok_url(
            "https://www.tiktok.com/@licensed_creator/photo/123",["licensed_creator"]))
        with self.assertRaises(SetupError):
            from daily_core import validate_config
            validate_config({**CONFIG,"rights_attested":False},for_publish=True)

    def test_headline_grapheme_length_including_spaces(self):
        self.assertEqual(validate_title("휴대폰 보다가","스스로를 찍었다"),
                         "휴대폰 보다가\n스스로를 찍었다")
        self.assertEqual(validate_title("상위 1% 강아지","대체 뭘 했길래"),
                         "상위 1% 강아지\n대체 뭘 했길래")
        for top,bottom in [
            ("짧음","이건 너무 짧다"),
            ("진짜 너무너무너무너무 길어","이건 너무 짧다"),
            ("귀여운 고양이 ","표정이 왜 저래"),
            ("진짜  강아지","표정이 왜 저래"),
        ]:
            with self.assertRaises(SetupError):
                validate_title(top,bottom)

    def test_failed_upload_never_moves_to_second_candidate(self):
        urls=[
            "https://www.tiktok.com/@licensed_creator/video/123",
            "https://www.tiktok.com/@licensed_creator/video/456",
        ]
        config=dict(CONFIG)
        state={"used_sources":[]}
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as temp:
            fake=Path(temp)/"source.mp4"
            with (patch.object(daily_pipeline,"discover",return_value=urls),
                  patch.object(daily_pipeline,"download_candidate",return_value=(fake,20.0)) as download,
                  patch.object(daily_pipeline,"preexisting_overlay",return_value=False),
                  patch.object(daily_pipeline,"gemini_titles",
                               return_value={"top":"휴대폰 보다가","bottom":"스스로를 찍었다","captions":[]}),
                  patch.object(daily_pipeline,"render_video",return_value=fake),
                  patch.object(daily_pipeline,"upload_youtube",side_effect=RuntimeError("response lost")) as upload,
                  patch.object(daily_pipeline,"sync_state"),
                  patch.object(daily_pipeline,"atomic_write")):
                with self.assertRaises(daily_pipeline.UploadUncertain):
                    daily_pipeline.produce(config,state,{"unused":"test"})
                self.assertEqual(download.call_count,1)
                self.assertEqual(upload.call_count,1)
                self.assertEqual(len(state["used_sources"]),1)
                self.assertEqual(state["pending_source"],source_fingerprint(urls[0]))


if __name__ == "__main__":
    unittest.main()
