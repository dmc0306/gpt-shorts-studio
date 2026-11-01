#!/usr/bin/env python3
"""Assertion-guarded one-time patch of Shorts Studio source ZIP."""
from pathlib import Path
from zipfile import ZipFile
import os, re
src=Path("shorts-studio-source.zip"); tmp=src.with_suffix(".patched.zip")
with ZipFile(src) as z:
    entries=[(i,z.read(i)) for i in z.infolist()]
original={i.filename:b for i,b in entries}
edited={}
def change(path,old,new):
    data=edited.get(path,original[path].decode("utf-8"))
    n=data.count(old)
    if n!=1: raise RuntimeError(f"Patch assertion failed {path}, count={n}: {old[:100]}")
    edited[path]=data.replace(old,new,1)
k="native/android/YouTubeChromeAuth.kt"
change(k,'    private val serviceLazy = lazy {\n        AuthorizationService(activity, AppAuthConfiguration.Builder()\n            .setBrowserMatcher(VersionedBrowserMatcher.CHROME_BROWSER)',
         '    private fun createService(matcher: VersionedBrowserMatcher): AuthorizationService {\n        return AuthorizationService(activity, AppAuthConfiguration.Builder()\n            .setBrowserMatcher(matcher)')
change(k,'    private val service get() = serviceLazy.value\n',
         '    private val serviceLazy = lazy { createService(VersionedBrowserMatcher.CHROME_BROWSER) }\n    private val tabServiceLazy = lazy { createService(VersionedBrowserMatcher.CHROME_CUSTOM_TAB) }\n    private val service get() = serviceLazy.value\n    private var loginService: AuthorizationService? = null\n    private var loginBrowserMode = "browser"\n')
change(k,'    fun connect(result: MethodChannel.Result) {\n','    fun connect(result: MethodChannel.Result, customTab: Boolean = false) {\n')
change(k,'            @Suppress("DEPRECATION")\n            activity.startActivityForResult(service.getAuthorizationRequestIntent(request), requestCode)',
         '            val selected = if (customTab) tabServiceLazy.value else service\n            loginService = selected\n            loginBrowserMode = if (customTab) "custom_tab" else "browser"\n            @Suppress("DEPRECATION")\n            activity.startActivityForResult(selected.getAuthorizationRequestIntent(request), requestCode)')
change(k,'        if (response == null) {\n            oauthFailure(exception, "authorize")\n            return true\n        }',
         '        if (response == null) {\n            if (exception == null) {\n                fail("AUTH_CHROME_NO_RESULT", "Chrome 인증 복귀 응답이 앱으로 전달되지 않았어요. Chrome 탭 방식으로 다시 시도해 주세요.", mapOf("resultCode" to resultCode, "returnedIntent" to (data != null), "mode" to loginBrowserMode))\n            } else oauthFailure(exception, "authorize")\n            return true\n        }')
change(k,'            service.performTokenRequest(response.createTokenExchangeRequest()) { token, error ->',
         '            (loginService ?: service).performTokenRequest(response.createTokenExchangeRequest()) { token, error ->')
change(k,'        if (serviceLazy.isInitialized()) service.dispose()\n',
         '        if (serviceLazy.isInitialized()) service.dispose()\n        if (tabServiceLazy.isInitialized()) tabServiceLazy.value.dispose()\n')
change("native/android/MainActivity.kt",'"youtubeChromeConnect" -> youtubeChrome.connect(r)',
       '"youtubeChromeConnect" -> youtubeChrome.connect(r, call.argument<Boolean>("customTab")==true)')
d="lib/youtube_chrome.dart"
change(d,'  Future<void> connect() async {\n','  Future<void> connect({bool customTab = false}) async {\n')
change(d,"      metadata(await call('youtubeChromeConnect'));","      metadata(await call('youtubeChromeConnect', {'customTab': customTab}));")
change(d,"          'AUTH_CHROME_STATE' => '인증 복귀 정보를 확인하지 못했어요. 앱에서 다시 연결해 주세요.',",
         "          'AUTH_CHROME_STATE' => '인증 복귀 정보를 확인하지 못했어요. 앱에서 다시 연결해 주세요.',\n          'AUTH_CHROME_NO_RESULT' => 'Chrome 복귀 정보가 앱에 전달되지 않았어요. 아래 Chrome 탭 방식으로 다시 시도해 주세요.',")
