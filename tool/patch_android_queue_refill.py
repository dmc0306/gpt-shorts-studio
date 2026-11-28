#!/usr/bin/env python3
"""Patch existing Android app with an opt-in scheduled queue refill."""
from pathlib import Path
from zipfile import ZipFile
import os,re

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".queue-refill.tmp")
with ZipFile(src) as z: entries=[(i,z.read(i)) for i in z.infolist()]
files={i.filename:b for i,b in entries}
updates={}
def get(p):return updates.get(p,files[p]).decode()
def put(p,s):updates[p]=s.encode()
def rep(p,a,b):
    s=get(p)
    if s.count(a)!=1:raise RuntimeError(f"{p}: unexpected anchor {a[:120]} count={s.count(a)}")
    put(p,s.replace(a,b,1))

p="lib/youtube.dart"
rep(p,"import 'youtube_publish_plan.dart';","import 'youtube_publish_plan.dart';\nimport 'youtube_scheduled_queue.dart';")
rep(p,"  Future<Map<String, dynamic>> state(String uri) async {", """  Future<void> reloadAfterBackground() async {
    _settingsLoad=null;
    _initializing=null;
    await loadSettings();
  }

  Future<T> _withScheduledQueue<T>(
    Future<T> Function(YouTubeScheduledQueue) run,
  ) async {
    await initialize();
    final client=_clientFactory();
    try{
      final token=await _token();
      final actual=await readYouTubeChannel(client,token);
      preferences.requireTarget(identity,actual);
      return await run(YouTubeScheduledQueue(client,token,actual.id));
    }finally{client.close();}
  }

  Future<bool> hasScheduledQueue()=>_withScheduledQueue(
    (q)=>q.hasScheduled(DateTime.now()));
  Future<bool> verifyScheduledQueue(String id)=>_withScheduledQueue(
    (q)=>q.verifyScheduled(id,DateTime.now()));

  Future<Map<String, dynamic>> state(String uri) async {""")

p="lib/daily_local_settings.dart"
rep(p,"bool enabled=false,loading=true,saving=false,rights=false;","bool enabled=false,loading=true,saving=false,rights=false,queueMode=false;")
rep(p,"        rights=data['rightsAttested']==true;","        rights=data['rightsAttested']==true;\n        queueMode=data['queueMode']==true;")
rep(p,"        'creators':creatorText.text.trim(),'rights':rights,","        'creators':creatorText.text.trim(),'rights':rights,'queueMode':queueMode,")
rep(p,"        message=enabled?'매일 자동 제작 시도가 예약됐어요.':'예약 실행을 껐어요.';","        queueMode=data['queueMode']==true;\n        message=enabled?(queueMode?'예약 소진 자동 보충이 활성화됐어요.':'매일 자동 제작 시도가 예약됐어요.'):'예약 실행을 껐어요.';")
rep(p,"              Text('매일 $twoHour:$twoMin',","              Text(queueMode?'예약 0개 → 최대 5개 자동 보충':'매일 $twoHour:$twoMin',")
rep(p,"              const Text('한국 시간 · Android WorkManager'),","""              const Text('한국 시간 · Android WorkManager'),
              SwitchListTile.adaptive(
                contentPadding:EdgeInsets.zero,
                title:const Text('예약 영상 소진 시 자동 보충'),
                subtitle:const Text('30분마다 실제 YouTube 예약 목록을 확인하고, 0개이면 최대 5개를 제작해 예약합니다.'),
                value:queueMode,
                onChanged:saving||enabled?null:(v)=>setState(()=>queueMode=v)),
""")
rep(p,"title:const Text('매일 자동 제작 예약'),","title:Text(queueMode?'예약 자동 보충 켜기':'매일 자동 제작 예약'),")
rep(p,"              OutlinedButton.icon(\n                onPressed:saving?null:_pickTime,","              if(!queueMode)OutlinedButton.icon(\n                onPressed:saving?null:_pickTime,")
rep(p,"              const Text('GitHub Actions 없이 휴대폰에서 실행합니다. '","              if(queueMode)const Text('주기별 예약 공개와 완성 MP4 자동 업로드를 먼저 켜 주세요. 예약 영상이 남아 있으면 검색·제작하지 않습니다. 화면을 닫고 휴대폰이 유휴 상태일 때 실행하며, 조회가 실패하면 업로드하지 않습니다. 한 번에 최대 5개, 실패 시 다음 점검에서 다시 확인합니다.') else const Text('GitHub Actions 없이 휴대폰에서 실행합니다. '")

