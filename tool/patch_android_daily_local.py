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
text=text[:start]+'''        ExpansionTile(
          title:const Text('휴대폰 백그라운드 자동 제작 예약',
            style:TextStyle(fontWeight:FontWeight.w600)),
          subtitle:const Text('매일 1회 · 영상 검색부터 YouTube까지'),
          children:[Padding(padding:const EdgeInsets.fromLTRB(8,4,8,16),
            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              const Text('GitHub Actions 없이 Android WorkManager에서 실행합니다. '
                '앱 프로세스가 살아 있으면 허가된 TikTok 영상 검색, '
                'Gemini 제목·자막 생성, MP4 제작 및 YouTube 업로드를 1회 시도합니다. '
                '앱이 완전히 종료된 상태에서는 사용자 알림으로 전환되며 '
                '자동 실행을 보장하지 않습니다.',
                style:TextStyle(fontSize:12)),
              const SizedBox(height:8),
              OutlinedButton.icon(
                onPressed:locked?null:()=>Navigator.of(context).push(
                  MaterialPageRoute(builder:(_)=>const DailyLocalSettingsScreen())),
                icon:const Icon(Icons.schedule_outlined),
                label:const Text('기기 내 예약 시간 설정'),
              ),
            ])),
          ],
        ),
''' +text[end:]
updates[path]=text.encode("utf-8")

# Keep a reference only while a real Flutter Activity engine exists.
replace("native/android/MainActivity.kt",
    'companion object { const val ACTION_CHROME_OAUTH_REDIRECT',
    'companion object { @Volatile var dailyRunChannel:MethodChannel?=null; const val ACTION_CHROME_OAUTH_REDIRECT')
replace("native/android/MainActivity.kt",
    '        BatchService.onStop={MethodChannel(engine.dartExecutor.binaryMessenger,"studio.local/batch").invokeMethod("stop",null)}',
    '        dailyRunChannel=MethodChannel(engine.dartExecutor.binaryMessenger,"studio.local/daily_run")\n'
    '        BatchService.onStop={MethodChannel(engine.dartExecutor.binaryMessenger,"studio.local/batch").invokeMethod("stop",null)}')
replace("native/android/MainActivity.kt",
    'override fun onDestroy(){if(youtubeChromeDelegate.isInitialized())',
    'override fun onDestroy(){dailyRunChannel=null;if(youtubeChromeDelegate.isInitialized())')
replace("native/android/MainActivity.kt",
    '''                r.success(AndroidDailyScheduler.configure(
                    applicationContext,enabled,hour,minute))''',
    '''                r.success(AndroidDailyScheduler.configure(
                    applicationContext,enabled,hour,minute,
                    call.argument<String>("creators")?:"",
                    call.argument<Boolean>("rights")==true))''')
replace("native/android/AndroidManifest.xml",
    '        <service android:name=".BatchService" android:exported="false" android:foregroundServiceType="dataSync|mediaProcessing" />',
    '''        <service android:name=".BatchService" android:exported="false" android:foregroundServiceType="dataSync|mediaProcessing" />
        <service android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync|mediaProcessing" tools:node="merge" />''')

replace("lib/main.dart",
    "import 'auto_batch.dart';",
    "import 'auto_batch.dart';\nimport 'youtube.dart';")
replace("lib/main.dart",
    " @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);init();}",
    """ static const localDaily=MethodChannel('studio.local/daily_run');
 @override void initState(){
   super.initState();
   WidgetsBinding.instance.addObserver(this);
   localDaily.setMethodCallHandler(_runScheduled);
   init();
 }
 Future<bool> _runScheduled(MethodCall call)async{
   if(call.method!='startDaily'||!mounted||!loaded||busy||draining||scanning||
      downloader!=null)return false;
   final raw=(call.arguments is Map)?call.arguments as Map:{};
   final allowed=(raw['creators'] is List)
     ?(raw['creators'] as List).whereType<String>().map((s)=>s.toLowerCase()).toSet()
     :<String>{};
   if(allowed.isEmpty)return false;
   try{
     final y=YouTube.instance;
     await y.loadSettings();
     if(!y.automatic||!y.preferences.confirmed||
       (y.preferences.publishMode!='private'&&!y.preferences.publicApproved)){
       return false;
     }
     final done=Completer<bool>();
     if(!mounted||busy)return false;
     setState(()=>busy=true);
     final route=Navigator.of(context).push(MaterialPageRoute(
       builder:(_)=>AutoBatchScreen(
         clips:clips,onSave:()=>Native.save(clips),
         dailyTriggered:true,licensedCreators:allowed,
         onDailyFinished:(ok){if(!done.isCompleted)done.complete(ok);}
       )));
     unawaited(route.then((_){
       if(!done.isCompleted)done.complete(false);
     }));
     final result=await done.future;
     if(mounted)setState(()=>busy=false);
     return result;
   }catch(_){
     if(mounted)setState(()=>busy=false);
     return false;
   }
 }
""")
replace("lib/main.dart",
    " @override void dispose(){downloader?.cancel();timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}",
    " @override void dispose(){localDaily.setMethodCallHandler(null);downloader?.cancel();timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}")

