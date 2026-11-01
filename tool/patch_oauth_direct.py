#!/usr/bin/env python3
"""Fix Android AppAuth USER_CANCELED race by using a direct Chrome URI callback.
Reads/writes only the repository's versioned source ZIP.
"""
from pathlib import Path
from zipfile import ZipFile
import os,re
src=Path("shorts-studio-source.zip")
tmp=src.with_suffix(".direct.zip")
with ZipFile(src) as z:
    entries=[(i,z.read(i)) for i in z.infolist()]
original={i.filename:b for i,b in entries}
patched={}
def change(path,before,after):
    current=patched.get(path,original[path].decode("utf-8"))
    found=current.count(before)
    if found != 1:
        raise RuntimeError(f"Patch failed: {path}, matches={found}, start={before[:90]!r}")
    patched[path]=current.replace(before,after,1)

k="native/android/YouTubeChromeAuth.kt"
change(k,"import android.app.Activity\n","import android.app.Activity\nimport androidx.browser.customtabs.CustomTabsIntent\n")
change(k,"    private var requestState: String? = null\n",
         """    private var requestState: String? = null
    private var activeRequest: AuthorizationRequest? = null
    private var redirectHandling = false
""")
change(k,'''    private val writeStore: (String) -> Unit
) {''',
         '''    private val writeStore: (String) -> Unit,
    private val readPendingRequest: () -> String,
    private val writePendingRequest: (String) -> Unit
) {''')
change(k,"        requestState = null\n        return pending.also { pending = null }",
         """        requestState = null
        activeRequest = null
        redirectHandling = false
        try { writePendingRequest("") } catch (_: Exception) { }
        return pending.also { pending = null }""")
change(k,
       "            requestState = request.state\n            requestCode = 8400 + attempt % 1000",
       """            requestState = request.state
            activeRequest = request
            // Code verifier + state are sensitive: encrypt before opening the browser.
            writePendingRequest(request.jsonSerializeString())
            requestCode = 8400 + attempt % 1000""")
change(k,
       '''            val selected = if (customTab) tabServiceLazy.value else service
            loginService = selected
            loginBrowserMode = if (customTab) "custom_tab" else "browser"
            @Suppress("DEPRECATION")
            activity.startActivityForResult(selected.getAuthorizationRequestIntent(request), requestCode)''',
       '''            loginBrowserMode = if (customTab) "custom_tab" else "browser"
            // Avoid AuthorizationManagementActivity: on some devices its onResume()
            // runs before redirect forwarding, causing false USER_CANCELED_AUTH_FLOW.
            // The redirect Activity forwards only to our explicit MainActivity.
            if (customTab) {
                val tab = CustomTabsIntent.Builder().build()
                tab.intent.setPackage("com.android.chrome")
                tab.launchUrl(activity, request.toUri())
            } else {
                activity.startActivity(Intent(Intent.ACTION_VIEW, request.toUri())
                    .addCategory(Intent.CATEGORY_BROWSABLE)
                    .setPackage("com.android.chrome"))
            }''')
