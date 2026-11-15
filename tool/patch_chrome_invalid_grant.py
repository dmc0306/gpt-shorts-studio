#!/usr/bin/env python3
"""Package precise AUTH_CHROME_REFRESH invalid_grant guidance into Flutter ZIP.

No token contents, OAuth URLs or authorization codes are read or logged.
Refuse to patch unknown app versions or ambiguous source anchors.
"""
from pathlib import Path
from zipfile import ZipFile
import os

src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".invalid-grant.tmp")
with ZipFile(src) as z:
    records=[(info,z.read(info)) for info in z.infolist()]
files={info.filename:blob for info,blob in records}
updates={}


def replace(name,old,new):
    current=updates.get(name,files[name].decode("utf-8"))
    count=current.count(old)
    if count!=1:
        raise RuntimeError(f"{name}: expected one anchor, found {count}: {old[:85]!r}")
    updates[name]=current.replace(old,new,1)


replace("pubspec.yaml", "version: 0.21.27+86", "version: 0.21.28+87")
replace("lib/youtube_chrome.dart",
    "  bool pending = false, hasGrant = false, hasRefreshToken = false;",
    "  bool pending = false, hasGrant = false, hasRefreshToken = false;\n"
    "  /// Last refresh was explicitly rejected by Google's token endpoint.\n"
    "  bool refreshRejected = false;")
replace("lib/youtube_chrome.dart",
    "      final oauth = details is Map ? details['oauthError'] : null;",
    "      final oauth = details is Map ? details['oauthError'] : null;\n"
    "      final invalidGrant = e.code == 'AUTH_CHROME_REFRESH' &&\n"
    "        (oauth == 'invalid_grant' ||\n"
    "         (details is Map && details['oauthType'] == 2 && details['oauthCode'] == 2002));\n"
    "      if(invalidGrant) refreshRejected = true;")
replace("lib/youtube_chrome.dart",
    "        'invalid_grant' => '인증 권한이 만료되거나 무효화됐어요. Chrome에서 다시 연결해 주세요.',",
    "        'invalid_grant' => 'Google이 저장된 인증 갱신 토큰을 거부했어요(invalid_grant). '\n"
    "          'Chrome에서 다시 로그인한 뒤 갱신을 확인해 주세요. '\n"
    "          '반복되면 Google OAuth 게시 상태가 Testing인지 확인하세요.',")
replace("lib/youtube_chrome.dart",
    "      if (!hasGrant) throw const YouTubeFailure('Chrome 인증 결과를 확인하지 못했어요.');",
    "      if (!hasGrant) throw const YouTubeFailure('Chrome 인증 결과를 확인하지 못했어요.');\n"
    "      refreshRejected = false;")
replace("lib/youtube_chrome.dart",
    "    metadata(result);\n    return token;",
    "    metadata(result);\n    refreshRejected = false;\n    return token;")
replace("lib/youtube_chrome.dart",
    "    metadata(null);\n    return result?['revoked'] == true;",
    "    metadata(null);\n    refreshRejected = false;\n    return result?['revoked'] == true;")

replace("lib/youtube_settings.dart",
    "        const Text('최초 설정: Google Cloud Android 클라이언트의 Custom URI scheme 허용을 켜고 저장하세요.'),",
    "        if(youtube.chrome.refreshRejected)\n"
    "          const Text('Google이 기존 인증 갱신을 거부했습니다 (invalid_grant / 2002). '\n"
    "            '위 Chrome 로그인에서 동일 채널을 다시 승인하고 갱신을 확인하세요. '\n"
    "            '반복되면 Google Cloud → Google Auth Platform → Audience에서 Testing 상태인지 확인하세요.',\n"
    "            style:TextStyle(color:Colors.red)),\n"
    "        if(!youtube.chrome.refreshRejected)\n"
    "          const Text('최초 설정: Google Cloud Android 클라이언트의 Custom URI scheme 허용을 켜고 저장하세요.'),")
replace("lib/youtube_settings.dart",
    "           Text(youtube.chrome.hasRefreshToken ? '인증 정보 암호화 저장됨 · 갱신 권한 있음' : '갱신 권한 없음 · 인증 만료 시 재연결 필요'),",
    "           Text(youtube.chrome.refreshRejected\n"
    "             ? '저장된 갱신 토큰이 거부됨 · Chrome 재로그인 필요'\n"
    "             : youtube.chrome.hasRefreshToken\n"
    "               ? '갱신 토큰 암호화 저장됨 · 유효성은 갱신 검사 후 확인'\n"
    "               : '갱신 토큰 없음 · 인증 만료 시 재연결 필요'),")

replace("test/youtube_chrome_test.dart",
    "  PlatformException? failure;",
    "  PlatformException? failure;\n  PlatformException? refreshFailure;")
replace("test/youtube_chrome_test.dart",
    "    calls.clear(); prefs = {}; actualId = 'UC${'a' * 22}'; failure = null; customTabRequested = null;",
    "    calls.clear(); prefs = {}; actualId = 'UC${'a' * 22}'; failure = null; refreshFailure = null; customTabRequested = null;")
replace("test/youtube_chrome_test.dart",
    "      if (call.method == 'youtubeChromeToken') {",
    "      if (call.method == 'youtubeChromeToken') {\n"
    "        if(refreshFailure != null) throw refreshFailure!;")
replace("test/youtube_chrome_test.dart",
    "  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {",
    """  test('OAuth token 2002 marks grant invalid and requires human re-consent', () async {
    final yt = youtube();
    await yt.connectChrome();
    yt.preferences.madeForKids = false;
    await yt.confirmChannel();
    refreshFailure = PlatformException(
      code: 'AUTH_CHROME_REFRESH',
      message: 'do-not-log-secret-token',
      details: {'oauthType': 2, 'oauthCode': 2002,
        'oauthError': 'invalid_grant', 'secret': 'do-not-log-secret-token'});
    await expectLater(yt.verifyChromeRefresh(), throwsA(
      isA<YouTubeFailure>().having((e) => e.message, 'message',
        allOf(contains('invalid_grant'), contains('AUTH_CHROME_REFRESH'),
          isNot(contains('do-not-log-secret-token'))))));
    expect(yt.chrome.refreshRejected, isTrue);
    refreshFailure = null;
    await yt.connectChrome();
    expect(yt.chrome.refreshRejected, isFalse);
  });

  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {""")

with ZipFile(tmp,"w") as z:
    for info,b in records:
        data=updates.get(info.filename)
        z.writestr(info,data.encode("utf-8") if data is not None else b)
os.replace(tmp,src)
print("Packaged v0.21.28+87: invalid_grant 2002 refresh rejection guidance and test")
