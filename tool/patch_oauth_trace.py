#!/usr/bin/env python3
from pathlib import Path
from zipfile import ZipFile
import os,re
p=Path("shorts-studio-source.zip");tmp=p.with_suffix(".traced.zip")
with ZipFile(p) as z: entries=[(i,z.read(i)) for i in z.infolist()]
orig={i.filename:b for i,b in entries};updates={}
def change(path,a,b):
 s=updates.get(path,orig[path].decode("utf-8"));assert s.count(a)==1,(path,s.count(a),a[:60]);updates[path]=s.replace(a,b,1)
k="native/android/YouTubeChromeAuth.kt"
change(k,"    fun connect(result: MethodChannel.Result, customTab: Boolean = false) {",'''    private fun redirectTrace(): Map<String, Any> {
        val p = activity.getSharedPreferences("studio", Activity.MODE_PRIVATE)
        return mapOf("redirectAttempted" to (p.getLong("ytRedirectAttempt",0L)>0L),
            "redirectSeen" to (p.getLong("ytRedirectReceived",0L)>0L),
            "redirectPathValid" to p.getBoolean("ytRedirectValid",false),
            "redirectHasCode" to p.getBoolean("ytRedirectCode",false),
            "redirectHasError" to p.getBoolean("ytRedirectError",false))
    }
    fun connect(result: MethodChannel.Result, customTab: Boolean = false) {''')
change(k,"            val request = AuthorizationRequest.Builder(config, CLIENT_ID, ResponseTypeValues.CODE, REDIRECT)",'''            check(activity.getSharedPreferences("studio", Activity.MODE_PRIVATE).edit()
                .putLong("ytRedirectAttempt",System.currentTimeMillis())
                .remove("ytRedirectReceived").remove("ytRedirectValid")
                .remove("ytRedirectCode").remove("ytRedirectError").commit())
            val request = AuthorizationRequest.Builder(config, CLIENT_ID, ResponseTypeValues.CODE, REDIRECT)''')
change(k,'''            } else {
                oauthFailure(exception, "authorize")
            }
            return true
        }''','''            } else if (exception.type == AuthorizationException.TYPE_GENERAL_ERROR && exception.code == 1) {
                val receipt = redirectTrace()
                val seen = receipt["redirectSeen"] == true
                fail(if (seen) "AUTH_CHROME_AFTER_REDIRECT" else "AUTH_CHROME_REDIRECT_MISSING",
                    if (seen) "OAuth 복귀 URI를 받았지만 AppAuth가 완료하지 못했어요."
                    else "Google 동의 후 OAuth 복귀 URI가 Android 앱에 전달되지 않았어요.",
                    receipt + mapOf("oauthType" to exception.type, "oauthCode" to exception.code))
            } else {
                oauthFailure(exception, "authorize")
            }
            return true
        }''')
change(k,'''        try { result.success(load()?.let { metadata(it) } ?: mapOf("hasGrant" to false, "hasRefreshToken" to false)) }''','''        try { result.success((load()?.let { metadata(it) } ?: mapOf("hasGrant" to false, "hasRefreshToken" to false)) + redirectTrace()) }''')
m="native/android/AndroidManifest.xml"
change(m,'''<activity android:name="net.openid.appauth.RedirectUriReceiverActivity" android:exported="true" tools:node="replace">''','''<activity android:name="net.openid.appauth.RedirectUriReceiverActivity" tools:node="remove" />
        <activity android:name=".YouTubeRedirectTraceActivity" android:exported="true">''')
receiver='''package com.local.shorts_studio

import android.os.Bundle
import net.openid.appauth.RedirectUriReceiverActivity

/** Safely tracks whether Android received the callback; never retains OAuth URI or secrets. */
class YouTubeRedirectTraceActivity : RedirectUriReceiverActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val uri = intent?.data
        val valid = uri?.scheme == YouTubeChromeAuth.REDIRECT_SCHEME && uri.path == "/oauth2redirect"
        val code = try { uri?.getQueryParameter("code") != null } catch (_: Exception) { false }
        val error = try { uri?.getQueryParameter("error") != null } catch (_: Exception) { false }
        getSharedPreferences("studio",MODE_PRIVATE).edit()
            .putLong("ytRedirectReceived",System.currentTimeMillis())
            .putBoolean("ytRedirectValid",valid)
            .putBoolean("ytRedirectCode",code)
            .putBoolean("ytRedirectError",error).commit()
        super.onCreate(savedInstanceState)
    }
}
'''
receiverName="native/android/YouTubeRedirectTraceActivity.kt"
assert receiverName not in orig
change("tool/bootstrap.py","('YouTubeChromeAuth.kt','src/main/kotlin/com/local/shorts_studio/YouTubeChromeAuth.kt'),","('YouTubeRedirectTraceActivity.kt','src/main/kotlin/com/local/shorts_studio/YouTubeRedirectTraceActivity.kt'),('YouTubeChromeAuth.kt','src/main/kotlin/com/local/shorts_studio/YouTubeChromeAuth.kt'),")
d="lib/youtube_chrome.dart"
change(d,"  bool pending = false, hasGrant = false, hasRefreshToken = false;","  bool pending = false, hasGrant = false, hasRefreshToken = false;\n  bool redirectAttempted = false, redirectSeen = false, redirectPathValid = false, redirectHasCode = false, redirectHasError = false;")
change(d,"    hasRefreshToken = value?['hasRefreshToken'] == true;",'''    hasRefreshToken = value?['hasRefreshToken'] == true;
    if (value?.containsKey('redirectAttempted') == true) {
      redirectAttempted = value?['redirectAttempted'] == true;
      redirectSeen = value?['redirectSeen'] == true;
      redirectPathValid = value?['redirectPathValid'] == true;
      redirectHasCode = value?['redirectHasCode'] == true;
      redirectHasError = value?['redirectHasError'] == true;
    }''')
