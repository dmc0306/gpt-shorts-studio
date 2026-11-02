#!/usr/bin/env python3
"""Package expanded OCR crop, short-form guards and bounded continuous search."""
from pathlib import Path
from zipfile import ZipFile
import os

archive_path=Path("shorts-studio-source.zip")
tmp=archive_path.with_suffix(".continuous.tmp")
with ZipFile(archive_path) as archive:
    members=[(info,archive.read(info)) for info in archive.infolist()]
existing={info.filename:raw for info,raw in members}
old="version: 0.21.15+74"
new="version: 0.21.16+75"
pub=existing["pubspec.yaml"].decode("utf8")
if pub.count(old)!=1:
    raise RuntimeError("Unexpected base application version; no write: "+pub[:160])
files={
  "native/android/BenchmarkFrameExtractor.kt": "tool/BenchmarkFrameExtractor.kt",
  "native/android/BenchmarkOcrCrop.kt": "tool/BenchmarkOcrCrop.kt",
  "lib/benchmark_duration.dart": "tool/benchmark_duration.dart",
  "lib/benchmark_oneclick.dart": "tool/benchmark_oneclick.dart",
  "lib/benchmark_ui.dart": "tool/benchmark_ui.dart",
  "test/benchmark_test.dart": "tool/benchmark_tests.dart",
}
for app_path in files:
    if app_path not in existing:
        raise RuntimeError("Source ZIP missing "+app_path)
changes={target:Path(src).read_bytes() for target,src in files.items()}
changes["pubspec.yaml"]=pub.replace(old,new).encode("utf8")
assert b"frameBatches" in changes["lib/benchmark_oneclick.dart"]
assert b"isShortGeometry" in changes["lib/benchmark_oneclick.dart"]
assert b"continuous:true" in changes["lib/benchmark_ui.dart"]
assert b"videoWidth" in changes["native/android/BenchmarkFrameExtractor.kt"]
assert b"listOf(.94,.90,.84,.76,.66)" in changes["native/android/BenchmarkOcrCrop.kt"]
with ZipFile(tmp,"w") as archive:
    for info,raw in members:
        archive.writestr(info,changes.get(info.filename,raw))
os.replace(tmp,archive_path)
print("v0.21.16+75: enlarged OCR-safe crops, close durations, exclude longform, continuous batches")