p="lib/youtube_settings.dart"
rep(p,"subtitle:const Text('매일 1회 · 영상 검색부터 YouTube까지'),","subtitle:const Text('매일 제작 또는 예약 소진 자동 보충'),")
rep(p,"label:const Text('기기 내 예약 시간 설정')","label:const Text('자동 제작 · 예약 보충 설정')")

p="native/android/AndroidDailyScheduler.kt"
rep(p,"    private const val LAST_RESULT = \"last_result\"","""    private const val LAST_RESULT = "last_result"
    private const val QUEUE_MODE = "queue_mode"
    private const val LAST_QUEUE_CHECK = "last_queue_check"
    private var uiHolders=0
    private var queueRunning=false
    @Synchronized fun holdUi(){uiHolders++}
    @Synchronized fun releaseUi(){if(uiHolders>0)uiHolders--}
    @Synchronized fun queueActive()=queueRunning
    @Synchronized fun tryQueue():Boolean{
        if(uiHolders>0||queueRunning)return false
        queueRunning=true
        return true
    }
    @Synchronized fun releaseQueue(){queueRunning=false}
    fun queueMode(context:Context):Boolean=context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
        .getBoolean(QUEUE_MODE,false)
    fun disable(context:Context){
        context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE).edit().putBoolean(ENABLED,false).commit()
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }
""")
rep(p,"creators:String, rights:Boolean):Map<String,Any> {","creators:String, rights:Boolean, queueMode:Boolean=false):Map<String,Any> {")
rep(p,"        check(prefs.edit().putBoolean(ENABLED,enabled)","""        val changed=prefs.getBoolean(QUEUE_MODE,false)!=queueMode
        val edit=prefs.edit().putBoolean(QUEUE_MODE,queueMode)
        if(changed||!prefs.getBoolean(ENABLED,false))edit.remove(LAST_QUEUE_CHECK)
        check(edit.putBoolean(ENABLED,enabled)""")
rep(p,"                24,TimeUnit.HOURS)\n                .setInitialDelay(ms,TimeUnit.MILLISECONDS)","""                if(queueMode)30L else 24*60L,TimeUnit.MINUTES)
                .setInitialDelay(if(queueMode)60_000L else ms,TimeUnit.MILLISECONDS)""")
rep(p,"ExistingPeriodicWorkPolicy.UPDATE,work)","if(changed)ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE else ExistingPeriodicWorkPolicy.UPDATE,work)")
rep(p,'            "mode" to "in_process_background_or_notification",','            "mode" to "in_process_background_or_notification",\n            "queueMode" to prefs.getBoolean(QUEUE_MODE,false),')
rep(p,"        val now=LocalDateTime.now(SEOUL)\n        if(now.toLocalTime()<LocalTime.of", """        if(prefs.getBoolean(QUEUE_MODE,false)){
            val nowMs=System.currentTimeMillis()
            val prev=prefs.getLong(LAST_QUEUE_CHECK,0L)
            if(nowMs>=prev&&nowMs-prev<15*60*1000L)return false
            return prefs.edit().putLong(LAST_QUEUE_CHECK,nowMs)
                .putString(LAST_NOTICE,LocalDateTime.now(SEOUL).toString()).commit()
        }
        val now=LocalDateTime.now(SEOUL)
        if(now.toLocalTime()<LocalTime.of""")
rep(p,"    override suspend fun doWork():Result {\n        if(!AndroidDailyScheduler.shouldNotify(applicationContext))","""    override suspend fun doWork():Result {
        val queue=AndroidDailyScheduler.queueMode(applicationContext)
        if(queue&&!AndroidDailyScheduler.tryQueue())return Result.success()
        try{return runScheduled(queue)}finally{if(queue)AndroidDailyScheduler.releaseQueue()}
    }
    private suspend fun runScheduled(queue:Boolean):Result{
        if(!AndroidDailyScheduler.shouldNotify(applicationContext))""")
