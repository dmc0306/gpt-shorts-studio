#!/usr/bin/env python3
"""Install benchmark discovery in the versioned ZIP with exact-match guards."""
from pathlib import Path
from zipfile import ZipFile
import re,os
zip_path=Path('shorts-studio-source.zip');out=zip_path.with_suffix('.benchmark.zip')
with ZipFile(zip_path) as zin: entries=[(i,zin.read(i)) for i in zin.infolist()]
base={i.filename:b for i,b in entries};updates={}
# On subsequent runs refresh only the new feature files; keep core native/editor intact.
if 'lib/benchmark_data.dart' in base:
    for name,source in [('lib/benchmark_data.dart','tool/benchmark_data.dart'),
                        ('lib/benchmark_ui.dart','tool/benchmark_ui.dart'),
                        ('test/benchmark_test.dart','tool/benchmark_tests.dart')]:
        updates[name]=Path(source).read_text(encoding='utf-8')
    ver=base['pubspec.yaml'].decode('utf-8')
    if 'version: 0.20.0+53' in ver:
        updates['pubspec.yaml']=ver.replace('version: 0.20.0+53','version: 0.20.1+54',1)
    with ZipFile(out,'w') as zout:
        for info,content in entries:
            changed=updates.get(info.filename)
            zout.writestr(info,changed.encode('utf-8') if changed is not None else content)
    os.replace(out,zip_path)
    print('Refreshed benchmark sources and regression tests.')
    raise SystemExit(0)
def edit(path,old,new):
 s=updates.get(path,base[path].decode('utf-8'))
 count=s.count(old)
 if count!=1:raise RuntimeError(f'Expected 1 location in {path}, found {count}: {old[:110]}')
 updates[path]=s.replace(old,new,1)
for filename,source in [('lib/benchmark_data.dart','tool/benchmark_data.dart'),
                        ('lib/benchmark_ui.dart','tool/benchmark_ui.dart'),
                        ('test/benchmark_test.dart','tool/benchmark_tests.dart')]:
 if filename in base:raise RuntimeError('Refusing overwrite '+filename)
 updates[filename]=Path(source).read_text(encoding='utf-8')
main='lib/main.dart'
edit(main,"import 'tiktok_download.dart';","import 'tiktok_download.dart';\nimport 'benchmark_ui.dart';")
edit(main,"Future<void> settings()async{","""  Future<void> benchmark() async {
    if(busy||downloader!=null)return;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>BenchmarkScreen(
      clips:clips,onSave:()=>Native.save(clips))));
    if(mounted)setState((){});
  }
  Future<void> settings()async{""")
edit(main,
     "actions:[IconButton(tooltip:'유튜브 채널 설정',",
     "actions:[IconButton(tooltip:'벤치마킹 소재 탐색',onPressed:busy?null:benchmark,icon:const Icon(Icons.insights_outlined)),IconButton(tooltip:'유튜브 채널 설정',")
editor='lib/editor.dart'
edit(editor,"const EditorScreen({super.key,required this.clip,required this.onSave});",
     "  const EditorScreen({super.key,required this.clip,required this.onSave,this.autoGenerateOnOpen=false});")
edit(editor,"final Clip clip; final Future<void> Function() onSave;",
     "  final Clip clip; final Future<void> Function() onSave;\n  final bool autoGenerateOnOpen;")
edit(editor,
     "player.addListener(tick);if(mounted)setState(()=>ready=true);",
     """player.addListener(tick);if(mounted){setState(()=>ready=true);
       if(widget.autoGenerateOnOpen)WidgetsBinding.instance.addPostFrameCallback((_) {
         if(mounted)generateAi();
       });
     }""")
native='native/android/MainActivity.kt'
edit(native,
     '"loadAiSettings" -> async(r)',
     '''            "benchmarkApiKey" -> r.success(readAiKey("youtubeBenchmark"))
            "saveBenchmarkApiKey" -> {
                val key=call.argument<String>("key")?:""
                require(key.length<=256){"YouTube Data API 키가 너무 길어요."}
                saveAiKey(key,"youtubeBenchmark")
                check(prefs.edit().commit())
                r.success(null)
            }
            "loadBenchmarkState" -> async(r) {
                val f=File(filesDir,"benchmark-state.json")
                if(f.exists())f.readText() else "{}"
            }
            "saveBenchmarkState" -> async(r) {
                val data=call.argument<String>("json")!!
                require(data.toByteArray(Charsets.UTF_8).size<=2_000_000){"벤치마킹 기록 한도를 초과했어요."}
                JSONObject(data)
                atomicWrite(File(filesDir,"benchmark-state.json"),data)
                null
            }
            "openBenchmarkLink" -> {
                val uri=Uri.parse(call.argument<String>("url")!!)
                val host=uri.host?.lowercase()?:""
                require(uri.scheme=="https"&&uri.userInfo==null&&(uri.port==-1||uri.port==443))
                require(listOf("youtube.com","youtu.be","tiktok.com","instagram.com").any{
                    host==it||host.endsWith("."+it)
                }){"허용되지 않은 링크예요."}
                startActivity(Intent(Intent.ACTION_VIEW,uri).addCategory(Intent.CATEGORY_BROWSABLE))
                r.success(null)
            }
            "loadAiSettings" -> async(r)''')
ver='pubspec.yaml'
original=base[ver].decode('utf-8')
m=re.search(r'(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)$',original)
if not m:raise RuntimeError('Missing version')
edit(ver,m.group(0),'version: 0.20.0+53')
with ZipFile(out,'w') as zout:
 for info,content in entries:
  changed=updates.pop(info.filename,None)
  zout.writestr(info,changed.encode('utf-8') if changed is not None else content)
 for path,s in updates.items():zout.writestr(path,s.encode('utf-8'))
os.replace(out,zip_path)
print('Applied ranking, original search, rights gate, editor pipeline and tests.')
