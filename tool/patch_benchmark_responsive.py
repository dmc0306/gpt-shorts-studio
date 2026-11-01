#!/usr/bin/env python3
"""Fix silent indefinite busy state in benchmark one-click source lookup."""
from pathlib import Path
from zipfile import ZipFile
import os
archive=Path("shorts-studio-source.zip")
out=archive.with_suffix(".responsive.zip")
with ZipFile(archive) as z: entries=[(i,z.read(i)) for i in z.infolist()]
data={i.filename:b for i,b in entries}
v=data["pubspec.yaml"].decode()
if v.count("version: 0.21.1+60")!=1:raise RuntimeError(f"Unexpected baseline version: {v[:95]}")
updated={
 "pubspec.yaml":v.replace("version: 0.21.1+60","version: 0.21.2+61").encode(),
 "lib/benchmark_ui.dart":Path("tool/benchmark_ui.dart").read_bytes(),
 "lib/benchmark_oneclick.dart":Path("tool/benchmark_oneclick.dart").read_bytes(),
 "lib/benchmark_stream.dart":Path("tool/benchmark_stream.dart").read_bytes(),
}
for k in updated:
 if k not in data:raise RuntimeError("Missing original source: "+k)
assert b"activeVideoId" in updated["lib/benchmark_ui.dart"]
assert b"stopSearch()" in updated["lib/benchmark_ui.dart"]
assert b"maxSearch" in updated["lib/benchmark_oneclick.dart"]
assert b"seconds:85" in updated["lib/benchmark_stream.dart"]
with ZipFile(out,"w") as z:
 for info,body in entries:z.writestr(info,updated.get(info.filename,body))
os.replace(out,archive)
print("Short Studio 0.21.2+61: in-card progress, cancel and bounded network scan.")
