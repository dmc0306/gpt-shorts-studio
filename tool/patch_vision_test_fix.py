#!/usr/bin/env python3
"""Refresh the Vision regression suite after a stalled CI mock-network test."""
from pathlib import Path
from zipfile import ZipFile
import os
src=Path("shorts-studio-source.zip");tmp=src.with_suffix(".tested.zip")
with ZipFile(src) as z:entries=[(x,z.read(x)) for x in z.infolist()]
files={x.filename:raw for x,raw in entries}
assert "version: 0.20.4+57" in files["pubspec.yaml"].decode("utf8")
tests=Path("tool/benchmark_tests.dart").read_bytes()
if b"Cross-verified pages need 3 frame moments" not in tests:raise RuntimeError("Strict matcher regression tests not present")
updated={"test/benchmark_test.dart":tests,
 "pubspec.yaml":files["pubspec.yaml"].decode("utf8").replace("version: 0.20.4+57","version: 0.20.5+58").encode("utf8")}
with ZipFile(tmp,"w") as z:
 for item,raw in entries:z.writestr(item,updated.get(item.filename,raw))
os.replace(tmp,src)
print("Updated regression tests and package version: 0.20.5+58")
