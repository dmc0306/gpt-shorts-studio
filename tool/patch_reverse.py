#!/usr/bin/env python3
"""Replace benchmark text-search and authorization form with video-frame reverse image search."""
from pathlib import Path
from zipfile import ZipFile
import os,re

archive=Path('shorts-studio-source.zip')
target=archive.with_suffix('.vision.zip')
with ZipFile(archive) as z: entries=[(i,z.read(i)) for i in z.infolist()]
files={i.filename:b for i,b in entries}
updates={}
def original(path):
    return updates.get(path,files[path].decode('utf-8'))
def change(path,a,b):
    s=original(path)
    n=s.count(a)
    if n!=1:
        # Existing source often uses two-space indentation; tolerate only a
        # unique exact match after stripping the first line's left padding.
        stripped=a.lstrip(' ')
        if stripped!=a and s.count(stripped)==1:
            a=stripped
            n=1
    if n!=1:
        # Match exact text across legacy indentation variants, once only.
        pattern=r'[ \t]*'+r'[ \t]*\n[ \t]*'.join(re.escape(line.strip()) for line in a.splitlines())
        hits=list(re.finditer(pattern,s))
        if len(hits)==1:
            m=hits[0]
            updates[path]=s[:m.start()]+b+s[m.end():]
            return
    if n!=1:raise RuntimeError(f'{path}: expected one anchor, got {n}: {a[:90]!r}')
    updates[path]=s.replace(a,b,1)

# Update only the live source ZIP and the canonical editable files in tool/.
for path,tool in [('lib/benchmark_ui.dart','tool/benchmark_ui.dart'),
                   ('lib/benchmark_data.dart','tool/benchmark_data.dart'),
                   ('test/benchmark_test.dart','tool/benchmark_tests.dart')]:
    # Files are patched independently here; modifications to tool files are committed as well.
    updates[path]=Path(tool).read_text(encoding='utf-8')

data='lib/benchmark_data.dart'
s=original(data)
marker='class BenchFinder {'
if s.count(marker)!=1:raise RuntimeError('Previous text-only finder not found')
updates[data]=s.split(marker)[0].rstrip()+'\n'

ui='lib/benchmark_ui.dart'
change(ui,"import 'tiktok_download.dart';",
   "import 'tiktok_download.dart';\nimport 'vision_reverse.dart';")
change(ui,
   " final keyText=TextEditingController(),channelText=TextEditingController(),originText=TextEditingController();",
   " final keyText=TextEditingController(),visionKeyText=TextEditingController(),channelText=TextEditingController(),originText=TextEditingController();")
change(ui," String tavily='',message='';"," String message='';")
change(ui," @override void dispose(){keyText.dispose();channelText.dispose();originText.dispose();super.dispose();}",
   " @override void dispose(){keyText.dispose();visionKeyText.dispose();channelText.dispose();originText.dispose();super.dispose();}")
change(ui,
   """   final settings=await Native.call<Map<dynamic,dynamic>>('loadAiSettings')??{};
   tavily=settings['searchKey'] as String? ?? '';""",
   """   visionKeyText.text=await Native.call<String>('benchmarkVisionKey')??'';
   // Expire the previous text-search origin suggestions; keep user-added links.
   for(final id in state.origins.keys.toList()){
     state.origins[id]=state.origins[id]!.where((c)=>
       c.source=='프레임 역이미지 검색'||c.source=='직접 추가').toList();
     if(!state.origins[id]!.any((c)=>c.url==state.chosen[id]))state.chosen.remove(id);
   }""")
old=original(ui)
start=old.index(' Future<void> search(BenchVideo v)')
end=old.index(' Future<void> addOrigin(BenchVideo v)',start)
repl=""" Future<void> search(BenchVideo v)async{
  if(busy)return;
  if(visionKeyText.text.trim().isEmpty && keyText.text.trim().isEmpty){
    report('Cloud Vision API 키를 먼저 입력하세요. YouTube 키도 Vision API를 허용한다면 재사용할 수 있어요.');
    return;
  }
  List<dynamic>? frames;
  try{
    frames=await Native.call<List<dynamic>>('benchmarkPickFrames');
  }catch(e){report('벤치마킹 영상 파일에서 장면을 추출하지 못했어요: $e');return;}
  if(frames==null){report('영상 파일 선택을 취소했어요.');return;}
  await run(()async{
   report('${v.title} · 실제 영상 프레임 ${frames!.length}장 이미지 검색 중');
   final key=visionKeyText.text.trim().isNotEmpty?visionKeyText.text.trim():keyText.text.trim();
   final service=FrameReverseSearch(key);
   try{
     final candidates=await service.find(v.id,frames!);
     state.origins[v.id]=candidates;
     state.chosen.remove(v.id);
     report(candidates.isEmpty
      ?'영상 장면과 일치하는 소셜 영상 페이지를 찾지 못했어요. 다른 프레임이 포함된 영상을 선택해 재검색할 수 있어요.'
      :'서로 다른 프레임의 중복 일치 순으로 원본 후보 ${candidates.length}개를 찾았어요.');
   }finally{service.close();}
  });
 }
"""
updates[ui]=old[:start]+repl+old[end:]
change(ui,
   "   final url=state.chosen[v.id],right=state.rights[v.id],proof=state.proof[v.id]?.trim()??'';\n   if(url==null||right==null||proof.length<8){report('원본 주소·사용 권한 유형·근거를 확인해 주세요.');return;}",
   "   final url=state.chosen[v.id];\n   if(url==null){report('먼저 사용할 원본 게시물을 선택해 주세요.');return;}")
