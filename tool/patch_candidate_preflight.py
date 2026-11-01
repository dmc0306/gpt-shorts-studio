#!/usr/bin/env python3
"""Reduce unverifiable repeated YouTube downloads; expose thumbnail evidence and links."""
from zipfile import ZipFile
from pathlib import Path
import os,re
source=Path("shorts-studio-source.zip")
output=source.with_suffix(".candidate-preflight.zip")
with ZipFile(source) as zipfile:
    entries=[(item,zipfile.read(item)) for item in zipfile.infolist()]
data={item.filename:content for item,content in entries}
version=data['pubspec.yaml'].decode('utf-8')
if version.count('version: 0.21.3+62')!=1:
    raise RuntimeError("Unexpected version; expected 0.21.3+62, found "+version[:160])
changes={
'pubspec.yaml':version.replace('version: 0.21.3+62','version: 0.21.4+63').encode('utf8'),
'lib/benchmark_oneclick.dart':Path('tool/benchmark_oneclick.dart').read_bytes(),
'lib/benchmark_ui.dart':Path('tool/benchmark_ui.dart').read_bytes(),
'native/android/BenchmarkFrameExtractor.kt':Path('tool/BenchmarkFrameExtractor.kt').read_bytes(),
'test/benchmark_test.dart':Path('tool/benchmark_tests.dart').read_bytes(),
}
for name in changes:
    if name not in data:raise RuntimeError('Missing source: '+name)
native='native/android/MainActivity.kt'
code=data[native].decode('utf8')
anchor='            "benchmarkInspectCandidate" -> async(r) {'
if code.count(anchor)!=1:raise RuntimeError('Native candidate channel not present or ambiguous')
handler='''            "benchmarkFingerprintImage" -> async(r) {
                val encoded=call.argument<String>("content")?:""
                require(encoded.length in 170..1400000){"썸네일 전송 데이터 크기 오류"}
                val bytes=android.util.Base64.decode(encoded,android.util.Base64.DEFAULT)
                BenchmarkFrameExtractor.fingerprintJpeg(bytes)
            }
'''
changes[native]=code.replace(anchor,handler+anchor,1).encode('utf8')
assert b'CandidateThumbnail' in changes['lib/benchmark_oneclick.dart']
assert b'후보 게시물 열어보기' in changes['lib/benchmark_ui.dart']
assert b'fingerprintJpeg' in changes['native/android/BenchmarkFrameExtractor.kt']
with ZipFile(output,'w') as z:
    for info,content in entries:
        z.writestr(info,changes.get(info.filename,content))
os.replace(output,source)
print("v0.21.4+63 · Quick YouTube image evidence, failure circuit breaker, and clickable candidate links installed")
