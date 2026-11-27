#!/usr/bin/env python3
"""Patch Android Gemini HTTP transport; preserve prompts, models and upload schedules."""
from pathlib import Path
from zipfile import ZipFile
import os,re

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".gemini-retry.tmp")
with ZipFile(src) as z:
    entries=[(i,z.read(i)) for i in z.infolist()]
files={i.filename:b for i,b in entries}
path="lib/ai.dart"
s=files[path].decode()
def replace(old,new):
    global s
    if s.count(old)!=1:
        raise RuntimeError(f"Unexpected AI anchor {old[:90]} ({s.count(old)})")
    s=s.replace(old,new,1)

replace("import 'ai_rules.dart';","import 'ai_rules.dart';\nimport 'gemini_retry.dart';")
replace("class AiDraft {", """class GeminiHttpFailure extends AiFailure {
 const GeminiHttpFailure(this.status,String message)
   : super(message,retryable:status>=500);
 final int status;
}
class AiDraft {""")
start=s.index(" bool _cancelled=false;")
end=s.index(" Future<Map<String,dynamic>> jsonResponse",start)
old=s[start:end]
if "await response.drain<void>()" not in old or "Future<HttpClientResponse> request(" not in old:
    raise RuntimeError("Unexpected Gemini transport")
new=""" bool _cancelled=false,_expired=false;
 final _stopped=Completer<void>();
 String _model='',_requestStage='AI_REQUEST';
 void Function(String)? _onStatus;
 void _stop(){if(!_stopped.isCompleted)_stopped.complete();_client.close(force:true);}
 void cancel(){_cancelled=true;_stop();}
 void _expire(){_expired=true;_stop();}
 void check(){
  if(_cancelled)throw const AiFailure('생성을 취소했어요.');
  if(_expired)throw const AiFailure('AI 작업 제한 시간을 넘겼어요. [AI_TIMEOUT]',retryable:true);
 }
 Future<void> _wait(Duration delay)async{
  final timerDone=Completer<void>();
  final timer=Timer(delay,()=>timerDone.complete());
  try{await Future.any<void>([timerDone.future,_stopped.future]);check();}
  finally{timer.cancel();}
 }
 static Uri endpoint(String path)=>Uri.https('generativelanguage.googleapis.com',path);
 Future<String> _errorBody(HttpClientResponse response)async{
  final bytes=<int>[];
  try{
   await for(final chunk in response.timeout(const Duration(seconds:5))){
    final remaining=8192-bytes.length;
    if(remaining<=0)break;
    bytes.addAll(chunk.take(remaining));
    if(bytes.length>=8192)break;
   }
  }catch(_){}
  return utf8.decode(bytes,allowMalformed:true);
 }
 Future<HttpClientResponse> request(String method,Uri uri,String key,{Map<String,String> headers=const {},Object? body,File? file})async{
  // A generateContent retry keeps the exact same uploaded file URI/body.
  // A GET is safe to replay. Never blindly repeat upload/start/finalize.
  final replay=method=='GET'||(method=='POST'&&file==null&&
      uri.host=='generativelanguage.googleapis.com'&&
      uri.path.endsWith(':generateContent'));
  final stage=_requestStage;
  final model=GeminiRetry.safeModel(_model);
  return GeminiRetry.run<HttpClientResponse>(
   safeToReplay:replay,check:check,wait:_wait,
   is503:(error)=>error is GeminiHttpFailure&&error.status==503,
   onRetry:(retry,delay)=>_onStatus?.call(
    'Gemini HTTP 503 · $stage · $model · DOLLAR{delay.inSeconds}초 후 재시도 ($retry/3)'),
   send:(attempt)async{
    check();
    final watch=Stopwatch()..start();
    final req=await _client.openUrl(method,uri);req.followRedirects=false;
    req.headers.set('x-goog-api-key',key);
    headers.forEach(req.headers.set);
    if(file!=null){req.contentLength=await file.length();await req.addStream(file.openRead());}
    else if(body!=null){req.headers.contentType=ContentType.json;req.write(jsonEncode(body));}
    final response=await req.close();
    if(response.statusCode<200||response.statusCode>=300){
     final status=response.statusCode;
     final detail=GeminiRetry.safeServerDetail(await _errorBody(response));
     final hint=switch(status){
      401||403=>'API 키 또는 Gemini API 권한을 확인해 주세요.',
      429=>'요청 속도 또는 사용량 한도를 확인해 주세요.',
      404=>'AI 설정의 모델 이름과 사용 권한을 확인해 주세요.',
      503=>replay?'서버 일시 오류':'파일 전송 결과 불확실 · 같은 요청 자동 재전송 안 함',
      _=>'Gemini 요청 실패',
     };
     throw GeminiHttpFailure(status,
      'Gemini API · HTTP $status [GEMINI_HTTP_$status] · $hint · '
      '모델 $model · 단계 $stage · 시도 $attempt · '
      'DOLLAR{watch.elapsedMilliseconds}ms · $detail');
    }
    return response;
   },
  );
 }
"""
new=new.replace("DOLLAR",chr(36))
s=s[:start]+new+s[end:]
replace("  String issue='';","  _model=model;_onStatus=onStatus;_requestStage='AI_TITLE_REPAIR';\n  String issue='';")
replace("  final deadline=Timer(const Duration(seconds:90),()=>cancel());",
        "  _model=model;_onStatus=onStatus;_requestStage='AI_REGENERATE';\n  final deadline=Timer(const Duration(seconds:90),_expire);")
replace("   onStatus('저장된 장면 정보로 자막만 재생성 · 영상 업로드 없음');",
        "   _requestStage='AI_CAPTION_REGENERATE';\n   onStatus('저장된 장면 정보로 자막만 재생성 · 영상 업로드 없음');")
replace("  String? remoteName;\n  var stage='AI_FILE';var timedOut=false;",
        "  _model=model;_onStatus=onStatus;\n  String? remoteName;\n  var stage='AI_FILE';var timedOut=false;")
replace("final deadline=Timer(const Duration(minutes:4),(){timedOut=true;_client.close(force:true);});",
        "final deadline=Timer(const Duration(minutes:4),(){timedOut=true;_expire();});")
for stage in ("AI_UPLOAD_START","AI_UPLOAD","AI_PROCESSING","AI_GENERATE"):
    replace(f"stage='{stage}';",f"stage='{stage}';_requestStage=stage;")
version=files["pubspec.yaml"].decode()
match=re.search(r"(?m)^version: 0\.21\.(\d+)\+(\d+)[ \t]*$",version)
if not match:raise RuntimeError("Unknown app version")
new_version=f"version: 0.21.{int(match[1])+1}+{int(match[2])+1}"
updates={path:s.encode(),"pubspec.yaml":version.replace(match[0],new_version,1).encode()}
additions={
    "lib/gemini_retry.dart":Path("tool/gemini_retry.dart").read_bytes(),
    "test/gemini_retry_test.dart":Path("tool/gemini_retry_test.dart").read_bytes(),
}
if any(p in files for p in additions):raise RuntimeError("Retry code already exists")
with ZipFile(tmp,"w") as z:
    for i,b in entries:z.writestr(i,updates.get(i.filename,b))
    for p,b in additions.items():z.writestr(p,b)
os.replace(tmp,src)
print("Packaged",new_version,"Gemini 503 retry and safe diagnostics")
