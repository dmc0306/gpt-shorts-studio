#!/usr/bin/env python3
"""Package separate activity-free Android daily producer, not cloud cron."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".headless.tmp")
with ZipFile(src) as archive:
    members=[(info,archive.read(info)) for info in archive.infolist()]
files={info.filename:blob for info,blob in members}
old_version="version: 0.21.25+84"
new_version="version: 0.21.26+85"
pub=files["pubspec.yaml"].decode()
assert pub.count(old_version)==1,"Unexpected APK version"
changes={"pubspec.yaml":pub.replace(old_version,new_version).encode()}

def replace(path,before,after):
    source=changes.get(path,files[path]).decode()
    if source.count(before)!=1:
        raise RuntimeError(f"Unexpected {path} anchor: {before[:100]} (count={source.count(before)})")
    changes[path]=source.replace(before,after).encode()

replace("tool/bootstrap.py",
    "('AndroidDailyScheduler.kt','src/main/kotlin/com/local/shorts_studio/AndroidDailyScheduler.kt'),",
    "('AndroidDailyScheduler.kt','src/main/kotlin/com/local/shorts_studio/AndroidDailyScheduler.kt'),"
    "('AndroidHeadlessDailyRunner.kt','src/main/kotlin/com/local/shorts_studio/AndroidHeadlessDailyRunner.kt'),"
    "('HeadlessDailyMedia.kt','src/main/kotlin/com/local/shorts_studio/HeadlessDailyMedia.kt'),")
replace("lib/youtube_settings.dart",
    "앱 프로세스가 살아 있으면",
    "앱을 열지 않아도 예약 실행기가")
replace("lib/youtube_settings.dart",
    "'완전히 종료된 앱을 화면 없이 다시 실행할 수는 없으며, '",
    "'앱 강제 중지·절전 등 Android 제약 시 자동 실행이 지연되거나 실패할 수 있으며, '")
replace("lib/youtube_settings.dart",
    "'이 경우에는 수동 시작 안내 알림으로 전환됩니다.'",
    "'실패 시 확인 알림을 표시합니다.'")

# WorkManager engine no longer depends on MainActivity/Flutter UI liveness.
replace("lib/daily_local_settings.dart",
    "'앱 프로세스가 살아 있으면 자동 제작을 시도하고, '",
    "'화면을 열지 않아도 새 Flutter 엔진으로 자동 제작을 시도하고, '")
replace("lib/daily_local_settings.dart",
    "'종료된 상태에서는 실행 알림을 보냅니다.'",
    "'Android 절전 제한으로 실패하면 알림을 보냅니다.'")
replace("lib/daily_local_settings.dart",
    "'앱 화면을 닫더라도 프로세스가 유지되면 예약 시각에 '",
    "'앱 화면을 닫더라도 Android 예약 작업이 실행되면 '")
replace("lib/daily_local_settings.dart",
    "'1회 시도합니다. 완전히 종료되거나 시스템에 의해 프로세스가 '",
    "'1회 시도합니다. 시스템이 앱을 강제 중지하거나 '")
replace("lib/daily_local_settings.dart",
    "'제거되면 자동 제작을 보장할 수 없고 확인 알림을 표시합니다. '",
    "'배터리 절전으로 실행을 제한하면 실패 알림을 표시합니다. '")

new_files={
    "lib/daily_headless_runner.dart":Path("tool/daily_headless_runner.dart").read_bytes(),
    "native/android/HeadlessDailyMedia.kt":Path("tool/HeadlessDailyMedia.kt").read_bytes(),
    "native/android/AndroidHeadlessDailyRunner.kt":Path("tool/AndroidHeadlessDailyRunner.kt").read_bytes(),
}
changes["native/android/AndroidDailyScheduler.kt"]=Path("tool/AndroidDailyScheduler.kt").read_bytes()
for name in new_files:
    if name in files:raise RuntimeError("Unexpected existing file: "+name)
with ZipFile(tmp,"w") as archive:
    for info,blob in members:
        archive.writestr(info,changes.get(info.filename,blob))
    for name,blob in new_files.items():
        archive.writestr(name,blob)
os.replace(tmp,src)
print("Packaged v0.21.26+85, native WorkManager starts separate Flutter AOT engine")
