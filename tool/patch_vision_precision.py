#!/usr/bin/env python3
"""Patch v0.20.3+56 with strict image-match filtering and frame previews."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
temp=Path("shorts-studio-source.precision.zip")
with ZipFile(src) as z:
    entries=[(i,z.read(i)) for i in z.infolist()]
data={i.filename:raw for i,raw in entries}
expected={
    "lib/vision_reverse.dart":"tool/vision_reverse.dart",
    "lib/benchmark_ui.dart":"tool/benchmark_ui.dart",
    "test/benchmark_test.dart":"tool/benchmark_tests.dart",
    "native/android/BenchmarkFrameExtractor.kt":"tool/BenchmarkFrameExtractor.kt",
}
for path in expected:
    if path not in data:
        raise RuntimeError(f"Cannot update nonexistent source: {path}")
pub=data["pubspec.yaml"].decode("utf-8")
old="version: 0.20.3+56"
if pub.count(old)!=1:
    raise RuntimeError(f"Expected {old}, found {pub.splitlines()[:12]}")
updates={path:Path(file).read_text(encoding="utf-8").encode("utf-8") for path,file in expected.items()}
updates["pubspec.yaml"]=pub.replace(old,"version: 0.20.4+57").encode("utf-8")
# Validate old ranking semantics are not left active.
check=updates["lib/vision_reverse.dart"].decode("utf-8")
if "fullMatchingImages" not in check or "frames.length>=3" not in check:
    raise RuntimeError("Strict frame matcher missing.")
view=updates["lib/benchmark_ui.dart"].decode("utf-8")
if "framePreviews" not in view or "직접일치 교차검증 v2" not in view:
    raise RuntimeError("Frame previews or old cache migration missing.")
with ZipFile(temp,"w") as z:
    for info,raw in entries:
        z.writestr(info,updates.get(info.filename,raw))
os.replace(temp,src)
print("v0.20.4+57 strict Vision matching, six-frame preview, overlay crop, old-origin invalidation applied.")