# We keep AppAuth's token exchange and AuthState, and validate request/redirect ourselves.
change(k,
       "    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {",
       '''    /** Receives an explicit internal callback from YouTubeRedirectTraceActivity.
     * No complete OAuth URI, authorization code, verifier or state is logged.
     */
    fun onRedirect(uri: Uri?) {
        if (redirectHandling) return
        redirectHandling = true
        val request = try {
            activeRequest ?: readPendingRequest().takeIf { it.isNotBlank() }
                ?.let { AuthorizationRequest.jsonDeserialize(it) }
        } catch (_: Exception) { null }
        if (request == null) {
            fail("AUTH_CHROME_SESSION_LOST", "인증 요청 정보가 종료됐어요. Chrome에서 다시 연결해 주세요.")
            return
        }
        if (uri == null || uri.scheme != REDIRECT_SCHEME || uri.path != "/oauth2redirect" ||
            request.clientId != CLIENT_ID || request.redirectUri != REDIRECT ||
            request.configuration.tokenEndpoint != TOKEN) {
            fail("AUTH_CHROME_REDIRECT_INVALID", "OAuth 복귀 주소가 올바르지 않아요.")
            return
        }
        val returnedState = try { uri.getQueryParameter("state") } catch (_: Exception) { null }
        if (request.state.isNullOrBlank() || returnedState != request.state) {
            fail("AUTH_CHROME_STATE", "OAuth 복귀 state가 요청과 일치하지 않아요. 다시 로그인해 주세요.")
            return
        }
        val oauthError = try { uri.getQueryParameter("error") } catch (_: Exception) { null }
        if (oauthError != null) {
            val category = if (oauthError in setOf("access_denied","invalid_request","invalid_scope",
                "unauthorized_client","invalid_client")) oauthError else "oauth_error"
            fail("AUTH_CHROME_OAUTH", "Google에서 인증 승인을 완료하지 않았어요.",
                mapOf("oauthError" to category))
            return
        }
        if (uri.getQueryParameter("code").isNullOrBlank()) {
            fail("AUTH_CHROME_NO_CODE", "Google 복귀 응답에 인증 코드가 없어요.")
            return
        }
        val response = try { AuthorizationResponse.Builder(request).fromUri(uri).build() }
            catch (_: Exception) {
                fail("AUTH_CHROME_RESPONSE", "Google 인증 응답을 해석하지 못했어요.")
                return
            }
        val attempt = epoch
        val state = AuthState(response, null)
        try {
            service.performTokenRequest(response.createTokenExchangeRequest()) { token, error ->
                handler.post {
                    if (attempt != epoch) return@post
                    if (token == null || error != null) {
                        oauthFailure(error, "token")
                        return@post
                    }
                    state.update(token, null)
                    if (state.accessToken.isNullOrBlank() || state.scopeSet?.containsAll(SCOPES) != true) {
                        fail("AUTH_CHROME_SCOPE", "채널 조회·업로드 권한을 모두 허용한 뒤 다시 연결해 주세요.")
                        return@post
                    }
                    try {
                        // Persist token state before resolving Flutter UI. Survives process restart.
                        writeStore(state.jsonSerializeString())
                        take()?.success(metadata(state))
                    } catch (_: Exception) {
                        fail("AUTH_CHROME_STORAGE", "인증 정보를 암호화해 저장하지 못했어요.")
                    }
                }
            }
        } catch (_: Exception) {
            oauthFailure(null, "token")
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {''')

receiver="native/android/YouTubeRedirectTraceActivity.kt"
change(receiver,
       "import android.os.Bundle\nimport net.openid.appauth.RedirectUriReceiverActivity",
       "import android.os.Bundle\nimport android.app.Activity\nimport android.content.Intent")
change(receiver,
       "class YouTubeRedirectTraceActivity : RedirectUriReceiverActivity() {",
       "class YouTubeRedirectTraceActivity : Activity() {")
change(receiver,
       '''        super.onCreate(savedInstanceState)
    }
}''',
       '''        // The AppAuth management Activity is deliberately bypassed.
        // Send the callback to our own existing Activity, without exposing it to other apps.
        val incoming = Intent(this, MainActivity::class.java)
            .setAction(MainActivity.ACTION_CHROME_OAUTH_REDIRECT)
            .setData(uri)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        startActivity(incoming)
        finish()
    }
}''')

main="native/android/MainActivity.kt"
change(main,
       '''    private val youtubeChromeDelegate = lazy { YouTubeChromeAuth(this,
        { readAiKey("youtubeChrome") },
        { value -> saveAiKey(value,"youtubeChrome");check(prefs.edit().commit()) }) }''',
       '''    private val youtubeChromeDelegate = lazy { YouTubeChromeAuth(this,
        { readAiKey("youtubeChrome") },
        { value -> saveAiKey(value,"youtubeChrome");check(prefs.edit().commit()) },
        { readAiKey("youtubeChromePending") },
        { value -> saveAiKey(value,"youtubeChromePending");check(prefs.edit().commit()) }) }''')
change(main,
       "class MainActivity : FlutterActivity() {\n",
       '''class MainActivity : FlutterActivity() {
    companion object { const val ACTION_CHROME_OAUTH_REDIRECT = "com.local.shorts_studio.CHROME_OAUTH_REDIRECT" }
    private fun consumeChromeRedirect(incoming: Intent?): Boolean {
        if (incoming?.action != ACTION_CHROME_OAUTH_REDIRECT) return false
        youtubeChrome.onRedirect(incoming.data)
        // Do not retain the authorization code URI in the Activity's current intent.
        setIntent(Intent(this, MainActivity::class.java))
        return true
    }
''')
change(main,
       '''    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); if(savedInstanceState==null) acceptShare(intent) }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); acceptShare(intent) }''',
       '''    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!consumeChromeRedirect(intent) && savedInstanceState == null) acceptShare(intent)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (consumeChromeRedirect(intent)) return
        setIntent(intent); acceptShare(intent)
    }''')

