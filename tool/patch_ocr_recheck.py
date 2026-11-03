#!/usr/bin/env python3
"""Package double-checked OCR search crops and truthful Lens sharing."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".ocr-recheck.tmp")
with ZipFile(src) as archive:
    rows=[(info,archive.read(info)) for info in archive.infolist()]
existing={info.filename:raw for info,raw in rows}
old="version: 0.21.16+75"
new="version: 0.21.17+76"
pub=existing["pubspec.yaml"].decode("utf8")
if pub.count(old)!=1:
    raise RuntimeError("Expected base "+old+"; got "+pub[:150])
paths={
    "native/android/BenchmarkOcrCrop.kt":"tool/BenchmarkOcrCrop.kt",
    "native/android/BenchmarkFrameExtractor.kt":"tool/BenchmarkFrameExtractor.kt",
    "lib/benchmark_ui.dart":"tool/benchmark_ui.dart",
}
for dest in paths:
    if dest not in existing:raise RuntimeError("Missing destination "+dest)
changes={dest:Path(local).read_bytes() for dest,local in paths.items()}
changes["pubspec.yaml"]=pub.replace(old,new).encode()
ocr=changes["native/android/BenchmarkOcrCrop.kt"]
extractor=changes["native/android/BenchmarkFrameExtractor.kt"]
ui=changes["lib/benchmark_ui.dart"]
assert b"findTextBoxes(scaled,recognizer).isEmpty()" in ocr
assert b"ocrRechecked" in extractor
assert b"originalContent" not in extractor
assert b"final frames=framePreviews[v.id]" in ui
assert b"fullFramePreviews" not in ui
with ZipFile(tmp,"w") as archive:
    for info,raw in rows:
        archive.writestr(info,changes.get(info.filename,raw))
os.replace(tmp,src)
print("Packaged v0.21.17+76: zoomed second OCR scan, crop-only Vision/Lens image")