change(d,"      throw YouTubeFailure('$message [${e.code}]');",
         """      final safeDiagnostic = <String>[
        if (details is Map && details['oauthType'] is int) 'OAuth 유형 ${details['oauthType']}',
        if (details is Map && details['oauthCode'] is int) 'OAuth 코드 ${details['oauthCode']}',
        if (details is Map && details['returnedIntent'] is bool)
          details['returnedIntent'] == true ? '응답 Intent 있음' : '응답 Intent 없음',
      ].join(' · ');
      throw YouTubeFailure('$message [${e.code}]${safeDiagnostic.isEmpty ? '' : ' ($safeDiagnostic)'}');""")
change("lib/youtube.dart",'  Future<void> connectChrome() async {',
       '  Future<void> connectChrome({bool customTab = false}) async {')
change("lib/youtube.dart",'    final connecting = chrome.connect();',
       '    final connecting = chrome.connect(customTab: customTab);')
change("lib/youtube_settings.dart",
       """        FilledButton.icon(onPressed: locked ? null : () => run(youtube.connectChrome),
          icon: const Icon(Icons.open_in_browser), label: const Text('Chrome에서 로그인 · 브랜드 채널 선택')),""",
       """        FilledButton.icon(onPressed: locked ? null : () => run(youtube.connectChrome),
          icon: const Icon(Icons.open_in_browser), label: const Text('Chrome에서 로그인 · 브랜드 채널 선택')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: locked ? null : () => run(() => youtube.connectChrome(customTab: true)),
          icon: const Icon(Icons.tab), label: const Text('Chrome 탭으로 로그인 · 복귀 오류 대안')),""")
t="test/youtube_chrome_test.dart"
change(t,'  PlatformException? failure;\n','  PlatformException? failure;\n  bool? customTabRequested;\n')
change(t,"    calls.clear(); prefs = {}; actualId = 'UC${'a' * 22}'; failure = null;",
         "    calls.clear(); prefs = {}; actualId = 'UC${'a' * 22}'; failure = null; customTabRequested = null;")
change(t,"      if (call.method == 'youtubeChromeConnect' && failure != null) throw failure!;",
         """      if (call.method == 'youtubeChromeConnect') {
        customTabRequested = call.arguments['customTab'] == true;
        if (failure != null) throw failure!;
      }""")
change(t,"  test('Chrome mode survives persistence and refresh revalidates changed target', () async {",
         """  test('Chrome Custom Tab fallback uses the same Android OAuth bridge', () async {
    final yt = youtube();
    await yt.connectChrome(customTab: true);
    expect(customTabRequested, true);
    expect(yt.chromeMode, true);
    expect(yt.channel?.id, actualId);
    expect(yt.preferences.automatic, false);
  });

  test('Chrome mode survives persistence and refresh revalidates changed target', () async {""")
change(t,"  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {",
         """  test('No-result diagnostics remain redacted', () async {
    failure = PlatformException(code: 'AUTH_CHROME_NO_RESULT', details: {
      'returnedIntent': false, 'secret': 'private-access-token'
    });
    await expectLater(youtube().connectChrome(), throwsA(
      isA<YouTubeFailure>().having((e) => e.message, 'message',
        allOf(contains('응답 Intent 없음'), isNot(contains('private-access-token'))))
    ));
  });

  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {""")
change("YOUTUBE_CHROME_AUTH.md","# 휴대폰 Chrome 직접 인증 — 0.19.0","# 휴대폰 Chrome 직접 인증 — 0.19.1")
change("YOUTUBE_CHROME_AUTH.md","## 동작과 한계",
       """## 0.19.1 복귀 오류 확인
- 기본 Chrome 브라우저에서 동의 후 앱 복귀가 불안정하면 **Chrome 탭으로 로그인 · 복귀 오류 대안**을 시도하세요. Chrome Custom Tab도 같은 Android OAuth 클라이언트, PKCE 및 직접 앱 복귀를 사용하며 서버는 필요 없습니다.
- AUTH_CHROME_NO_RESULT는 OAuth 응답도 예외도 전달되지 않은 경우입니다. 기존 AUTH_CHROME_AUTHORIZE보다 정확하게 원인을 구분하고 OAuth 오류의 정수 유형/코드만 표시합니다. 인증 토큰, 원본 URL 등은 노출하지 않습니다.
- 어느 경로가 성공할지는 실제 기기에서 확인해야 합니다.

## 동작과 한계""")
if "pubspec.yaml" in original:
    v=original["pubspec.yaml"].decode("utf-8")
    m=re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$",v)
    if not m:raise RuntimeError("pubspec version missing")
    change("pubspec.yaml",m.group(0),"version: 0.19.1+50")
with ZipFile(tmp,"w") as z:
    for info,data in entries:
        z.writestr(info,edited.get(info.filename,"").encode("utf-8") if info.filename in edited else data)
os.replace(tmp,src)
print("Updated:",", ".join(edited.keys()))
