#!/usr/bin/env python3
"""Package clear video-verification states and strict embedded-caption screening."""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
temp=src.with_suffix(".caption-verified.tmp")
with ZipFile(src) as z:
    entries=[(info,z.read(info)) for info in z.infolist()]
files={info.filename:raw for info,raw in entries}
pub=files["pubspec.yaml"].decode("utf8")
old="version: 0.21.17+76"
new="version: 0.21.18+77"
if pub.count(old)!=1:raise RuntimeError("Unexpected base version: "+pub[:130])
mapping={
 "lib/benchmark_oneclick.dart":"tool/benchmark_oneclick.dart",
 "lib/benchmark_ui.dart":"tool/benchmark_ui.dart",
 "lib/benchmark_data.dart":"tool/benchmark_data.dart",
 "test/benchmark_test.dart":"tool/benchmark_tests.dart",
}
for destination in mapping:
    if destination not in files:raise RuntimeError("Missing "+destination)
updated={p:Path(path).read_bytes() for p,path in mapping.items()}
updated["pubspec.yaml"]=pub.replace(old,new).encode()
assert b"OverlayCheck.verdict" in updated["lib/benchmark_oneclick.dart"]
assert b"'caption_possible'" in updated["lib/benchmark_oneclick.dart"]
assert b"final captioned=" in updated["lib/benchmark_ui.dart"]
assert b"captioned" in updated["lib/benchmark_data.dart"]
assert b"Short lived caption" in updated["test/benchmark_test.dart"]
with ZipFile(temp,"w") as z:
    for info,raw in entries:z.writestr(info,updated.get(info.filename,raw))
os.replace(temp,src)
print("Packaged v0.21.18+77: honest Instagram labels, one-frame caption detection, manual caption blacklist")