d="lib/youtube_chrome.dart"
change(d,
       "          'AUTH_CHROME_AFTER_REDIRECT' => 'OAuth 복귀 URI는 도착했지만 AppAuth가 완료하지 못했어요.',",
       """          'AUTH_CHROME_AFTER_REDIRECT' => 'OAuth 복귀 URI는 도착했지만 AppAuth가 완료하지 못했어요.',
          'AUTH_CHROME_SESSION_LOST' => '인증 요청 정보가 사라졌어요. Chrome에서 다시 연결해 주세요.',
          'AUTH_CHROME_REDIRECT_INVALID' => 'OAuth 복귀 주소 검증에 실패했어요.',
          'AUTH_CHROME_RESPONSE' => '인증 응답을 해석하지 못했어요.',
          'AUTH_CHROME_NO_CODE' => '인증 응답에 코드가 없어요.',
          'AUTH_CHROME_OAUTH' => 'Google에서 인증 오류를 반환했어요.',""")

t="test/youtube_chrome_test.dart"
change(t,
       "  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {",
       """  test('Direct redirect validation error stays redacted', () async {
    failure = PlatformException(code: 'AUTH_CHROME_STATE',
      details: {'code': 'private-authorization-code', 'state': 'private-state'});
    await expectLater(youtube().connectChrome(), throwsA(isA<YouTubeFailure>()
      .having((e) => e.message, 'message',
        allOf(contains('AUTH_CHROME_STATE'), isNot(contains('private-authorization-code')),
              isNot(contains('private-state'))))));
  });

  test('Chrome disconnect uses local Chrome grant and resets confirmation', () async {""")

doc="YOUTUBE_CHROME_AUTH.md"
change(doc,
       "# 휴대폰 Chrome 직접 인증 — 0.19.2",
       "# 휴대폰 Chrome 직접 인증 — 0.19.3")
change(doc,
       "## 0.19.2 OAuth 복귀 수신 진단",
       """## 0.19.3 직접 URI 복귀 처리
- 실제 기기에서 OAuth 코드가 수신됐지만 AppAuth AuthorizationManagementActivity가 USER_CANCELED_AUTH_FLOW를 반환한 것이 확인됨.
- 인증 요청 URL을 Chrome 또는 Chrome Custom Tab에 직접 실행하고, Android receiver에서 내부 MainActivity로 명시적 전달. AuthorizationManagementActivity의 onResume 취소 경로를 사용하지 않음.
- 복귀 URI는 Kotlin에서 client ID/redirect URI/state 확인, AppAuth AuthorizationResponse.Builder로 파싱, PKCE 검증자가 보존된 TokenRequest로 토큰 교환. Refresh token은 기존 Android Keystore 암호화 저장.
- 원본 URI, 인증 코드, state, 토큰은 로그/진단에 남기지 않음. 미완료 AuthorizationRequest(상태 및 PKCE verifier 포함)는 Android Keystore 암호화 저장 후 연결 성공/실패 시 삭제. 앱 프로세스가 Chrome 사용 중 종료되더라도 요청 정보 복구 가능.
- 테스트/CI 통과와 실기기 Google 인증 완료는 다른 문제이며 반드시 재검증.

## 0.19.2 OAuth 복귀 수신 진단""")

version="pubspec.yaml"
info=original[version].decode("utf-8")
match=re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$",info)
if not match:raise RuntimeError("Expected pubspec version not found")
change(version,match.group(0),"version: 0.19.3+52")

# Verify no secrets are added to any unencrypted diagnostic sinks by this patch.
with ZipFile(tmp,"w") as z:
    for item,data in entries:
        replacement=patched.get(item.filename)
        z.writestr(item, replacement.encode("utf-8") if replacement is not None else data)
os.replace(tmp,src)
print("Updated source ZIP:", sorted(patched))