rep(p,'.setContentTitle("매일 쇼츠 1개 자동 제작")','.setContentTitle(if(queue)"유튜브 예약 자동 보충" else "매일 쇼츠 1개 자동 제작")')
rep(p,"                val success=AndroidHeadlessDailyRunner.execute(\n                    applicationContext,handles","                val outcome=AndroidHeadlessDailyRunner.execute(\n                    applicationContext,handles,queue")
rep(p,"                if(success){\n                    AndroidDailyScheduler.record(applicationContext,\n                        \"성공: YouTube에 새 쇼츠 1개 업로드 접수\")","""                if(outcome.skipped){
                    AndroidDailyScheduler.record(applicationContext,outcome.message)
                    return Result.success()
                }
                if(outcome.success){
                    AndroidDailyScheduler.record(applicationContext,outcome.message)""")
rep(p,'.setContentTitle("오늘 쇼츠 1개 업로드 완료")','.setContentTitle(if(queue)"예약 영상 자동 보충 완료" else "오늘 쇼츠 1개 업로드 완료")')
rep(p,'.setContentText("YouTube 채널에서 상태를 확인해 주세요.")','.setContentText(outcome.message.take(180))')
rep(p,'                AndroidDailyScheduler.record(applicationContext,\n                    "실패: 조건에 맞는 새 영상이 없거나 업로드가 완료되지 않았어요.")','                AndroidDailyScheduler.record(applicationContext,outcome.message)')

p="native/android/AndroidHeadlessDailyRunner.kt"
rep(p,"import kotlinx.coroutines.Dispatchers","import kotlinx.coroutines.Dispatchers\nimport kotlinx.coroutines.NonCancellable")
rep(p,"object AndroidHeadlessDailyRunner {","""object AndroidHeadlessDailyRunner {
    data class Outcome(val success:Boolean,val skipped:Boolean,val message:String)""")
rep(p,"        allowedCreators:List<String>,\n        onProgress:","        allowedCreators:List<String>,\n        queueMode:Boolean,\n        onProgress:")
rep(p,"):Boolean {\n        require(allowedCreators.isNotEmpty())\n        val completed=CompletableDeferred<Boolean>()", """):Outcome {
        require(allowedCreators.isNotEmpty())
        val completed=CompletableDeferred<Outcome>()""")
rep(p,'"creators" to allowedCreators','"creators" to allowedCreators,\n                            "queueMode" to queueMode')
rep(p,"                            onProgress(call.argument<String>(\"message\")?.take(200)\n                                ?:if(ok)\"업로드 성공\"else\"영상 제작 실패\")\n                            if(!completed.isCompleted)completed.complete(ok)", """                            val msg=call.argument<String>("message")?.take(200)
                                ?:if(ok)"업로드 성공"else"영상 제작 실패"
                            val skipped=call.argument<Boolean>("skipped")==true
                            onProgress(msg)
                            if(!completed.isCompleted)completed.complete(Outcome(ok,skipped,msg))""")
rep(p,"            } ?: false\n        }catch(_:Exception){\n            return false","""            } ?: Outcome(false,false,"실패: 작업 제한 시간 초과 · 다음 확인 때 재검사")
        }catch(_:Exception){
            return Outcome(false,false,"실패: Android 백그라운드 실행 오류")""")
rep(p,"            withContext(Dispatchers.Main){\n                try{media?.close()}","            withContext(NonCancellable+Dispatchers.Main){\n                try{media?.close()}")

p="native/android/MainActivity.kt"
rep(p,"    override fun onCreate(savedInstanceState: Bundle?) {\n        super.onCreate(savedInstanceState)","""    private var queueUiHeld=false
    private fun holdQueueUi(){if(!queueUiHeld){AndroidDailyScheduler.holdUi();queueUiHeld=true}}
    private fun releaseQueueUi(){if(queueUiHeld){AndroidDailyScheduler.releaseUi();queueUiHeld=false}}
    override fun onCreate(savedInstanceState: Bundle?) {
        holdQueueUi()
        super.onCreate(savedInstanceState)""")
