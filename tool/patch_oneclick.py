#!/usr/bin/env python3
"""Install one-click media evidence verification in the versioned Android/Flutter ZIP."""
from pathlib import Path
from zipfile import ZipFile
import os

path=Path("shorts-studio-source.zip")
out=path.with_suffix(".oneclick.zip")
with ZipFile(path) as z:entries=[(x,z.read(x)) for x in z.infolist()]
old={x.filename:b for x,b in entries}
ver=old["pubspec.yaml"].decode()
assert ver.count("version: 0.20.5+58")==1,ver[:150]
changed={
"pubspec.yaml":ver.replace("version: 0.20.5+58","version: 0.21.0+59"),
"lib/benchmark_ui.dart":Path("tool/benchmark_ui.dart").read_text(),
"lib/vision_reverse.dart":Path("tool/vision_reverse.dart").read_text(),
"lib/benchmark_oneclick.dart":Path("tool/benchmark_oneclick.dart").read_text(),
"native/android/BenchmarkFrameExtractor.kt":Path("tool/BenchmarkFrameExtractor.kt").read_text(),
"test/benchmark_test.dart":Path("tool/benchmark_tests.dart").read_text(),
}

native="native/android/MainActivity.kt"
main=old[native].decode()
anchor='            "benchmarkExtractFramesFromCache" -> async(r) {'
assert main.count(anchor)==1
added='''            "benchmarkInspectCandidate" -> async(r) {
                val file=File(call.argument<String>("path")!!).canonicalFile
                val sourceDir=File(filesDir,"sources").canonicalFile
                val streamDir=File(cacheDir,"benchmark-streams").canonicalFile
                require(file.parentFile==sourceDir||file.parentFile==streamDir) {
                    "앱 내부 후보 영상만 분석할 수 있어요."
                }
                require(file.name.endsWith(".mp4",true)&&file.isFile){"후보 영상 파일이 없어요."}
                val hashes=BenchmarkFrameExtractor.fingerprints(file)
                // Native OCR model stays on-device. Missing OCR results must
                // never be interpreted as a clean source.
                val text=OriginalTextScanner.scan(file)
                mapOf("frames" to hashes,"text" to text)
            }
'''
changed[native]=main.replace(anchor,added+anchor,1)
assert changed["lib/benchmark_oneclick.dart"].count("OneClickExplorer")==1
assert changed["lib/benchmark_ui.dart"].count("원클릭 원본 탐색")==1
assert changed["native/android/BenchmarkFrameExtractor.kt"].count("fun fingerprints(")==1
with ZipFile(out,"w") as z:
 for info,body in entries:
  if info.filename not in changed:z.writestr(info,body)
  else:z.writestr(info,changed.pop(info.filename).encode("utf8"))
 for key,value in changed.items():
  if key!="lib/benchmark_oneclick.dart" or key in old:raise RuntimeError(f"Unexpected new source: {key}")
  z.writestr(key,value.encode("utf8"))
os.replace(out,path)
print("Installed OneClickExplorer, frame cross-check, native OCR gate, and editor handoff v0.21.0+59.")
