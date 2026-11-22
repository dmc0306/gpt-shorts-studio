#!/usr/bin/env python3
"""Add ONLY a 12-hour option to the shipped Android YouTube publish cadence.

Existing daily/2-day/3-day/weekly options, uploader, Android WorkManager
and Linux automation remain unchanged. Refuse if ZIP contents are unfamiliar.
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from zipfile import ZipFile

source = Path("shorts-studio-source.zip")
target = source.with_suffix(".youtube-12h.tmp")
if not source.is_file():
    raise RuntimeError("Android source archive was not found")
with ZipFile(source, "r") as archive:
    entries = [(info, archive.read(info)) for info in archive.infolist()]
files = {info.filename: blob for info, blob in entries}
if len(files) != len(entries):
    raise RuntimeError("Duplicate archive paths are not supported")
updates: dict[str, bytes] = {}


def replace(path: str, before: str, after: str) -> None:
    content = updates.get(path, files[path]).decode("utf-8")
    if content.count(before) != 1:
        raise RuntimeError(
            f"Unexpected Android source anchor: {path} / {before[:85]} "
            f"({content.count(before)} matches)"
        )
    updates[path] = content.replace(before, after, 1).encode("utf-8")


# Persisted YouTube configuration: a 12h selection must not fall back to 24h.
replace("lib/youtube_channel.dart",
        "const [24,48,72,168].contains(data['cadenceHours'])",
        "const [12,24,48,72,168].contains(data['cadenceHours'])")

# Public reservation time calculator and all callers (batch previews included).
replace("lib/youtube_publish_plan.dart",
        "static const supportedHours=[24,48,72,168];",
        "static const supportedHours=[12,24,48,72,168];")
replace("lib/youtube_publish_plan.dart",
        "24=>'매일',48=>'2일마다',72=>'3일마다',168=>'매주',",
        "12=>'하루 2회 (12시간 간격)',24=>'매일',48=>'2일마다',72=>'3일마다',168=>'매주',")

# Insert exactly one new selectable choice in the existing Settings dropdown.
replace("lib/youtube_settings.dart",
        "DropdownMenuItem(value:24,child:Text('매일')),",
        "DropdownMenuItem(value:12,child:Text('하루 2회 (12시간 간격)')),\n"
        "               DropdownMenuItem(value:24,child:Text('매일')),")

# Add production-flutter tests, including 09:00/21:00 and JSON persistence.
tests = Path("tool/youtube_schedule_tests.dart").read_text(encoding="utf-8")
start = tests.index("  test('12-hour public cadence previews")
end = tests.index("  test('Legacy settings stay private;", start)
new_tests = tests[start:end]
replace("test/youtube_schedule_test.dart",
        "  test('Legacy settings stay private; public auto upload requires same-channel consent',(){",
        new_tests + "  test('Legacy settings stay private; public auto upload requires same-channel consent',(){")

# Bump Android version so the new APK is recognized as an update.
version = files["pubspec.yaml"].decode("utf-8")
match = re.search(r"(?m)^version: 0\\.21\\.(\\d+)\\+(\\d+)\\s*$", version)
if match is None:
    raise RuntimeError("Unexpected existing app version; refusing to overwrite")
old_version = match.group(0)
new_version = f"version: 0.21.{int(match[1])+1}+{int(match[2])+1}"
updates["pubspec.yaml"] = version.replace(old_version, new_version, 1).encode("utf-8")

with ZipFile(target, "w") as archive:
    for info, data in entries:
        archive.writestr(info, updates.get(info.filename, data))
os.replace(target, source)
print(f"Packaged {new_version}: Android YouTube 12-hour publication cadence")