rep(p,'            "dailyScheduleStatus" ->','''            "queueWorkerActive" -> r.success(AndroidDailyScheduler.queueActive())
            "queueReleaseUi" -> {releaseQueueUi();r.success(null)}
            "queueResumeUi" -> {holdQueueUi();r.success(null)}
            "queueStop" -> {AndroidDailyScheduler.disable(applicationContext);r.success(null)}
            "dailyScheduleStatus" ->''')
rep(p,'                    call.argument<Boolean>("rights")==true))','                    call.argument<Boolean>("rights")==true,\n                    call.argument<Boolean>("queueMode")==true))')
rep(p,"worker.shutdown();super.onDestroy()}","worker.shutdown();releaseQueueUi();super.onDestroy()}")

p="lib/main.dart"
rep(p," Future<void> init()async{\n  try{clips=await Native.load();","""  bool queueParked=false,queueWaiting=false;
  Future<void> lifecycle=Future.value();
  Future<void> waitForQueue()async{
   while(mounted&&(await Native.call<bool>('queueWorkerActive')??false)){
    if(!mounted)return;
    if(!queueWaiting)setState(()=>queueWaiting=true);
    await Future<void>.delayed(const Duration(seconds:2));
   }
   if(mounted&&queueWaiting)setState(()=>queueWaiting=false);
  }
  Future<void> init()async{
   try{await waitForQueue();if(!mounted)return;clips=await Native.load();""")
rep(p," @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed&&loaded)scan();}", """ @override void didChangeAppLifecycleState(AppLifecycleState state){
  lifecycle=lifecycle.then((_)async{
   if(!mounted)return;
   if(state==AppLifecycleState.paused&&loaded&&!busy&&!draining&&!scanning&&
       downloader==null&&ModalRoute.of(context)?.isCurrent==true){
    setState(()=>busy=true);
    timer?.cancel();timer=null;queueParked=true;
    await Native.call('queueReleaseUi');
   }else if(state==AppLifecycleState.resumed){
    await Native.call('queueResumeUi');
    if(queueParked){
     queueParked=false;loaded=false;
     await waitForQueue();if(!mounted)return;
     await YouTube.instance.reloadAfterBackground();
     await init();
    }else if(loaded){await scan();}
   }
  }).catchError((Object _){if(mounted)setState(()=>busy=!loaded);});
 }""")
rep(p," @override Widget build(BuildContext context){\n  final shown=",""" @override Widget build(BuildContext context){
  if(queueWaiting)return Scaffold(
    appBar:AppBar(title:const Text('예약 영상 자동 보충 중')),
    body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(
      mainAxisSize:MainAxisSize.min,children:[
        const CircularProgressIndicator(),const SizedBox(height:20),
        const Text('중복 제작·업로드 방지를 위해 백그라운드 작업이 끝나면 앱을 열어요.'),
        TextButton(onPressed:()async{await Native.call('queueStop');},
          child:const Text('자동 보충 중지 및 끄기')),
      ]))),
  );
  final shown=""")

p="native/android/HeadlessDailyMedia.kt"
rep(p,'"lastYoutubeId" to state.optString("lastYoutubeId","")','''"lastYoutubeId" to state.optString("lastYoutubeId",""),
            "pendingSourceId" to state.optString("pendingSourceId",""),
            "queuePendingUri" to state.optString("queuePendingUri",""),
            "queuePendingChannel" to state.optString("queuePendingChannel","")''')
rep(p,'        state.put("pendingSourceId","")\n        saveHistory(state)','''        state.put("pendingSourceId","")
        state.remove("queuePendingUri")
        state.remove("queuePendingChannel")
        saveHistory(state)''')
