#!/usr/bin/env python3
"""Package OCR-selected search windows and strict similar-duration candidate validation."""
from pathlib import Path
from zipfile import ZipFile
import os
src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".ocr-duration.zip")
with ZipFile(src) as z:items=[(info,z.read(info)) for info in z.infolist()]
original={info.filename:raw for info,raw in items}
pub=original["pubspec.yaml"].decode("utf8")
old="version: 0.21.8+67"
if pub.count(old)!=1:raise RuntimeError("Expected "+old+", not "+pub[:140])
bootstrap=original["tool/bootstrap.py"].decode("utf8")
from_token="('BenchmarkFrameExtractor.kt','src/main/kotlin/com/local/shorts_studio/BenchmarkFrameExtractor.kt'),"
new_token=from_token+"('BenchmarkOcrCrop.kt','src/main/kotlin/com/local/shorts_studio/BenchmarkOcrCrop.kt'),"
if bootstrap.count(from_token)!=1:raise RuntimeError("Cannot install OCR Kotlin source")
bootstrap=bootstrap.replace(from_token,new_token,1)

main=original["native/android/MainActivity.kt"].decode("utf8")
anchor="                val hashes=BenchmarkFrameExtractor.fingerprints(file)"
if main.count(anchor)!=1:raise RuntimeError("Candidate frame hook not found")
replace="""                val bounds=call.argument<List<Map<String,Double>>>("bounds")?:emptyList()
                require(bounds.size<=8){"검색 영역 개수가 너무 많아요."}
                for(window in bounds){
                    require(listOf("x","y","w","h").all{window[it]?.isFinite()==true})
                    require(window["x"]!!>=0.0&&window["y"]!!>=0.0)
                    require(window["w"]!!>0.0&&window["h"]!!>0.0)
                    require(window["x"]!!+window["w"]!!<=1.001 &&
                        window["y"]!!+window["h"]!!<=1.001){"검색 영역 좌표 오류"}
                }
                val hashes=BenchmarkFrameExtractor.fingerprints(file,bounds)"""
main=main.replace(anchor,replace,1)

replacements={
    "pubspec.yaml":pub.replace(old,"version: 0.21.9+68").encode("utf8"),
    "tool/bootstrap.py":bootstrap.encode("utf8"),
    "native/android/MainActivity.kt":main.encode("utf8"),
    "native/android/BenchmarkFrameExtractor.kt":Path("tool/BenchmarkFrameExtractor.kt").read_bytes(),
    "native/android/BenchmarkOcrCrop.kt":Path("tool/BenchmarkOcrCrop.kt").read_bytes(),
    "lib/benchmark_duration.dart":Path("tool/benchmark_duration.dart").read_bytes(),
    "lib/benchmark_oneclick.dart":Path("tool/benchmark_oneclick.dart").read_bytes(),
    "lib/benchmark_ui.dart":Path("tool/benchmark_ui.dart").read_bytes(),
    "test/benchmark_test.dart":Path("tool/benchmark_tests.dart").read_bytes(),
}
if b"BenchmarkOcrCrop.select" not in replacements["native/android/BenchmarkFrameExtractor.kt"]:
    raise RuntimeError("OCR filtering missing")
if b"BenchmarkDuration.youtubeLengths" not in replacements["lib/benchmark_oneclick.dart"]:
    raise RuntimeError("Duration preflight missing")
if b"originalContent" not in replacements["native/android/BenchmarkFrameExtractor.kt"]:
    raise RuntimeError("Lens uncropped fallback lost")
new_files={"native/android/BenchmarkOcrCrop.kt","lib/benchmark_duration.dart"}
with ZipFile(tmp,"w") as z:
    for info,raw in items:z.writestr(info,replacements.pop(info.filename,raw))
    if set(replacements)!=new_files:raise RuntimeError("Unexpected replacement paths "+str(replacements.keys()))
    for path,raw in replacements.items():z.writestr(path,raw)
os.replace(tmp,src)
print("0.21.9+68: On-device Korean OCR clean search windows, common reference/candidate crops, YouTube duration preflight.")
