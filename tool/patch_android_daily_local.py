#!/usr/bin/env python3
"""Wire native WorkManager daily on-device reminders into Shorts Studio.

This change is a strictly labeled reminder fallback, NOT full headless
TikTok/Gemini/Media3/YouTube production. It intentionally avoids silently
claiming the user's requested end-to-end unattended capability is ready.
"""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".android-local.tmp")
with ZipFile(src) as archive:
    entries=[(info,archive.read(info)) for info in archive.infolist()]
files={info.filename:blob for info,blob in entries}
old="version: 0.21.24+83"
new="version: 0.21.25+84"
pub=files["pubspec.yaml"].decode("utf-8")
if pub.count(old)!=1:
    raise RuntimeError("Unexpected source version: "+pub[:130])
updates={"pubspec.yaml":pub.replace(old,new).encode("utf-8")}

def replace(path,needle,replacement):
    value=updates.get(path,files[path]).decode("utf-8")
    count=value.count(needle)
    if count!=1:
        raise RuntimeError(f"Missing/ambiguous source anchor {path}: {needle[:100]} ({count})")
    updates[path]=value.replace(needle,replacement,1).encode("utf-8")

replace("native/android/dependencies.gradle.kts",
    '    implementation("androidx.documentfile:documentfile:1.0.1")',
    '    implementation("androidx.documentfile:documentfile:1.0.1")\n'
    '    implementation("androidx.work:work-runtime-ktx:2.12.0")')

replace("native/android/MainActivity.kt",
    '        when(call.method) {',
    '''        when(call.method) {
            "dailyScheduleStatus" ->
                r.success(AndroidDailyScheduler.status(applicationContext))
            "dailyScheduleConfigure" -> {
                val enabled=call.argument<Boolean>("enabled") == true
                val hour=call.argument<Number>("hour")?.toInt() ?: 9
                val minute=call.argument<Number>("minute")?.toInt() ?: 0
                r.success(AndroidDailyScheduler.configure(
                    applicationContext,enabled,hour,minute))
            }
''')

replace("tool/bootstrap.py",
    "('BatchService.kt','src/main/kotlin/com/local/shorts_studio/BatchService.kt'),",
    "('BatchService.kt','src/main/kotlin/com/local/shorts_studio/BatchService.kt'),"
    "('AndroidDailyScheduler.kt','src/main/kotlin/com/local/shorts_studio/AndroidDailyScheduler.kt'),")

path="lib/youtube_settings.dart"
text=files[path].decode("utf-8")
anchor="import 'youtube_batch_publish_screen.dart';"
if text.count(anchor)!=1:raise RuntimeError("Unexpected YoutubeSettings imports")
text=text.replace(anchor,anchor+"\nimport 'daily_local_settings.dart';",1)
start=text.find("        const Text('매일 자동 검색·제작·업로드',")
end=text.find("        if(widget.clips.any((c)=>c.savedUri.isNotEmpty))...[",start)
if start<0 or end<=start:
    raise RuntimeError("Could not isolate previously installed GitHub Actions UI")
# retain divider preceding old text and replace the entire inaccurate cloud hint
text=text[:start]+'''        const Text('휴대폰 백그라운드 예약 알림',
          style:TextStyle(fontSize:19,fontWeight:FontWeight.w600)),
        const SizedBox(height:8),
        const Text('GitHub Actions 대신 Android WorkManager에서 '
          '매일 시각을 관리합니다. 현재는 예약 알림만 지원하며 '
          '앱이 완전히 닫혀 있을 때 자동 영상 검색·제작·업로드까지 '
          '실행하는 기능은 아직 지원되지 않습니다.',
          style:TextStyle(fontSize:12)),
        const SizedBox(height:8),
        OutlinedButton.icon(
          onPressed:locked?null:()=>Navigator.of(context).push(
            MaterialPageRoute(builder:(_)=>const DailyLocalSettingsScreen())),
          icon:const Icon(Icons.schedule_outlined),
          label:const Text('기기 내 예약 시간 설정'),
        ),
''' +text[end:]
updates[path]=text.encode("utf-8")
newfiles={
    "native/android/AndroidDailyScheduler.kt":
        Path("tool/AndroidDailyScheduler.kt").read_bytes(),
    "lib/daily_local_settings.dart":
        Path("tool/daily_local_settings.dart").read_bytes(),
}
for name in newfiles:
    if name in files:raise RuntimeError("Unexpected preexisting "+name)
with ZipFile(tmp,"w") as output:
    for info,blob in entries:
        output.writestr(info,updates.get(info.filename,blob))
    for name,blob in newfiles.items():
        output.writestr(name,blob)
os.replace(tmp,src)
print("Packaged v0.21.25 on-device daily WorkManager reminder, no GitHub scheduler")
