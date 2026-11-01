#!/usr/bin/env python3
"""Stage 1: YouTube stream -> video-only temporary mp4 -> existing six-frame Vision."""
from zipfile import ZipFile
from pathlib import Path
import os
src=Path('shorts-studio-source.zip')
tmp=Path('shorts-studio-source.stream.zip')
with ZipFile(src) as z:items=[(info,z.read(info)) for info in z.infolist()]
data={info.filename:raw for info,raw in items}
updated={}
def exact(path,old,new):
    content=updated.get(path,data[path].decode('utf-8'))
    n=content.count(old)
    if n!=1:raise RuntimeError(f'{path}: expected 1 anchor, got {n}: {old[:105]!r}')
    updated[path]=content.replace(old,new,1)
def from_tool(path,tool):
    if path not in data:raise RuntimeError(f'Existing source absent: {path}')
    updated[path]=Path(tool).read_text(encoding='utf-8')

if 'lib/benchmark_stream.dart' in data:raise RuntimeError('Stage 1 stream module already applied.')
for target,tool in [('lib/benchmark_ui.dart','tool/benchmark_ui.dart'),
                    ('test/benchmark_test.dart','tool/benchmark_tests.dart'),
                    ('native/android/BenchmarkFrameExtractor.kt','tool/BenchmarkFrameExtractor.kt')]:
    from_tool(target,tool)
updated['lib/benchmark_stream.dart']=Path('tool/benchmark_stream.dart').read_text(encoding='utf-8')
native='native/android/MainActivity.kt'
anchor='            "benchmarkPickFrames" -> {'
insert='''            "benchmarkStreamCachePath" -> {
                val id=call.argument<String>("id")?:""
                require(Regex("^[A-Za-z0-9_-]{11}$").matches(id)){"YouTube ID 형식 오류"}
                val dir=File(cacheDir,"benchmark-streams")
                check(dir.exists()||dir.mkdirs()){"임시 스트림 저장 공간 준비 실패"}
                r.success(File(dir,"$id.mp4").absolutePath)
            }
            "benchmarkExtractFramesFromCache" -> async(r) {
                val id=call.argument<String>("id")?:""
                require(Regex("^[A-Za-z0-9_-]{11}$").matches(id)){"YouTube ID 형식 오류"}
                val dir=File(cacheDir,"benchmark-streams")
                val source=File(dir,"$id.mp4")
                require(source.canonicalFile.parentFile==dir.canonicalFile)
                BenchmarkFrameExtractor.extractFile(source)
            }
'''
exact(native,anchor,insert+anchor)
pub='pubspec.yaml'
exact(pub,'version: 0.20.2+55','version: 0.20.3+56')
exact(pub,'dependencies:\n','dependencies:\n  youtube_explode_dart: ^3.1.0\n')
with ZipFile(tmp,'w') as z:
    for info,raw in items:
        body=updated.pop(info.filename,None)
        z.writestr(info,body.encode('utf-8') if body is not None else raw)
    for name,body in updated.items():
        if name!='lib/benchmark_stream.dart':raise RuntimeError('Unexpected new source file')
        z.writestr(name,body.encode('utf-8'))
os.replace(tmp,src)
print('Stage1 stream + frames integrated: 0.20.3+56. No subtitle classifier changes.')