replace("lib/auto_batch.dart",
    " const AutoBatchScreen({super.key,required this.clips,required this.onSave});",
    """ const AutoBatchScreen({super.key,required this.clips,required this.onSave,
   this.dailyTriggered=false,this.licensedCreators=const <String>{},this.onDailyFinished});""")
replace("lib/auto_batch.dart",
    " final Future<void> Function() onSave;",
    """ final Future<void> Function() onSave;
 final bool dailyTriggered;
 final Set<String> licensedCreators;
 final void Function(bool success)? onDailyFinished;""")
replace("lib/auto_batch.dart",
    " bool previewing=false;",
    " bool previewing=false,reportedDaily=false;")
replace("lib/auto_batch.dart",
    "  if(mounted)setState(()=>loading=false);",
    """  if(mounted)setState(()=>loading=false);
  if(widget.dailyTriggered&&mounted){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)unawaited(start());
    });
  }""")
replace("lib/auto_batch.dart",
    " @override void dispose(){stopPoll?.cancel();",
    """ @override void dispose(){
  if(widget.dailyTriggered&&!reportedDaily){
    reportedDaily=true;
    widget.onDailyFinished?.call(false);
  }
  stopPoll?.cancel();""")
replace("lib/auto_batch.dart",
    "  if((!previewOnly&&key.isEmpty)||searchKey.isEmpty){update('AI 설정에서 Gemini 키와 Tavily 검색 키를 입력해 주세요.');await settings();return;}",
    """  if((!previewOnly&&key.isEmpty)||searchKey.isEmpty){
   update('AI 설정에서 Gemini 키와 Tavily 검색 키를 입력해 주세요.');
   if(widget.dailyTriggered){
     if(!reportedDaily){reportedDaily=true;widget.onDailyFinished?.call(false);}
   }else{await settings();}
   return;
  }""")
replace("lib/auto_batch.dart",
    "   await Native.call('batchStart');await saveReport();",
    "   if(!widget.dailyTriggered)await Native.call('batchStart');await saveReport();")
replace("lib/auto_batch.dart",
    "while(saved<5&&(!previewOnly||previewCount<5)",
    "while(saved<(widget.dailyTriggered?1:5)&&(!previewOnly||previewCount<5)")
replace("lib/auto_batch.dart",
    "    final candidate=selected;processed++;tried.add(MixedDiscovery.videoId(candidate.url)!);var retain=false;",
    """    final candidate=selected;
    if(widget.dailyTriggered){
      final handle=RegExp(r'/@([^/]+)/video/')
        .firstMatch(candidate.url)?.group(1)?.toLowerCase();
      if(handle==null||!widget.licensedCreators.contains(handle)){
        store.finish(candidate);
        tried.add(MixedDiscovery.videoId(candidate.url)!);
        continue;
      }
    }
    processed++;tried.add(MixedDiscovery.videoId(candidate.url)!);var retain=false;""")
replace("lib/auto_batch.dart",
    "   try{await Native.call('batchFinish',{'status':status,'saved':savedCount});}catch(_){}",
    "   if(!widget.dailyTriggered)try{await Native.call('batchFinish',{'status':status,'saved':savedCount});}catch(_){}")
# exact original finish may use no spaces in catch; repair against verified anchor below

replace("lib/auto_batch.dart",
    "const Text('웃긴 순간, 한 번에 5개'",
    "Text(widget.dailyTriggered?'오늘의 영상 1개':'웃긴 순간, 한 번에 5개'")
replace("lib/auto_batch.dart",
    "Text('${previewing?previewCount:savedCount} / 5개'",
    "Text('${previewing?previewCount:savedCount} / ${widget.dailyTriggered?1:5}개'")
replace("lib/auto_batch.dart",
    "value:(previewing?previewCount:savedCount)/5,",
    "value:(previewing?previewCount:savedCount)/(widget.dailyTriggered?1:5),")
replace("lib/auto_batch.dart",
    "   if(exitRequested&&mounted)Navigator.pop(context);",
    """   if(widget.dailyTriggered&&!reportedDaily){
     reportedDaily=true;
     widget.onDailyFinished?.call(reports.any((r)=>
       r['youtubeVideoId'] is String&&
       (r['youtubeVideoId'] as String).isNotEmpty));
   }
   if(exitRequested&&mounted)Navigator.pop(context);""")
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
