#!/usr/bin/env python3
"""Upgrade the actual Gemini prompt used in initial video analysis and title regeneration.

Keeps response schema curiosity/twist/humor, existing per-line grapheme validator,
automatic headline-only retries, subtitles, and all other source ZIP files intact.
"""
import os
import re
from pathlib import Path
from zipfile import ZipFile

zip_path=Path("shorts-studio-source.zip")
tmp=zip_path.with_suffix(".gemini-titles.tmp")
with ZipFile(zip_path) as archive:
    members=[(info,archive.read(info)) for info in archive.infolist()]
existing={info.filename:payload for info,payload in members}

old_version="version: 0.21.22+81"
new_version="version: 0.21.23+82"
pubspec=existing["pubspec.yaml"].decode("utf-8")
if pubspec.count(old_version)!=1:
    raise RuntimeError("Unexpected application base version: "+pubspec[:150])

# Illustrations are references for tone, not facts to assert about unknown clips.
# The original two-line structure and three style keys remain unchanged.
TITLE_RULES="""너는 한국 유튜브 쇼츠 제목을 전문으로 쓰는 카피라이터야. 영상에 실제로 나타나는 장면·행동·감정·반전 중 가장 흥미로운 한 가지를 짧고 자연스러운 한국어로 표현해.
제목은 평범한 설명이나 AI식 장황한 문장이 아니라, 짧은 상황 제시 + 궁금증, 공감, 귀여움, 가벼운 드립 또는 실제 반전이 느껴지는 말투여야 해.
참고할 한국 쇼츠 제목의 문체와 리듬: '액체 고양이', '나도 좀 먹고 살자', '복복복 가나디의 치명적인 귀여움', '프로레슬링계 아이돌의 위엄', '휴대폰 보다가 스스로를 몰카해버림', '그네 타다 친구까지 같이 보내버림', '이걸 원테이크로 찍었다고?', '센스있는 친구가 행동하는 방법'.
이 예시의 분위기만 참고하고 문구를 복제하거나 특정 소재·상황을 영상에 억지로 끼워 넣지 마.
중요: '상위 1%', '세계 최초', '역대급', '프로 선수', '유일한', '최고'처럼 순위·통계·전문성·독점성을 암시하는 표현은 영상/자료에 객관적 근거가 있을 때만 사용해. 확인할 수 없는 수치·사실·관계·대사·의도·결과를 지어내지 마.
titles 객체에 curiosity(호기심형), twist(반전형), humor(유머형) 세 후보를 각각 하나씩 작성해. 각 후보는 top과 bottom 문자열로 구성해.
호기심형: 실제 주인공·행동을 먼저 보여 주고 이어지는 이유/반응이 궁금하게 작성해. 막연한 '충격적 진실' 식의 허풍은 금지.
반전형: 앞뒤 장면에서 실제로 발견되는 예상 밖의 변화가 있을 때만 반전을 드러내. 영상에 반전이 없으면 특별한 행동을 관찰한 의외성으로 표현하고 없는 결말을 만들지 마.
유머형: 자연스러운 구어체·공감·가벼운 의인화 느낌을 살려. ㅋㅋ, ㄷㄷ, 의문형은 필요한 경우에만 사용하고 억지 드립·조롱·과장 금지.
top은 대상/상황/호기심을, bottom은 반응/의외성/재치 있는 후속 문구를 담되, 두 줄을 이어 읽었을 때 하나의 자연스러운 제목이 돼야 해. 제목을 둘로 자르려고 조사를 분리하거나 낱말 중간 줄바꿈, 어색한 축약, 의미 없는 단어를 덧붙이지 마.
글자수 절대 규칙: 모든 후보의 top은 공백·문장부호·이모지까지 포함한 화면상 글자 수 5~11자, bottom도 별도로 5~11자. 두 줄 합계로 판단하면 안 돼. 앞뒤 공백, 연속 공백, 불필요한 느낌표·이모지·해시태그는 쓰지 마.
톤만 보여주는 형식 예시(영상에 없는 내용을 따라 쓰지 말 것): top='휴대폰 보다가', bottom='스스로를 찍었다'; top='액체가 된 고양이', bottom='몸이 왜 저래?'; top='나도 좀 먹고', bottom='살자고 이러냐'.
출력 전 curiosity, twist, humor의 top/bottom 여섯 줄을 하나씩 직접 검사하고, 5~11자 위반이나 어색한 표현이 있으면 다시 작성해. 출력은 responseSchema의 titles 객체 구조를 정확히 지켜."""

source=existing["lib/ai_rules.dart"].decode("utf-8")
pattern=r"(?m)^const titleRules='[^\r\n]*';"
replacement="const titleRules=r'''"+TITLE_RULES+"''';"
new_rules,count=re.subn(pattern,lambda _:replacement,source)
if count!=1:
    raise RuntimeError("Could not uniquely locate existing Gemini titleRules")
assert "String captionRules(Clip clip)" in new_rules
assert "String visibleTextRules(Clip clip,bool selected)" in new_rules

tests=Path("tool/gemini_title_style_test.dart").read_bytes()
assert b"GeminiCaptions.decodeTitles" in tests
assert "5~11자" in TITLE_RULES
assert "curiosity" in TITLE_RULES
updated={
    "pubspec.yaml":pubspec.replace(old_version,new_version).encode("utf-8"),
    "lib/ai_rules.dart":new_rules.encode("utf-8"),
}
test_path="test/gemini_title_style_test.dart"
if test_path in existing: raise RuntimeError("Unexpected duplicate Gemini title style test")
with ZipFile(tmp,"w") as archive:
    for info,content in members:
        archive.writestr(info,updated.get(info.filename,content))
    archive.writestr(test_path,tests)
os.replace(tmp,zip_path)
print("v0.21.23+82 title prompt integrated for both video analysis and title-only regeneration")