change(ui,"       const Text('본인이 확인한 재사용 권한이 있는 원본만 가져오세요. 출처 표기만으로 허가되지 않습니다.'),",
   "       const Text('원본 후보를 선택한 다음 기기에 보유한 파일 또는 TikTok 영상을 연결하세요.'),")
change(ui,"child:const Text('권한 확인한 TikTok 영상 가져오기')",
   "child:const Text('TikTok 영상 가져오기')")
change(ui,
   "       'originalUrl':url,'rights':right,'rightsEvidence':proof});",
   "       'originalUrl':url});")
change(ui,
   "   final list=state.origins[v.id]??[],selected=state.chosen[v.id],kind=state.rights[v.id]??'';\n   final canCreate=selected!=null&&kind.isNotEmpty&&(state.proof[v.id]?.trim().length??0)>=8&&!busy;",
   "   final list=state.origins[v.id]??[],selected=state.chosen[v.id];\n   final canCreate=selected!=null&&!busy;")
change(ui,
   "OutlinedButton(onPressed:busy?null:()=>search(v),child:const Text('원본 후보 검색')),",
   "OutlinedButton(onPressed:busy?null:()=>search(v),child:const Text('주요 장면 역이미지 검색')),")
change(ui,"     if(list.isEmpty)const Text('원본 후보 미확인 · 제작 불가',style:TextStyle(fontSize:12)),",
    "     if(list.isEmpty)const Text('주요 장면 이미지 검색 결과 없음',style:TextStyle(fontSize:12)),")
old=original(ui)
a=old.index("DropdownButtonFormField<String>(key:ValueKey('rights:")
a=old.rfind("\n",0,a)+1
b=old.index("const SizedBox(height:8),",a)
b=old.rfind("\n",0,b)+1
updates[ui]=old[:a]+old[b:]
change(ui,"label:const Text('권한 확인 원본 → 템플릿 제작')",
   "label:const Text('선택한 원본 → 템플릿 제작')")
change(ui,"const Text('채널별 조회수 상위 50개 → 랜덤 선정 → 원본 탐색 → 기존 템플릿'",
   "const Text('채널별 상위 50개 → 랜덤 선정 → 주요 장면 역이미지 검색 → 기존 템플릿'")
change(ui,
   "     const Text('검색 후보는 원제작자와 일치한다고 보장하지 않아요. 직접 확인하고 재사용 권한이 있는 경우만 제작하세요.',",
   "     const Text('여러 이미지에서 일치한 페이지를 우선 표시해요. 후보가 최초 제작자라고 확정되는 것은 아니에요.',")
change(ui,
   "      }),child:const Text('API 키 저장')),\n    Text('채널",
   """      }),child:const Text('API 키 저장')),
    const SizedBox(height:8),
    TextField(controller:visionKeyText,obscureText:true,enableSuggestions:false,autocorrect:false,
      decoration:const InputDecoration(labelText:'Cloud Vision Web Detection API 키',
        helperText:'Cloud Vision API 활성화 필요 · 빈칸이면 YouTube API 키 사용')),
    TextButton(onPressed:busy?null:()=>run(()async{
       await Native.call('saveBenchmarkVisionKey',{'key':visionKeyText.text.trim()});
       report('Vision 검색 키를 암호화 저장했어요.');
     }),child:const Text('Vision API 키 저장')),
    const Text('실제 영상의 주요 장면 검색을 위해 영상 파일 선택이 필요합니다. 제목·설명란·Tavily 검색은 사용하지 않아요.',
      style:TextStyle(fontSize:12)),
    Text('채널""")

tests='test/benchmark_test.dart'
change(tests,"import 'package:shorts_studio/benchmark_data.dart';",
  "import 'package:shorts_studio/benchmark_data.dart';\nimport 'package:shorts_studio/vision_reverse.dart';")