rep(p,'            "dailyUploadSuccess" -> {','''            "queueSavePending" -> {
                val state=loadHistory()
                val uri=call.argument<String>("uri")?:error("저장 영상 누락")
                val channelId=call.argument<String>("channelId")?:error("채널 누락")
                require(state.optString("pendingSourceId")==call.argument<String>("sourceId"))
                require(Uri.parse(uri).scheme=="content"&&Uri.parse(uri).authority=="media")
                require(Regex("^UC[A-Za-z0-9_-]{22}$").matches(channelId))
                state.put("queuePendingUri",uri)
                state.put("queuePendingChannel",channelId)
                saveHistory(state)
                result.success(null)
            }
            "loadBatchReport" -> async(result){
                val file=File(context.filesDir,"batch-report.json")
                if(file.exists())file.readText()else "{}"
            }
            "dailyUploadSuccess" -> {''')

p="lib/daily_headless_runner.dart"
rep(p,"    bool success=false;\n    String reason=", "    bool success=false,skipped=false,queueMode=false,uploadStarted=false;\n    int uploaded=0,target=1;\n    String reason=")
rep(p,"      final creators=(raw['creators']", "      queueMode=raw['queueMode']==true;\n      target=queueMode?5:1;\n      final creators=(raw['creators']")
rep(p,"      final state=await Native.call<Map<dynamic,dynamic>>('loadDailyHistory')??{};","""      if(queueMode&&youtube.preferences.publishMode!='scheduled'){
        throw const YouTubeFailure('주기별 예약 공개를 먼저 설정해 주세요.');
      }
      final state=await Native.call<Map<dynamic,dynamic>>('loadDailyHistory')??{};
      final clips=await Native.load();
      if(queueMode){
        await step('실제 YouTube 공개 예약 목록 확인');
        final hasScheduled=await youtube.hasScheduledQueue();
        final pendingUri=state['queuePendingUri'] as String? ?? '';
        if(pendingUri.isNotEmpty){
          if(state['queuePendingChannel']!=youtube.preferences.channelId){
            throw const YouTubeFailure('이전 전송 대상 채널이 달라 자동 보충을 중지합니다.');
          }
          final pending=clips.where((c)=>c.savedUri==pendingUri).firstOrNull;
          if(pending==null)throw const YouTubeFailure('이전 자동 업로드의 저장 영상이 없어 확인이 필요합니다.');
          final pendingState=await youtube.state(pendingUri);
          if(pendingState['videoId'] is String){
            await Native.call('dailyUploadSuccess',{
              'sourceId':state['pendingSourceId'],'youtubeVideoId':pendingState['videoId'],
            });
          }else if(!hasScheduled){
            await step('이전 미완료 업로드 확인·이어 올리기');
            uploadStarted=true;
            final id=await youtube.uploadClip(pending);
            if(id.isEmpty)throw const YouTubeFailure('이전 업로드 결과를 확인하지 못했어요.');
            await Native.call('dailyUploadSuccess',{
              'sourceId':state['pendingSourceId'],'youtubeVideoId':id,
            });
            if(!await youtube.verifyScheduledQueue(id)){
              throw const YouTubeFailure('YouTube 예약 등록을 확인하지 못했어요. 추가 업로드를 보류합니다.');
            }
            uploadStarted=false;
            uploaded=1;
          }else{
            skipped=true;success=true;reason='예약 영상 있음 · 이전 미완료 전송은 보류';return;
          }
        }
        if(hasScheduled){
          skipped=true;success=true;reason='YouTube 예약 영상 있음 · 새 제작 건너뜀';return;
        }
        if(uploaded==0){
          youtube.preferences.lastScheduledAtUtc='';
          await youtube.saveSettings();
        }
      }else if((state['queuePendingUri'] as String? ?? '').isNotEmpty){
        throw const YouTubeFailure('이전 자동 보충 업로드 확인이 필요합니다. 자동 보충 모드에서 이어 올려 주세요.');
      }
""")
rep(p,"import 'youtube.dart';","import 'youtube.dart';\nimport 'youtube_upload.dart';")
rep(p,"      final clips=await Native.load();\n      int examined=0;","""      for(final c in clips){
        final id=MixedDiscovery.videoId(c.url);
        if(id!=null)used.add(id);
      }
      if(queueMode){
        final rawReport=await Native.call<String>('loadBatchReport');
        if(rawReport!=null&&rawReport.isNotEmpty){
          final report=jsonDecode(rawReport);
          if(report is Map&&report['items'] is List){
            for(final item in report['items'] as List){
              if(item is Map&&(item['state']=='저장 완료'||item['youtubeVideoId'] is String)){
                final id=MixedDiscovery.videoId(item['url'] as String? ?? '');
                if(id!=null)used.add(id);
              }
            }
          }
        }
      }
      int examined=0;""")