change(d,"          'AUTH_CHROME_NO_RESULT' => 'Chrome 복귀 정보가 앱에 전달되지 않았어요. 아래 Chrome 탭 방식으로 다시 시도해 주세요.',","""          'AUTH_CHROME_NO_RESULT' => 'Chrome 복귀 정보가 앱에 전달되지 않았어요. 아래 Chrome 탭 방식으로 다시 시도해 주세요.',
          'AUTH_CHROME_REDIRECT_MISSING' => 'AppAuth가 취소로 종료됐고, Android에 OAuth 복귀 URI가 도착하지 않았어요.',
          'AUTH_CHROME_AFTER_REDIRECT' => 'OAuth 복귀 URI는 도착했지만 AppAuth가 완료하지 못했어요.',""")
s="lib/youtube_settings.dart"
change(s,"    catch (e) { if (mounted) setState(() => error = youtubeError(e)); }",'''    catch (e) {
      if (youtube.chromeMode) {
        try { await youtube.chrome.load(); } catch (_) {}
      }
      if (mounted) setState(() => error = youtubeError(e));
    }''')
change(s,"        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),",'''        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (youtube.chrome.redirectAttempted) Text(
          youtube.chrome.redirectSeen
            ? (youtube.chrome.redirectPathValid
              ? (youtube.chrome.redirectHasCode ? '최근 Chrome 복귀: 인증 코드 포함 URI 수신'
                : (youtube.chrome.redirectHasError ? '최근 Chrome 복귀: 오류 URI 수신' : '최근 Chrome 복귀: URI 수신, 코드 없음'))
              : '최근 Chrome 복귀: URI 수신, 경로 불일치')
            : '최근 Chrome 복귀: Android 콜백 수신 안 됨',
        ),''')
t="test/youtube_chrome_test.dart"
change(t,"  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {",'''  test('Redirect failure is distinguished without exposing credentials', () async {
    failure = PlatformException(code: 'AUTH_CHROME_REDIRECT_MISSING',
      details: {'oauthType':0, 'oauthCode':1, 'secret':'private-access-token'});
    await expectLater(youtube().connectChrome(), throwsA(isA<YouTubeFailure>()
      .having((e) => e.message, 'message',
        allOf(contains('복귀 URI'), isNot(contains('private-access-token'))))));
  });

  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {''')
doc="YOUTUBE_CHROME_AUTH.md"
change(doc,"# 휴대폰 Chrome 직접 인증 — 0.19.1","# 휴대폰 Chrome 직접 인증 — 0.19.2")
change(doc,"## 0.19.1 복귀 오류 확인",'''## 0.19.2 OAuth 복귀 수신 진단
- Chrome Custom Tab에서도 사용자 동의 후 OAuth 유형 0 코드 1이 확인됨. 이는 AppAuth의 USER_CANCELED_AUTH_FLOW이며 실제 사용자가 취소했다는 증거는 아님.
- Android 콜백 Activity가 전달받은 이벤트만 기록하며, 복귀 URI, 토큰, 코드, 상태 값을 저장하거나 기록하지 않음.
- 리디렉션 미수신은 AUTH_CHROME_REDIRECT_MISSING, 수신 후 AppAuth 취소는 AUTH_CHROME_AFTER_REDIRECT로 분리.
- 앱 설정 화면에는 최신 수신 여부 및 URI가 인증 코드/오류를 포함하는지만 표시. 실기기 재검증 필요.

## 0.19.1 복귀 오류 확인''')
v=orig["pubspec.yaml"].decode("utf-8")
mt=re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$",v)
assert mt is not None
change("pubspec.yaml",mt.group(0),"version: 0.19.2+51")
with ZipFile(tmp,"w") as z:
    for info,b in entries:
        val=updates.get(info.filename,b)
        z.writestr(info,val.encode("utf-8") if isinstance(val,str) else val)
    z.writestr(receiverName,receiver.encode("utf-8"))
os.replace(tmp,p)
print("Modified:",list(updates),receiverName)