old=original(tests)
a=old.index(" test('Description credit is only a candidate")
b=old.rfind("\n}")
if a<0 or b<=a:raise RuntimeError("Original description test missing")
newTests="""
 test('Frames matching the same original rank higher, benchmark itself excluded',(){
   final matches=FrameReverseSearch.rank([
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.tiktok.com/@original/video/123456','score':.8},
       {'url':'https://www.youtube.com/watch?v=benchmark'}]}},
     {'webDetection':{'pagesWithMatchingImages':[
       {'url':'https://www.tiktok.com/@original/video/123456','score':.2},
       {'url':'https://www.tiktok.com/@other/video/345','score':1.0}]}}
   ],'benchmark');
   expect(matches.length,2);
   expect(matches.first.url,contains('original'));
   expect(matches.first.evidence,contains('2장'));
 });
 test('Vision sends only images without title, description or Tavily',()async{
   final client=MockClient((request)async{
     expect(request.url.host,'vision.googleapis.com');
     expect(request.url.queryParameters['key'],'vision-key');
     final data=jsonDecode(request.body) as Map;
     expect(data.keys.toList(),['requests']);
     final requests=data['requests'] as List;
     expect(requests.length,2);
     expect(jsonEncode(requests),contains('WEB_DETECTION'));
     expect(jsonEncode(requests),isNot(contains('Tavily')));
     return http.Response(jsonEncode({'responses':[
       {'webDetection':{'pagesWithMatchingImages':[{'url':'https://www.youtube.com/shorts/AbCdEfGhijk'}]}},
       {'webDetection':{'pagesWithMatchingImages':[{'url':'https://www.youtube.com/shorts/AbCdEfGhijk'}]}}
     ]}),200);
   });
   final engine=FrameReverseSearch('vision-key',client:client);
   final results=await engine.find('reference',[{'content':'A'*150},{'content':'B'*150}]);
   expect(results.single.evidence,contains('2장'));
   engine.close();
 });
"""
updates[tests]=old[:a]+newTests+old[b:]

main='native/android/MainActivity.kt'
change(main,
   '            "benchmarkApiKey" -> r.success(readAiKey("youtubeBenchmark"))',
   '''            "benchmarkVisionKey" -> r.success(readAiKey("youtubeBenchmarkVision"))
            "saveBenchmarkVisionKey" -> {
                val key=call.argument<String>("key")?:""
                require(key.length<=256){"Vision API 키가 너무 길어요."}
                saveAiKey(key,"youtubeBenchmarkVision")
                check(prefs.edit().commit())
                r.success(null)
            }
            "benchmarkPickFrames" -> {
                check(pickerResult==null){"다른 영상 선택이 진행 중이에요."}
                pickerResult=r
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply{
                    type="video/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },12)
            }
            "benchmarkApiKey" -> r.success(readAiKey("youtubeBenchmark"))''')
change(main,
   'if(requestCode!=10&&requestCode!=11)return',
   'if(requestCode!=10&&requestCode!=11&&requestCode!=12)return')
change(main,
   'if(requestCode==10)async(r){importUri(uri)}',
   'if(requestCode==12)async(r){BenchmarkFrameExtractor.extract(this,uri)}\n        else if(requestCode==10)async(r){importUri(uri)}')

bootstrap='tool/bootstrap.py'
change(bootstrap,
   "('YouTubeRedirectTraceActivity.kt','src/main/kotlin/com/local/shorts_studio/YouTubeRedirectTraceActivity.kt'),",
   "('BenchmarkFrameExtractor.kt','src/main/kotlin/com/local/shorts_studio/BenchmarkFrameExtractor.kt'),('YouTubeRedirectTraceActivity.kt','src/main/kotlin/com/local/shorts_studio/YouTubeRedirectTraceActivity.kt'),")

updates['native/android/BenchmarkFrameExtractor.kt']=Path('tool/BenchmarkFrameExtractor.kt').read_text(encoding='utf-8')
updates['lib/vision_reverse.dart']=Path('tool/vision_reverse.dart').read_text(encoding='utf-8')
if updates.keys()&set([]):pass
# Increment version without modifying existing channel rank cache.
version='pubspec.yaml'
change(version,'version: 0.20.1+54','version: 0.20.2+55')
with ZipFile(target,'w') as z:
    for item,content in entries:
        altered=updates.get(item.filename)
        z.writestr(item,altered.encode('utf-8') if altered is not None else content)
    for p in ('native/android/BenchmarkFrameExtractor.kt','lib/vision_reverse.dart'):
        if p in files:raise RuntimeError('Refusing to replace an existing new file '+p)
        z.writestr(p,updates[p].encode('utf-8'))
os.replace(target,archive)
# Keep the canonical edit sources in GitHub consistent with the app archive.
Path('tool/benchmark_ui.dart').write_text(updates[ui],encoding='utf-8')
Path('tool/benchmark_data.dart').write_text(updates[data],encoding='utf-8')
Path('tool/benchmark_tests.dart').write_text(updates[tests],encoding='utf-8')
print('Updated: Android reference frame picker, Vision multi-frame image match, UI, tests, removed permission gate.')
