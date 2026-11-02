#!/usr/bin/env python3
"""Package time-consistent video matching and caption-screening into the app ZIP."""
from pathlib import Path
from zipfile import ZipFile
import os

src = Path("shorts-studio-source.zip")
temp = src.with_suffix(".temporal-precision.zip")
expected = "version: 0.21.14+73"
next_version = "version: 0.21.15+74"
mapping = {
    "native/android/BenchmarkFrameExtractor.kt": "tool/BenchmarkFrameExtractor.kt",
    "lib/benchmark_oneclick.dart": "tool/benchmark_oneclick.dart",
    "test/benchmark_test.dart": "tool/benchmark_tests.dart",
}
with ZipFile(src) as archive:
    entries = [(info, archive.read(info)) for info in archive.infolist()]
files = {info.filename: raw for info, raw in entries}
for destination in mapping:
    if destination not in files:
        raise RuntimeError("Missing expected source path: " + destination)

pub = files["pubspec.yaml"].decode("utf8")
if pub.count(expected) != 1:
    raise RuntimeError("Unexpected app version; refusing to overwrite: " + pub[:120])
changes = {
    target: Path(local).read_bytes()
    for target, local in mapping.items()
}
changes["pubspec.yaml"] = pub.replace(expected, next_version).encode("utf8")
native = changes["native/android/BenchmarkFrameExtractor.kt"].decode("utf8")
logic = changes["lib/benchmark_oneclick.dart"].decode("utf8")
tests = changes["test/benchmark_test.dart"].decode("utf8")
assert "OPTION_CLOSEST_SYNC" not in native
assert "cropIndex" in native and "OPTION_CLOSEST" in native
assert "before.time+700>current.time" in logic
assert "m.matched>=3" in logic
assert "y<.24||y>.66||" in logic
assert "Reverse timeline cannot masquerade" in tests
with ZipFile(temp, "w") as archive:
    for info, old in entries:
        archive.writestr(info, changes.get(info.filename, old))
os.replace(temp, src)
print("Packaged v0.21.15+74 temporal three-scene verification and centered caption filter")