s=get(p)
if s.count("if(success||examined>=maxCandidates)break;")!=3:raise RuntimeError("Unexpected candidate loop")
put(p,s.replace("if(success||examined>=maxCandidates)break;","if(uploaded>=target||examined>=maxCandidates)break;"))
rep(p,"                onStatus:(message){},\n              );\n              if(!draft.quality.acceptable","                onStatus:(message){unawaited(step(message));},\n              );\n              if(!draft.quality.acceptable")
rep(p,"              await step('확인된 YouTube 채널로 완성 MP4 업로드');\n              final videoId=await youtube.uploadClip(current);","""              await step('확인된 YouTube 채널로 완성 MP4 업로드');
              if(queueMode){
                if(uploaded==0&&await youtube.hasScheduledQueue()){
                  skipped=true;success=true;
                  reason='다른 예약 영상이 등록됨 · 추가 업로드 보류';return;
                }
                await Native.call('queueSavePending',{
                  'uri':current.savedUri,'sourceId':id,'channelId':youtube.preferences.channelId,
                });
              }
              uploadStarted=true;
              final videoId=await youtube.uploadClip(current);""")
rep(p,"              success=true;\n              reason='영상 1개 업로드 접수 · YouTube ID $videoId';\n              break;\n            }catch(_){\n              await step('검증 또는 제작 실패 · 후보 제외');","""              if(queueMode&&!await youtube.verifyScheduledQueue(videoId)){
                throw const YouTubeFailure('YouTube 예약 등록을 확인하지 못했어요. 추가 업로드를 보류합니다.');
              }
              uploadStarted=false;
              uploaded++;success=true;
              reason='영상 $uploaded개 예약 업로드 접수';
              if(uploaded>=target)break;
            }catch(e){
              if(uploadStarted){
                reason='업로드 결과 확인 필요 · 추가 업로드 중단: '+(e is YouTubeFailure?e.message:'전송 오류');
                return;
              }
              if(e is YouTubeFailure){
                reason=e.message;return;
              }
              await step('검증 또는 제작 실패 · 후보 제외');""")
rep(p,"      if(!success)reason='검증을 통과한 새 영상이 없거나 업로드에 실패했습니다.';\n    }catch(e){\n      reason='예약 작업 설정·연결 또는 백그라운드 환경 오류';","""      success=uploaded>0;
      if(!success)reason='검증을 통과한 새 영상이 없거나 업로드에 실패했습니다.';
      else reason=queueMode?'예약 자동 보충 $uploaded/$target개 접수 확인':'영상 1개 업로드 접수 확인';
    }catch(e){
      reason=e is YouTubeFailure?e.message:'예약 작업 설정·연결 또는 백그라운드 환경 오류';""")
rep(p,"          'success':success,'message':reason,","          'success':success&&!uploadStarted,'skipped':skipped,'message':reason,")

version=get("pubspec.yaml")
match=re.search(r"(?m)^version: 0\.21\.(\d+)\+(\d+)[ \t]*$",version)
if not match:raise RuntimeError("Unexpected app version")
new_version=f"version: 0.21.{int(match[1])+1}+{int(match[2])+1}"
put("pubspec.yaml",version.replace(match[0],new_version,1))
adds={
    "lib/youtube_scheduled_queue.dart":Path("tool/youtube_scheduled_queue.dart").read_bytes(),
    "test/youtube_scheduled_queue_test.dart":Path("tool/youtube_scheduled_queue_test.dart").read_bytes(),
}
if any(p in files for p in adds):raise RuntimeError("Queue code already exists")
with ZipFile(tmp,"w") as z:
    for i,b in entries:z.writestr(i,updates.get(i.filename,b))
    for p,b in adds.items():z.writestr(p,b)
os.replace(tmp,src)
print("Packaged",new_version,"Android scheduled queue automatic refill")
