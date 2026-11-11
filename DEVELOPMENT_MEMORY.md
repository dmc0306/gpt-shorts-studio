## 0.19.0 — External Chrome with Android public OAuth client

- User explicitly requires phone app button → installed Chrome app → Brand selection → app return, with no PC/ADB/server. Supplied public Android client ID 337875283119-som1inoqhtgpf1jvkk4b31tg46rub1ag.apps.googleusercontent.com and confirmed Custom URI scheme option exists. Must enable/save that option in Google Cloud; do not ask for web secret.
- Correct earlier overstatement that a server is mandatory: Google official 2023 Custom URI scheme restrictions guidance documents Android opt-in. Current generic OAuth docs sometimes say unsupported by default; require console opt-in and live validation rather than claiming guaranteed support.
- AppAuth 0.11.1 verified against Maven metadata/source. Use Android public client, Google fixed endpoints, S256 PKCE, state, reverse-client-ID redirect scheme, external signed Chrome browser matcher excluding Custom Tabs. No identity/OpenID/Drive scopes. Request offline access; store only completed AuthState with existing Android Keystore AES-GCM and flush preferences.
- Refresh uses AppAuth fresh-token handling with fixed endpoint/redirect/client validation and no client secret; manual forced-refresh check added. Missing refresh grant blocks enabling automatic upload. Actual channel confirmation/target validation and private/resumable upload preserved. New login clears automatic confirmation before granting access.
- Opening settings no longer performs personal Google Sign-In first. Chrome is primary; legacy server/PC/native probe controls moved to an expansion section. Native probes remain diagnostic.
- Tests cover public Chrome bridge without PC/server/Google sign-in calls, persistence/restoration, forced refresh, changed-channel deconfirmation, no-refresh gate, redacted failures and disconnection. Existing legacy cancellation settings test expands advanced section before editing.
- Brand picker availability, Google callback/token exchange/refresh and real upload require device validation. Do not report as verified from mocks or compilation. Login interrupted by process death must restart; no unencrypted pending tokens.

## 0.18.1 — Preserve automatic Google authorization exit diagnostics

- Actual user device observation: selecting Gmail closed the Google UI automatically; no Brand identities were shown. AUTH_NATIVE_CANCELLED was our own blanket classification, not evidence of explicit user cancellation or SDK status 16.
- Parse any returned Intent with getAuthorizationResultFromIntent even when Activity resultCode is canceled, so SDK ApiException status is preserved. Null Intent is AUTH_NATIVE_NO_RESULT (cause unknown). Explicit app cancellation has a separate code/origin. Never copy raw Intent extras, exception messages, OAuth URLs or credentials.
- Copy safe diagnostic fields only: SDK status, activity result/data presence/origin, selected scope mode, selection flag, public package/certificate SHA-1 and Play services version. Report metadata does not claim the chooser exposed Brand identities.
- Default probe now requests readonly only; optional readonly+upload comparison and SELECT_ACCOUNT on/off allow isolating scope/chooser effects without another APK. Both paths remain read-only API probes and do not change upload preferences.
- Regression tests preserve returned SDK diagnostics for canceled activity results, unknown no-data exit, redaction and explicit scope/selection arguments. Actual Google completion/Brand support remains unverified until device report.

## 0.18.0 — Android direct authorization diagnostic

- User verified that explicitly selecting the Brand channel in the web API Explorer returns the intended channel. The remaining unknown is Android account/Brand chooser behavior, not public channel existence.
- Added a separate read-only diagnostic using native AuthorizationClient with play-services-auth 22.0.0. It requests only YouTube readonly/upload scopes, opts out of including previously granted scopes, and sets Prompt.SELECT_ACCOUNT without first calling GoogleSignIn.authenticate or pinning a personal account. Verified methods against official docs and the actual 22.0.0 AAR.
- Google controls whether Brand identities appear; resolutionShown records only that Google's PendingIntent was launched, not that a Brand picker was available. Do not label APK compilation or a mocked channel response as live Brand success.
- Test screen is separate from normal connection preferences: no authMode switch, automatic setting changes, refresh tokens, token persistence, MP4 upload or server dependency. Token stays in the private method channel/Dart memory for one channels.list GET. Copy report includes only safe diagnostics, channel name/ID and no token/raw OAuth response.
- Bound pending requests, cancellation/timeout and stale-callback generation guard. Existing media picker callbacks and legacy authentication paths preserved. Regression tests cover GET-only lookup, zero channels, native developer error and response redaction.

## 0.17.1 — Keep authentication settings usable after cancellation

- Initial 0.17.0 Actions analysis/tests/APK/signature passed. Final review caught an over-broad text edit disposing the server field controllers in the cancel callback. Removed it and added a UI test that cancels then edits the server address. Only screen disposal releases controllers.
- CI 41280729760: 101 Flutter tests passed, new cancel-settings UI test failed because scrollUntilVisible matched multiple Scrollables (outer ListView and inner text-field scroll views). Target the outer Scrollable explicitly; do not remove the cancellation/edit regression.
- CI 41280920935: subsequent test failure was Finder.first evaluated before the lazy ListView rebuilt an offscreen TextField. Use a label-specific predicate without first so scrollUntilVisible can search across lazy children.
- Label legacy PC connection explicitly so its ADB requirement cannot be confused with the primary server mode.

## 0.17.0 — HTTPS server authentication

- User requested a continuously available authentication server instead of the PC broker. Added single-owner Docker/Caddy service using the shared PKCE/state/channel validation protocol with configurable HTTPS callback and server identity namespace.
- Fernet encrypted persistent grants, fail closed on invalid key/ciphertext; client secret remains server environment only. API pairing key stored in Android Keystore; access tokens cached only in app memory. MP4 remains direct phone→YouTube.
- Host and browser-origin validation, no-redirect clients, bounded server threads/rate buckets, redacted errors/no access logs. Private .env/connection.txt and encrypted data excluded from ZIP/git/Docker context.
- Server regression covers restart+refresh, ciphertext tampering/wrong key, changed channel and HTTP authentication restrictions. Preserve PC flow tests. No live deployment or Google consent has been completed; host/domain are still required.
- Google external/testing refresh tokens with YouTube scopes can expire after seven days. Do not promise permanent once-only authorization.

## 0.14.0 — 최종 크롭·구간 자막 검사 / 검색 카테고리

- 자동 제작은 AI가 사용 구간을 선택한 뒤 그 시간 안의 중앙 정사각형 이미지를 실제로 잘라 기기 OCR을 실행합니다. 잘려 사라지는 상하/좌우 글자와 구간 밖 글자는 제외 사유가 아닙니다. 남는 글자 조각은 경계 검사로 보완합니다. AI의 sourceText/edited 판단 지침도 같은 표시 영역·시간 기준으로 맞춥니다. 간판/워터마크 구별, 기타 편집·AI 의심 기준은 유지합니다. OCR은 최대 16개 샘플 프레임 검사여서 짧은 자막을 놓치거나 현장 글자를 오인할 수 있습니다.
- 기기 OCR의 원본 길이 제한 30.1초를 60.1초로 수정합니다. 선택 범위·crop 인자와 반환 범위를 확인하고 불완전한 검사를 통과 처리하지 않습니다. 저장 재개 체크포인트에 크롭 검사 완료를 기록하고 이전 검사 기준의 체크포인트는 무효화합니다.
- 후보 먼저 보기는 구간 선택 전이므로 원본 전체 시간의 크롭 영역을 검사하되 글자 의심만으로 영구 제외하지 않고 안내합니다. 실제 제작에서 선택 구간을 다시 검사합니다. 생성 API 없이 후보 재생·평가 기능 유지.
- 검색 카테고리 8개: 사람·관계 반전 / 놀라운 실력 / 신기한 영상 / 귀여운 영상 / 웃긴 영상 / 힐링·감동 / 스포츠·묘기 / 생활·음식. 카테고리별 한영 36개, 총 288개 키워드. 혼합 추천은 기존 세 중심 주제만 섞고, 단일 카테고리는 해당 주제의 대기 후보와 검색어만 사용합니다. 선택은 보고서에 저장하며 제작 중에는 변경하지 않습니다. 실행당 검색 9회/basic/결과 20개 제한 유지.
- AI에도 해당 카테고리 지침을 전달하고 선택 카테고리 범위 밖의 유형은 제외합니다. 귀여움·힐링에는 억지 반전을 요구하지 않으며 구체적인 볼 지점을 설명하도록 합니다. 사연/관계/효능 추측 금지. 기존 저장함/수집함 카테고리·평가/기록은 보존하고 새 카테고리를 추가합니다. 후보 검색은 실제 영상 내용 확인 전이므로 정확한 소재 보장은 아닙니다.
- 세로/가로 크롭 영역·사용 시간 밖 글자·남은 글자 조각·카테고리 키워드/AI 지침·귀여운 후보만 준비하는 UI 및 크롭 검사 인자 회귀 테스트 추가. 실기기 OCR·실제 API 판정 확인은 별도입니다.

## 빌드 환경 오류 기록 — 2026-10-12

- 0.13.2 CI 38245987105: 분석·테스트 통과 후 Gradle 9.3.1-all.zip의 공식 GitHub 배포 다운로드에서 HTTP 504. 앱 소스 컴파일 오류가 아닌 외부 다운로드 장애로 확인. 동일 커밋의 실패 작업 재실행으로 확인하며 소스나 서명 설정을 불필요하게 변경하지 않습니다.

## 0.13.2 — 준비된 후보 연속 재생·평가

- 후보 먼저 보기에서 준비된 원본을 연속 재생하며 평가할 수 있는 버튼을 연결합니다. 개별 원본 재생/평가도 유지합니다. 후보 준비 테스트에서 버튼 접근을 검증합니다. 실제 휴대폰 재생·평가 품질은 별도입니다.

## 0.13.1 — 대기 후보 우선 처리 수정

- CI 38245380240: 분석 통과 후 후보 확인 회귀 테스트 실패. 같은 주제 대기 원본 5개가 있는데 1개 처리 후 다음 주제에서 검색하여 테스트 HTTP 400 발생. 회전 순서에서 주제별 대기 확인과 신규 검색을 섞던 실제 호출 순서 문제였습니다.
- 세 주제의 사용 가능한 대기 후보를 모두 먼저 확인하고 없을 때만 신규 검색합니다. 부정 평가/이미 시도한 후보는 계속 건너뜁니다. 기존 5개 후보 확인 테스트를 그대로 유지해 검색/분석/내보내기 없이 끝나는지 검증하며 전체 CI 재확인합니다.

## 0.13.0 — 사람·실력·기발함 중심 소재 선별

- 혼합 주제를 사람·관계 반전 / 놀라운 실력 / 기발한 상황으로 변경하고 한영 상황 검색어 108개를 교체합니다. 참고 채널의 영상 자체를 복사하지 않고 소재 유형을 검색 기준으로 사용합니다. 새 후보는 새 주제로 수집하며 과거 저장본·평가·카테고리는 보존합니다. 기존 동물/아기 대기 후보는 새 자동 주제로 선택하지 않습니다.
- 자동 제작은 원본 5~60초를 길이 사전 검사 후 다운로드합니다. 동일한 Gemini 영상 요청에서 selection의 도입/핵심 결과/핵심 시간/유형/채택 이유와 연속 5~30초 구간, 제목 세 후보·구간 안 자막을 함께 생성합니다. 구간 범위·핵심 시간·근거·자막 범위를 앱에서 검증합니다. 막연한 귀여움/반복 움직임 대신 구체적인 상황 변화·실력·결과가 없으면 제외합니다. AI 판단과 타임코드는 오류 가능성이 있습니다.
- 기존 자막/OCR/편집본/AI 의심/위험 영상 필터를 유지합니다. 상황극 촬영 자체를 편집본으로 보지는 않습니다. 제목 각 줄 5~11자와 드문 자막/피사체 회피/정사각 크롭은 유지합니다. 30초보다 긴 원본은 영상 분석 사용량이 증가할 수 있습니다. 검색 9회/basic/후보 처리 60개 제한 유지.
- 후보 5개 먼저 보기: 생성 API 없이 다운로드·원본 글자 검사까지 하고 결과에서 원본 재생/4종 평가 후 제작을 재개합니다. 기존 5개 자동 제작은 유지하며 확인을 강제하지 않습니다. 좋은 평가 계정 검색과 유형별 괜찮음/재미없음 평가 횟수를 후속 생성 지침에 함께 반영합니다. 모델 파인튜닝은 아닙니다.
- 결과 카드에서 선택한 장면의 도입·핵심·구간 시간을 확인합니다. 저장 재개 시 선택 구간과 생성 결과를 복원하며 기존 AI 체크포인트는 새 소재 기준으로 무효화합니다. 분석 근거를 저장해 제목·자막 재생성은 영상 재업로드 없이 유지합니다.
- 핵심 장면 시간/근거/구간 밖 자막/선호 기록/후보 확인 시 내보내기 금지·저장 재개 회귀 테스트를 추가합니다. 실제 API·휴대폰의 소재 품질과 선택 타이밍은 별도 확인해야 합니다.

## 0.12.3 — 검색어 108개·검색 편중 개선

- 혼합 3주제별 36개씩 총 108개 검색어. 한국어·영어와 요리/일상/춤/리액션, 고양이/강아지/앵무새/토끼/햄스터/수달/오리, 아기 표정/옹알이/까꿍/형제/부모 상황으로 확장합니다. 기존 사용 기록을 보존하고 실행당 검색 9회/basic/결과 20개 제한을 유지합니다. 추가 AI 검색어 생성 호출은 없습니다.
- 모든 검색어를 한 번 사용한 뒤 과거 성공률만으로 같은 검색어가 반복되는 결함을 수정합니다. 적게 사용한 검색어를 먼저 선택하고 동률이면 성과·평가·빈 검색 기록을 참고합니다. 괜찮음 계정 검색도 고정된 첫 문구 대신 여러 상황을 순환하며 계정 검색/일반 탐색 비율은 유지합니다.
- 검색 성공·다운로드 성공을 보장하지 않습니다. 검색 결과가 프로필/중복뿐이거나 색인이 부족한 경우 기존 검색 진단으로 확인합니다. 5~30초·기존 자막/편집본/AI 판정 조건과 부정 평가 제외는 유지합니다.
- 한영 검색어 수/중복·전체 순환 후 편중·계정 문구 순환 회귀 테스트를 추가합니다.

## 0.12.2 — 검색 0개 진단·검색어 순환·API 구분

- 검색마다 응답 수/중복/개별 영상 아님/모음집/잘못된 항목/새 후보 수와 검색어를 기록·표시합니다. HTTP 200 빈 결과와 응답 형식 오류를 구분하며 API 키·원문 응답은 기록하지 않습니다. 제작 종료는 검색 9회/처리 60개/새 후보 없음/API 오류로 구분합니다.
- 좁은 site:tiktok.com/@ 및 /video/ 검색 조건을 도메인 조건으로 완화합니다. 실제 개별 영상 URL 검증은 유지합니다. 18개 검색어를 덜 사용한 순으로 순환하여 실행마다 같은 9개만 반복하지 않습니다. 검색 최대 9회/basic 설정은 유지합니다. 성공률 보장은 아니며 실제 응답 원인은 새 로그로 확인해야 합니다.
- Tavily 검색 오류는 공급자·HTTP 코드와 키/권한/요청 형식/속도 또는 사용량/서버 오류로 구분합니다. 연결/TLS/JSON/결과 목록 누락도 구분합니다. Gemini 오류에도 공급자·HTTP 코드를 추가합니다. 429만으로 무료 크레딧 소진을 단정하지 않습니다.
- 기존 일시적 AI·네트워크·저장 실패 후보의 대기/재개 처리는 유지합니다. 비공개·접근 제한이나 반복 메타데이터 오류를 무조건 재시도하지 않습니다. 이전 영구 제외 목록은 초기화하지 않습니다.
- 필터 수치 합계와 덜 사용한 검색어 순환·API 진단 회귀 테스트를 추가합니다.

## 0.12.1 — 글자 수 표시 선언 수정

- CI #38에서 flutter analyze 실패: editor.dart 입력창 InputDecoration이 const인데 helperText/errorText가 동적 값이라 invalid_constant. const를 제거했습니다. 동적 카운터를 추가할 때 상위 위젯 const를 함께 확인해야 합니다. 분석·전체 테스트·APK 재빌드를 확인합니다.

## 0.12.0 — 제목 3후보·개별 검증·텍스트 재생성

- API에 호기심형·반전형·드립형 각각 top/bottom을 요청합니다. 공백 포함 화면 문자(grapheme) 기준 상·하단 독립 5~11자 검증. 제목 잘라내기/임의 글자 중간 줄바꿈을 제거하며 모든 후보가 유효해야 적용됩니다. 위반 시 영상 없이 텍스트만 보정(최대 3회 요청), 지속 실패는 기존 문구 유지. 상황/호기심→반전/리액션 구조, 사용자 예시와 한국식 표현·관찰 사실 조건을 적용합니다.
- ai_rules.dart에서 제목 규칙과 자막 규칙을 별도 관리합니다. 직접 입력 시 두 줄 문자 수 표시 및 저장 조건 검증. 초과 입력을 강제로 잘라내지 않습니다.
- 초기 영상 분석에 sceneSummary와 시간/피사체 영역을 요청해 프로젝트에 저장합니다. 편집창 제목 재생성·자막 재생성 버튼은 이 텍스트만 전송하며 영상 재업로드/재분석이 없습니다. 제목 후보 3개 선택, 자막 결과 확인 후 해당 항목만 적용합니다. 원격 업로드 파일은 기존처럼 정리합니다.
- 분석 정보가 없는 기존 프로젝트는 한 번 영상 분석·전체 생성이 필요하며 개별 재생성 버튼에서 자동 업로드하지 않습니다. 자막 재생성은 저장된 장면 범위 안에서만 적용하고 기존 피사체 영역을 유지합니다. 새 장면 분석이 필요하면 전체 생성을 사용합니다. 문구 적용 후 MP4 교체 저장 필요.
- 제목 독립 길이·가족/피부색 이모지·잘림 금지·분석 저장 및 텍스트만 요청하는 회귀 테스트 추가. 기존 임의 재배치/잘림 테스트는 새 요구사항에 맞춰 변경합니다.

## 0.11.2 — 저장함 편집·수정본 교체

- 저장함 카드 탭도 수집함과 동일한 원본 기반 편집 화면을 엽니다. 기존 제목·시간별 자막·구간을 유지하고 저장 버튼은 수정본으로 교체 저장으로 표시합니다.
- 새 MP4 내보내기 및 프로젝트 저장 완료 후 이전 갤러리 MP4를 삭제합니다. 제작 보고서의 저장 주소·제목도 수정본으로 갱신해 연속 재생이 최신본을 엽니다.
- 새 내보내기 실패 또는 프로젝트 저장 실패 시 기존 MP4를 삭제하지 않습니다. 삭제/보고서 갱신 실패 시 새 저장본을 유지하고 오류를 안내합니다. 원본 영상은 삭제하지 않습니다.
- 교체 저장 순서, 프로젝트 저장 실패, 기존 MP4 삭제 실패 회귀 테스트를 추가합니다.

## 0.11.1 — 제작 중 뒤로가기·접근 불가 후보 처리

- 제작 중 뒤로가기: 중단 확인 후 다운로드/AI/내보내기를 취소하고 보고서와 완료본을 유지한 뒤 이전 화면으로 이동합니다. 완료·대기 화면에서는 즉시 돌아갑니다.
- TikTok 상태 10204에 일치하는 영상 데이터가 없으면 PAGE_UNAVAILABLE로 구분하여 동일 페이지 재요청 없이 제외합니다. 실제 삭제/비공개/지역 제한 원인은 이 응답만으로 단정하지 않습니다. 정상 영상 데이터가 있으면 다른 스크립트 상태가 10204여도 진행합니다.
- 반복 실패한 PAGE_METADATA/HTTP400 후보는 재개 큐에 계속 남기지 않고 다음 후보를 찾습니다. 네트워크 일시 오류는 재개 후보로 유지합니다.
- 제작 중 뒤로가기 정리 완료 및 10204 요청 횟수 회귀 테스트를 추가합니다.

## 0.11.0 — 연속 재생 삭제·여러 개 삭제·카테고리

- 연속 재생에서 현재 완성 MP4 삭제 후 다음 영상으로 이어집니다. 마지막 삭제 시 재생창을 닫습니다. 확인창 중 다음 이동을 막고 삭제 실패 시 목록을 유지합니다.
- 수집함/저장함 길게 눌러 여러 개 선택, 현재 검색·카테고리 안의 전체 선택, 선택 삭제 및 일괄 분류 변경. 세 혼합 주제+기타 카테고리. 자동 제작은 주제를 저장하고 기존 보고서 주제로 기타 항목을 보완합니다.
- 저장함 삭제는 갤러리 MP4까지 삭제하며 원본·편집 프로젝트는 유지합니다. 수집함 삭제는 저장본 있는 프로젝트를 저장함에 남기며 저장본 없는 앱 내부 원본·썸네일을 삭제합니다. 외부 가져오기 원본은 삭제하지 않습니다. 확인창에 범위를 안내합니다. 삭제한 저장본은 혼합 보고서에서도 삭제 상태로 동기화합니다. Android에서 앱 소유 영상 접근이 거부되면 오류를 표시하고 항목을 유지합니다.

## 0.10.4 — 드문 자막·낱말 줄바꿈·한국식 반응

- 새 AI 자막은 6초당 최대 1개(15초 최대 3개, 전체 최대 5개), 자막 사이 최소 1.5초 공백, 1개 최대 2.5초, 총 노출 40% 이하로 제한합니다. 핵심 장면에 한국식 웃음/놀람 표현을 자연스럽게 섞도록 지시하며 단독 ㅋ·조롱은 피합니다. 추가 AI 호출은 없습니다.
- 미리보기·PNG 저장에서 같은 낱말 단위 레이아웃을 사용합니다. 글씨 크기는 유지하며 좁은 좌우 영역에 문구가 다 안 들어가면 위/아래 내부 영역을 우선합니다. 두 줄을 넘는 수동 문구는 낱말 경계에서 말줄임합니다. 이미 저장한 MP4는 그대로이며 자막 밀도 변경은 새 AI 생성부터 적용합니다. 자동 제작의 이전 AI 체크포인트는 새 규칙으로 재생성합니다.

## 0.10.3 — 화면 스크롤 회귀 테스트 수정

- CI #32는 분석 통과 후 화면 테스트 2건 실패: 전환율 패널 아래 버튼이 ListView에서 아직 생성되지 않아 ensureVisible/finder가 실패했습니다. scrollUntilVisible로 실제 스크롤 후 재개·연속 재생·필터·저장본 버튼을 확인합니다. 전환율 중복 제거/단계 집계/빈 결과 회귀 테스트도 추가했습니다. APK 빌드 전에 실패한 테스트를 건너뛰지 않고 전체 CI를 재검증합니다.

# Development memory

## Working rules — 2026-10-10

Minimize tokens and routine verification. When a build fails, the user explicitly requests verification: inspect logs, fix the cause, add relevant regression coverage, and verify the resulting CI build. Record recurring failures here.

## Known failures

- 0.5.0 / Actions #13: analysis failed with eight errors in lib/discovery.dart. A nullable Uri local was reassigned in a redirect loop, so its non-null promotion did not survive. Parse into a final local, reject null, then use an explicitly non-null Uri for redirect updates. Added URL-validation and resolver regression tests in test/discovery_test.dart. The tests make no network requests.
- 0.2.4 / Actions #6: source selection changed from downloadAddr to playAddr; an old diagnostic assertion still expected downloadAddr. Update assertions to the current behavior whenever source-selection logic changes. The following #7 build passed.
- Input dialogs: disposing TextEditingController immediately after showDialog completes can precede the dismissal animation. Let the dialog State dispose its own controllers. Actions #11 passed; device confirmation is separate.
- Scrolling the editor: the preview in ListView may unmount, making export layer currentContext null. Keep the export renderer outside the scrolling list and avoid forced null assertions. Actions #12 passed; device confirmation is separate.

CI results and device behavior must be reported separately. Passing CI does not verify TikTok availability, Gemini responses, or actual video output on a device.

## Search model access — 2026-10-10

0.5.1 device screenshot showed zero saved items and a generic model-unavailable error before candidate rows. Search used fixed gemini-2.5-flash-lite; changing the generation model could not change search. Google documentation now restricts 2.5 access to previous active users, despite continued pricing/free-tier listings. Never infer model availability from pricing alone. 0.6.0 replaces discovery with Tavily basic search (separate encrypted key), retains Gemini for video generation, and adds shared settings accessible from batch and editor. Actual provider success still requires the user's configured keys.

## TikTok api-data schema — 2026-10-10

0.6.0 screenshot: search produced candidates but downloads failed with PAGE_METADATA. Reproduced the provided page: Universal state reflow queryData was empty, but a separate script id=api-data contained videoDetail.itemInfo.itemStruct and the matching video ID/playAddr. This is an observed parser omission, not proof of authentication or region restriction. 0.6.1 adds this exact schema to extraction and diagnostics plus a sanitized regression fixture. Preserve ID matching, explicit privacy/download-disabled checks, and trusted HTTPS hosts.

- 0.6.1 작업 환경: 새 페이지 playAddr MP4 다운로드 파일 ffprobe 확인(4,874,547 bytes/H.264/AAC/720×1280/35.712초). 30초 상한 초과 후보는 제외가 정상. 휴대폰 전체 경로는 미검증.

## 0.7.0 자동 보충·백그라운드
- 제외는 길이/적합도 필터 결과. 12개 고정 후보로 끝내지 말고 최대 3차 새 검색어로 보충, 시도한 ID 중복 제거. 무한 반복·API 한도 오류 재시도 금지.
- UI endOfFrame/RepaintBoundary 캡처는 paused에서 기다릴 수 있으므로 자동 제작은 공통 Canvas painter로 프레임 없이 PNG 생성.
- Android foreground dataSync/mediaProcessing 서비스, 알림 중단, partial wake lock(1시간), 종료/취소/timeout 정리. 홈·잠금 지원 범위이며 강제 종료/프로세스 종료 재개는 미지원. 실기기 검증 전에는 검증 완료로 표현하지 않기.

## 2026-10-10 — 검색 효율과 원본 품질
- 사용자는 웃긴 영상 혼합 자동 수집을 유지하며 모든 영상 크기 통일을 위해 기존 중앙 정사각 크롭을 유지하도록 요청했다. 잘림 방지/비율 보존 전환은 추가하지 않는다.
- Tavily basic, 자동 옵션 비활성, 20개 유효 결과 보관, 영속 대기열, 부족한 주제만 검색, 처리 ID 중복 방지, 검색어·계정 성과 기록을 적용한다. 검색 점수는 재미나 인기도가 아니다.
- 편집본·AI 의심 여부는 기존 영상 분석 요청에서 함께 평가한다. 애매한 경우 제외하며 오판 가능성을 명시한다. 검색의 original/real 단어는 원본을 보장하지 않는다.
- 피드백은 로컬에 기록하며 실제 파인튜닝이나 학습 데이터 외부 전송을 자동 실행하지 않는다. 사용자 취향과 기술 품질을 분리해 평가하고, 채널/영상 중복이 없는 고정 평가셋으로 개선을 측정해야 한다.
- 이전 0.7.0 CI #17 성공 확인: 분석·테스트·APK, 73.2MB artifact. 일반 작업은 검증 비용 최소화, 빌드 실패 예외 검증 정책은 계속 적용한다.

## 2026-10-10 — AI 응답 오류 진단
- 0.8.0 실기기에서 여러 영상이 일반 AI 처리 오류로 실패했다. 실제 응답 원문/종료 사유가 없어 원인은 확정할 수 없다. 네트워크로 단정하지 않는다.
- 응답 구문·타입·빈 출력·MAX_TOKENS를 구분하고 단계별 안전 코드로 표시한다. 일시적 AI 실패 후보는 영속 대기에 보존하되 같은 실행에서 무한 재시도하지 않는다. 내부 CLIENT 오류는 비용 낭비를 막기 위해 전체 중단한다.
- 일반 검증 절약 선호에도 제보한 실패 경로는 실제 스키마 구성/응답 파싱 회귀 테스트를 포함한다.

- 후속 CI #19에서 실제 원인 재현: schema required의 List<String>에 raw List.addAll을 호출하면서 인수가 List<dynamic>으로 생성되어 Iterable<String> 타입 오류. 문자열 목록에 원소 하나씩 add하는 0.7은 통과했지만 addAll로 바꾼 0.8부터 발생했다. (schema['required'] as List<String>).addAll(<String>[...])로 고정한다. JSON 스키마 실제 구성과 jsonEncode까지 테스트해야 이 회귀를 잡을 수 있다.

## 2026-10-10 — 0.9.0 오류 복구와 공통 설정
- 사용자 제보: PAGE_HTTP_400 / PAGE_METADATA / AI 제목 형식 오류, 긴 원본을 내려받은 뒤 제외하는 비효율, 결과 재생·설정 분산.
- 제목은 정확히 2줄이 아니면 영상 전체를 실패 처리하던 것이 원인. 줄바꿈 자동 정리, 긴/빈 제목은 텍스트만 1회 재생성, 실패 시 retryable 후보 보존. 원문/키/서명 URL을 진단이나 메모리에 넣지 않음.
- 페이지의 ID 일치 영상 duration 검사 후 미디어 요청. 없는/유효하지 않은 길이는 추측하지 않고 파일 검사로 대체. 5~30초와 중앙 크롭·출력 배치는 유지.
- HTTP400/metadata는 동일 공개 페이지 1회 재확인만 허용. 인증/다운로드 금지/403/429를 우회하거나 서버가 제공하지 않은 주소를 만들지 않음. 지속 오류는 다음 후보로 진행.
- 혼합 결과에 앱 내 원본/저장본 재생·편집, 상태 요약·필터·접는 진단, 모든 설정을 공통 앱 설정으로 통합.
- 사용자 고정 서명 설정 완료 보고와 별개로, 저장소 공개 workflow의 최종 수정은 2026-10-09로 확인됨. 이번 변경에서 workflow/Secrets/키 파일은 수정하거나 읽지 않음. 고정 서명 연결 확인 없이 업데이트 설치 성공을 보장하지 말 것.

## 2026-10-10 — 0.9.1 고정 서명 연결
- 사용자 요청으로 ANDROID_KEYSTORE_BASE64를 실제 CI 서명에 연결. Settings에서 Secret 이름 4개가 등록되었음을 확인했으며 값은 읽거나 변경하지 않았음.
- 복원은 runner temp 0600, 비밀번호는 환경변수. bootstrap Gradle studio signing을 debug/release에 연결. CI 서명 누락 시 임시 debug 키로 성공 처리하지 않음.
- APK 업로드 전에 apksigner 검증과 키의 공개 인증서 SHA-256 비교. 빌드 이후 키 삭제. ZIP에서 jks/keystore/key.properties 및 빌드 결과 제외.
- 첫 고정 키 APK는 기존 CI 임시 debug 인증서와 다를 수 있어 최초 삭제/재설치가 필요. 이후 같은 키와 증가한 버전 번호 유지. 키/비밀번호/개인 인증서 DN을 메모리나 로그에 기록하지 않음.

- 서명 검사 회귀: apksigner v3.1은 `Signer (minSdkVersion=..., maxSdkVersion=...)`로 표시한다. 번호 형식만 파싱하면 올바른 서명도 실패한다. 두 형식의 인증서 SHA-256을 모두 읽고, 모든 고유 서명 인증서가 지정 키와 같을 때만 통과. source stamp/public key는 제외. 형식·중복 범위·다른 키·다중 서명·누락 테스트 추가.

## 2026-10-10 — 0.9.2 제목·원본 자막·장면별 위치
- 사용자: 상단/하단 제목 각 11칸. 공백·문장부호 포함, grapheme 단위. AI 생성/보정·수동 입력·저장·미리보기/출력 모두 적용. AI 긴 제목은 의미를 유지한 재작성 1회; 무단 절단은 수동 입력 제한에만 사용.
- 제보 사진: 하단 영어 원본 자막이 포함됐지만 기존 edited=false 판정으로 저장 성공. 원본 자체 자막은 편집본 제외. AI sourceText(present/absent/uncertain)를 별도 필수 응답으로 받고 present/uncertain/누락은 통과하지 않음.
- AI 전 기기 bundled ML Kit 한국어/Latin OCR, 원본 전체에서 최대16장 균등 샘플. 글자 내용은 로그/프로젝트에 기록하지 않고 위치/크기/문자수로 큰 합성 글자 의심을 제외. 작은 플랫폼 워터마크는 제외 기준에서 제외. 표지판 오인/짧은 순간 누락 가능. 검사 실패는 다음 실행 후보로 보존, 성공 처리하지 않음. 외부 AI 추가 호출 없음.
- 각 시간별 자막에 구간 전체 피사체 합집합 bbox를 원본 정규화 좌표로 요청. 중앙 crop/fit 변환 후 실제 자막 크기 및 여백과 충돌하지 않는 위/아래/좌/우를 선택. 불확실/전체 점유는 영상 밖 하단 검정 여백. 장면 경계에서 위치 변경, 동일 자막 중 흔들림 방지. 기존 저장 자막은 legacy 위치 보존. 새 수동 자막 기본 밖, 직접 위치 변경 가능.
- 편집/자동 제작은 공통 painter로 PNG를 생성해 백그라운드 화면 프레임과 무관. 네이티브 시간별 오버레이 topPx 전달, 위치는 저장 후 재개 시 복원. AI 피사체 좌표 자체의 정확도는 보장되지 않으며 실기기 확인 필요.
- CI 서명 도구 사람이 읽는 출력 형식 문제는 certificate PEM→DER 해시 비교로 변경. 검증 통과 전 아티팩트 공개하지 않음. 실제 CI 완료 상태는 실행 로그로 확인.

- Dart 조건식에서 `edge?.25:.45`는 null-aware 연산자로 해석된다. 소수 리터럴 앞 삼항 연산자는 `edge ? .25 : .45`처럼 공백을 명시. CI #24 분석에서 발견하여 수정. OCR 회귀 테스트가 해당 정책을 import하여 컴파일을 검증.

## 2026-10-11 — 0.9.3 사용자 제약
- 자막은 위/아래 검정 여백 금지. 내부 위치만 선택하고 자동 배치에서 안전한 위치가 없으면 숨김. 기존 outside도 내부 재배치/숨김. 사용량 2% 요청: 검증 실행 및 CI 결과 대기 생략.

## 2026-10-11 — 0.9.4 자막 미표시 수정
- 0.9.3에서 좌표 누락/보수적인 합집합 bbox가 모든 내부 후보와 충돌하면 자막을 숨겨 미표시 발생. 좌표 누락은 내부 하단, 충돌 시 후보 중 최소 겹침 비율 위치로 표시. 피사체 회피는 최선 노력이며 완전 회피 보장 불가. AI 프롬프트에서도 자막 생략 지시 제거. 검정 여백 금지 유지, 검증 생략 요청 유지.

## 2026-10-11 — CI #27 압축 구조 실패
- ZIP에 shorts_studio/ 접두어를 잘못 추가해 app/tool/signing.py가 없어 서명 키 복원 단계 실패. workflow는 unzip -d app 후 app에서 실행하므로 ZIP 파일 이름은 프로젝트 기준 상대 경로로 저장해야 함. pubspec.yaml, tool/signing.py, tool/bootstrap.py, lib/main.dart 최상위 존재를 매번 패킹 후 assert.

## 2026-10-11 — 0.10.0 개선 범위
- 사용자: 개선 1/2/4/5 적용, 3(피사체 회피용 글씨 축소·문구 단축)은 제외. 기존 44px·영상 내부 후보 배치 그대로.
- 평가를 계정/검색어 순위에 반영. 연속 재생과 평가, 부정 평가 완성본 교체(원본 MP4 삭제 없음), 남은 결과 보존하고 총 5개 채우기.
- OCR/승인된 AI 단계 체크포인트는 배치 보고서와 함께 로컬 저장. clip ID/원본 경로/크기/수정시각/길이/모델로 무효화. 다운로드 일시 오류 및 렌더 오류는 대기 유지. 파일 삭제 시 다시 다운로드. 강제 종료 자동 실행은 아님, 버튼으로 재개.
- 자막은 행동 변화·반전 선공개 금지·같은 의미 반복 금지 프롬프트 강화. 추가 AI 호출 없이 적용. 실제 타이밍 정확도 보장 아님.

- CI #29: 분석 및 44개 테스트 통과, 신규 재개 테스트는 export 호출 0으로 실패. 실제 파일 IO를 fakeAsync 바깥에서 시작하고 완료를 기다리도록 runAsync 안에서 버튼 탭과 단계 완료 대기를 함께 처리. 추가 진단은 저장 보고서(키 없음)만 테스트 실패 사유로 첨부.

## 2026-10-11 — 0.10.1 제목 최소 길이
- 사용자: 상/하단 각 최소 5자, 기존 최대 11자 유지. 두 줄 필수, 공백·문장부호 포함 grapheme. 바깥 공백으로 최소 길이 채우기 금지. AI 생성/보정·수동 저장 검사 및 체크포인트 재사용 검사 적용. 입력 도중 최소 길이 미달 허용, 저장 시 제한.

## 2026-10-11 — 0.10.2 전환율·계정 탐색
- 요청 두 가지: 단계별 전환율 및 좋은 평가 계정 중심 탐색. URL 영상 ID 중복 제거, 현재 보고서+대기 후보 분모, 단계 검사 bool 영속 저장. 기존 MP4 저장 결과는 모든 단계 통과로 집계. 대기는 실패가 아님.
- 주제별 괜찮음 평가·긍정 비율>0.5 계정 선택. 평가/저장률 순위, 주제별 2회 타깃 후 1회 일반 검색. 계정핸들 정규식 검증 후 site 필터 검색. 전체 검색/API 한도 증대 없음. 계정 전체 목록 수집이나 인기 보장 아님.


## 2026-10-31: preserve the 0.14 source when integrating YouTube

- Local shorts_studio was the initial 0.1.0 scaffold. Using it as the integration base omitted existing TikTok/AI/batch features. Base changes on the repository source ZIP 0.14.0+40 instead, preserve all model fields and existing discovery/download logic, and bump to 0.15.0+41.
- Keep YouTube errors separate from render success. Regression: the fifth MP4 and saved-count=5 survive a failed Google connection; retain the original candidate checkpoints and reports.
- Persist resumable sessions by saved URI and bind them to email and channel ID. Query channels.list mine=true and reject a changed target before sending bytes. youtube.readonly is required in addition to youtube.upload.
- Windows sandbox builds use workspace SDK/cache copies, in-process Kotlin, JDK 21, and FLUTTER_SUPPRESS_ANALYTICS=true. Restart the workspace Gradle daemon after switching Android SDK roots to avoid stale absolute SDK paths.
- Local validation: Flutter tests 83 passed, upload protocol scenarios 9 passed, APK build passed. Live Google/TikTok/YouTube network behavior is not covered by mocks.


## 2026-10-31: Google channel-change authorization and session policy

- Re-authenticating without disconnect reused the previous Google authorization. Reconnect now clears the old token, calls disconnect to revoke access, then authenticates and authorizes again. Revocation failure clears local confirmation and stops; a changed channel on refresh disables automatic upload. Three platform-stub regression tests cover call order, failure and changed-target confirmation. Tests: 86 passed; static analysis clean. Actual desired-channel selection remains a device confirmation step.
- User config.toml changed approval_policy to on-request, but the active GitHub MCP tool still returned requires approval / policy never. No remote write occurred. The running session's effective policy must be refreshed before retrying repository writes; do not switch to a different write mechanism to evade the approval requirement.


## 2026-10-31: empty YouTube channel response

- A single generic exception hid empty results, multiple results and malformed JSON shape. 0.15.2 distinguishes them and accepts empty nextPageToken for a single channel. Regression tests cover separate result kinds and omitted items with totalResults=0; 89 tests passed, analysis and APK build passed, versionCode 43 installed as update.
- Actual device redacted metadata: kind=empty, count=0, total=0, hasNext=false. Automatic upload remains false. This is not evidence the channel does not exist. Ownership/delegated Studio permissions and Brand Account OAuth identity still need user confirmation. Do not create new Cloud projects or guess an upload destination. No Google consent controls were automated.

## 2026-10-31: mobile external-browser OAuth with a PC broker (0.16.0)

- User clarified: authenticate in the phone browser, optionally using its desktop-site view; video collection, editing and upload remain Android features. Desktop-site UI alone does not change OAuth client type or guarantee Brand Account selection. Use the existing Web OAuth client with exact callback http://127.0.0.1:8765/oauth/callback, not an Android custom-scheme/Desktop-client workaround.
- PC broker listens only on loopback; existing authorized ADB reverse tunnel connects the phone. Provision a random pairing key directly into app-private files, then import into Android Keystore-encrypted preferences. Browser APIs reject Origin/Sec-Fetch-Site requests, enforce Host, disable redirects and require the pairing key. Browser callback is bound to a one-use state and PKCE S256 with a ten-minute lifetime. No request/code/token logs.
- Web client secret and refresh token stay in current-user Windows DPAPI storage under ignored .local/youtube-auth. The phone receives only short-lived access tokens. Revalidate channels.list mine=true on confirmation/upload and token refresh; bind sessions to the PC client/channel identity. Switching channel disables automatic uploads until reconfirmation. Google consent remains manual.
- Sandbox DPAPI CryptProtectData returns code 2 because the restricted execution profile has no usable user credential profile. Fail closed; do not write plaintext or weaken to machine-wide protection. Start the provided batch file in the normal Windows user environment. Actual DPAPI round-trip test is explicitly skipped only for code 2; failure-with-no-plaintext coverage passes.
- Validation: 97 Flutter tests pass, analysis clean; Python broker checks 9 passed and 1 skipped for unavailable DPAPI profile. Live Google login/Brand Account selection and actual YouTube upload still require the user's Web client JSON and callback registration. Do not report those as verified.
- Existing signing test assumed POSIX chmod bits on Windows, where stat returns 0666 despite chmod(0600). Keep exact 0600 assertion on the Linux CI platform; retain all bytes/secret/path assertions on Windows. No CI signing behavior changed. The five signing tests pass locally; the installed APK signature still matches the prior local debug certificate.
- Device transport regression: half-closing a raw ADB exec socket can terminate cat before an atomic rename, leaving an old pairing key. Provision with shell v2 stdin frames and explicit CLOSE_STDIN (id 4), then require exit status id 3 success. Actual phone smoke test confirmed the provisioned random key equals the broker key, Keystore import succeeds and the HTTP API authorizes the request through ADB reverse. This test used no Google credentials. Retry after an initially missing pairing must reread the native key instead of caching an empty string; add app regression coverage.

## 2026-11-01 — Cloud Vision 원본 후보 5건 중 미디어 수신 실패 4건 (v0.21.7+66)
사용자 실기기 스크린샷: 기준 장면 6장, Vision 일치 웹페이지 11건, 소셜 게시물 단서 5건, 원본 후보 5건, 실제 동영상 검사 4건 중 성공 0/장면 불일치 0/자막 의심 0/처리 실패 4. TikTok 10204+PAGE_UNAVAILABLE로 영상 정보 미확보, YouTube는 비공식 스트림 연결 취소 또는 85/95초 제한. 영상 불일치가 검증된 것이 아니라 다운로드/정보 취득 단계에서 모두 실패. 10204만으로 삭제/비공개 단정 금지.
개선: YouTube 썸네일 최대 1MB/9초 확보 후 네이티브 dHash로 참조 프레임 비교, 단 이 결과는 영상 미검증 단서일 뿐 원본 자동 승인 불가. 한 실행에서 YouTube 스트림 확보 실패 시 후속 YouTube 후보의 반복 긴 다운로드를 생략하고 썸네일만 확인. 검증되지 않은 후보도 '후보 게시물 열어보기' 버튼으로 브라우저 열기. TikTok 10204, YouTube 403/타임아웃/취소를 짧고 명확하게 표시하고 raw HTML/JSON 원문 표시 금지. 실제 비디오 프레임과 OCR 모두 통과하지 않은 후보는 자동 제작 불가.
패치 과정 회귀: 최초 Python bytes Unicode assertion SyntaxError 수정; v0.21.4~0.21.6에서 Dart CandidateThumbnail 소스 삽입 후 소스가 잘리거나 OneClickExplorer가 두 번 선언되어 flutter analyze 에서 unterminated_string_literal 및 duplicate_definition 오류 발생. 최종 tool/benchmark_oneclick.dart 완전 복원, 후미 중복 코드 제거, tool/patch_candidate_clean.py로 v0.21.7+66 소스 생성.
검증 완료: GitHub Actions https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41312551306 성공. Flutter analyze/test, Android 고정 서명 APK 컴파일, 서명 검사, artifact 업로드 통과. Artifact shorts-studio-debug-apk id 13086575985. 실기기 스트림 접근 개선과 실제 검색 적중률은 미확인.


## 2026-11-02 — v0.21.10+69 실제 OCR 자막 영역 회피 및 원본 후보 영상 길이 제한

사용자 실기기 화면: Cloud Vision에서 원본 못 찾고, 프레임 안에 한국어 합성 자막이 남아 있으며, 전혀 다른 길이의 소셜 영상이 후보가 됨. 이전의 세로 영상 상단 30%/하단 35% 고정 크롭은 실제 OCR 감지가 아니었기 때문에 화면 중간 자막을 차단하지 못함. 영상 길이도 공식 메타데이터로 사전 판정하지 않았음.

구현: Android 앱에 이미 탑재된 Google ML Kit 한국어 OCR을 검색용 프레임에도 실행, bounding box+padding이 겹치지 않는 최대 검색 영역을 다양한 x/y/폭/높이 조합에서 선택. OCR 오류 시 조용히 원래 이미지로 대체하지 않음. 영상 전 구간에 분산한 6개 장면 추출, 자막과 충돌할 때 추가 후보 시점 탐색(최대 12회). 3장 미만이면 명시적 실패. 각 프레임의 검색용 bounding box를 후보 영상 지문 비교에 그대로 적용, 같은 후보 타임스탬프의 다른 크롭 여러 개는 독립 장면으로 중복 계산하지 않음. OCR이 놓친 효과 자막은 여전히 남을 수 있고 인페인팅은 하지 않음.

재생시간 조건: 기준 영상 길이 ±20% (최소 ±3초), 예컨대 42초 기준 33~51초. YouTube Data API `videos.list(part=contentDetails)` 결과 ISO8601 `duration`을 후보 URL 최대 24건에 대해 배치 조회해 길이 일치 영상부터 자동 확인. API 키 부재/길이 확인 불가/길이 불일치 YouTube 후보는 자동 다운로드하지 않고 판정 보류 또는 제외 사유 표시. TikTok 기존 페이지 메타데이터에는 다운로드 전 범위를 적용하고, 파일 확보 후 실제 길이 재확인. 영상 길이 일치는 동일 원본 증거가 아니며 기존 프레임 대조와 자막 의심 검사를 유지.

코드: `tool/BenchmarkOcrCrop.kt` 신규, `tool/BenchmarkFrameExtractor.kt`, `tool/benchmark_duration.dart`, `tool/benchmark_oneclick.dart`, `tool/benchmark_ui.dart`, `tool/benchmark_tests.dart`. 통합: `tool/patch_ocr_duration.py`; 분산 장면 보강 `tool/patch_ocr_spread.py`. 버전 v0.21.10+69.

검증: GitHub Actions https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41367125984 성공: Flutter analyze, Flutter 전체 테스트, 서명 APK 빌드, 고정 인증서 검증, artifact 업로드 통과. APK artifact `shorts-studio-debug-apk` ID 13107124033. 실기기 OCR 검색 이미지 품질 및 실제 원본 발견률 미검증. Google Cloud Vision 웹 이미지 색인이 원본을 포함하지 않으면 결과가 계속 없을 수 있음. 자동화된 플랫폼 스트림 제한 문제도 그대로 존재할 수 있음.

## 2026-11-02 — v0.21.14+73 원본 검색 후보 오탐 억제 및 사용자 검증 피드백
실기기 검색 화면에서 동일 영상 일부의 원본 Instagram 릴스는 사용자가 수동으로 확인했지만, Cloud Vision이 자동 추천한 대부분의 YouTube/Instagram 게시물은 실제 관련 없는 것으로 나타남. 검색 참조 프레임에는 여러 서로 다른 장면과 텍스트가 포함됨.
Cloud Vision WebDetection pagesWithMatchingImages 자체는 동일 영상 증거가 아님. 이를 fullMatchingImages/partialMatchingImages로 페이지 내부 이미지 일치가 있는 경우와 단순 페이지 일치만 있는 경우로 분류. 직접 일치 증거가 있으면 우선순위에 반영, 약한 페이지는 최대 3개만 수동 참고로 표시하고 자동 스트림 조회/길이검사 슬롯에서 제외. 이미지 직접 일치도 동영상 동일성은 입증하지 못함.
UI '원본 아님'으로 확인한 링크는 BenchState.rejected[videoId]로 영속 저장하고 향후 검색에서 제외. 초기화 지원. '원본 확인·저장'은 BenchState.confirmed[videoId]로 영속 보존, 자동 예측 성공으로 집계하지 않음. 수동 추가된 링크도 재검색 시 보존.
수정: tool/vision_reverse.dart, benchmark_oneclick.dart, benchmark_data.dart, benchmark_ui.dart, benchmark_tests.dart. ZIP 반영 tool/patch_precision_feedback.py. CI에서 데이터 소스 파서 손상 및 UI 변수 shadowing, 후미 중복 BenchApi 코드 확인 후 복구. 최종 패치 tool/patch_precision_tail.py, v0.21.14+73.
최종 검증 https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41455616422 SUCCESS: flutter analyze, flutter test, Android 고정 서명 APK 빌드, 서명 확인, Artifact upload 모두 성공. Artifact shorts-studio-debug-apk ID 13145993904. 실기기 원본 탐색 적중률 실측 전; 검색되지 않던 원본 발견까지 보장하지 않음.
## 2026-11-02 — v0.21.15+74 프레임 시간순서/크롭 정합 기반 원본 검색 정밀도

직전 v0.21.14에서 사용자 제보: 정확히 일치하는 원본 하나를 수동으로 확인했으나 자동 추천한 후보 대다수는 무관했다. 원인 추정: 후보 검증 dHash가 2장만 일치하면 통과하며 서로 다른 검색 크롭 영역도 교차 매칭되고 시간상 역순 장면/반복 장면도 통과 가능했다. 또한 후보 영상의 길이 일치로 YouTube 결과가 강한 이미지 증거를 가진 TikTok보다 먼저 검증되는 우선순위였다.

v0.21.15 변경: Kotlin 후보 프레임 지문에 cropIndex 추가. 후보와 참조의 동일 크롭 위치로만 비교하고, 정지/중복 참조 장면은 독립 증거에서 제외. 3장 이상 서로 다른 장면이 후보에서 500ms 이상 간격을 두고 동일한 시간 순서로 일치해야 자동 확인. 참조·후보 프레임 검색은 OPTION_CLOSEST로 키프레임 중복 위험 완화. 화면 중앙에 오래 남는 기존 편집 자막도 의심 판정에 포함. 원본 후보 순서는 직접 이미지 일치 장면 수/완전 일치 근거를 먼저, 길이 확인은 YouTube 다운로드 적격 조건으로만 반영. 사용자 제공 원본/오답 링크 피드백, 기존 자동 제작 흐름은 보존.

단위 회귀 검사: 크롭 인덱스, 역순 장면, 반복되는 정지 화면, 동일 타임스탬프, 중앙 자막, 증거 정렬. 보수적 검증으로 오탐은 감소할 것으로 기대하지만 검색 엔진 색인 부족 및 TikTok/YouTube 스트림 제한은 개선하지 못한다. CI 통과와 실기기 실제 원본 정확도 향상은 별도로 확인해야 한다. 확인된 원본 예시 NPom9sHH2J0 ↔ https://vt.tiktok.com/ZSp11jbJd/는 사용자 제공 정답으로만 유지.

## 2026-11-03 — v0.21.16+75 OCR 검색 영역·길이·롱폼 차단·연속찾기
사용자 요청: 검색 가능한 원본 이미지 영역 확대, 기준 영상과 비슷한 길이 후보 우선, YouTube 롱폼 제외, 유사도가 실제 일치할 때까지 새로운 장면으로 반복 탐색하는 버튼. OCR 검사 최대 창은 가로 94% × 높이 68%로 확대하되 인식된 텍스트 박스와 겹치는 창은 허용하지 않음. 추출 프레임은 최대 9개, 시간순으로 정렬해 서로 다른 최대 6개의 5장 조합을 검색. 같은 세션에서 이미 검토한 URL은 다시 조회하지 않으며, 3개 독립 장면의 시간순 일치와 OCR 자막 검사 통과 시 연속찾기 종료. 중단 버튼 지원. 여섯 조합을 소진하면 비용·무한루프 방지를 위해 원본 미확인 상태로 종료하며, 동일 원본을 반드시 찾는다고 보장하지 않음.
후보 영상 길이 허용 범위 ±10%(최소 ±2초)로 축소. YouTube 공식 길이가 180초 초과면 다운로드 전에 배제. 다운로드된 영상의 메타데이터는 회전값 반영 후 가로≤세로이고 180초 이하일 때만 자동 확인 통과. YouTube Data API 길이만으로 공식 Shorts 여부가 증명되지는 않으며, 세로형 짧은 롱폼은 제한적으로 남을 수 있음. 원본 게시물 검색 색인 누락/스트림 제한은 미해결. 정상 APK 빌드와 실제 스마트폰 검색 정확도 검증은 별도 확인.
PR #4 Flutter analyze 및 Flutter 전체 테스트 통과: https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41537296049 . 앱 ZIP 통합: main commit 0abadaac870b1a18bf1bac7f658fcbe46bfb9b26. 새 고정 서명 Android APK 빌드를 main에서 트리거.

## 2026-11-03 — v0.21.17+76 자막 오검출/원본 공유 회귀 수정

실기기 스크린샷: 벤치마킹 쇼츠에서 추출한 이미지 카드의 일부 하단에 원작자 추가 자막이 남아 있고, 사용자는 연속찾기 5/6의 의미를 질문함. 5/6은 최대 6개의 서로 다른 이미지 검색 조합 중 5번째, 1/3은 탐색 파이프라인 단계. 실제 원본 확인은 기준 영상을 이루는 서로 다른 3개 장면이 시간 순서대로 일치해야 하며 6장 전부 일치 불필요.

확인된 코드 버그: bench UI가 프레임 미리보기에는 크롭 JPEG을 보여주면서 Google Lens 공유에는 `originalContent` 전체 영상 프레임을 우선 사용하여 자막을 그대로 전송함. 수정: Lens도 정확히 Cloud Vision에 보내는 검색용 크롭과 같은 `framePreviews` 바이트를 공유하며, Kotlin extractor가 전체 원본 프레임 JPEG을 플랫폼 채널에 전송하지 않도록 제거.

OCR 보강: 기존 1글자 자막을 무시하던 검사에서 숫자/문자 1개도 검사하고, 인식 텍스트 주변 패딩 확대. 1차 OCR이 선택한 자막 비접촉 큰 크롭 후보를 최대 8개까지 확대하여 2차 OCR을 실시한 후 잔여 텍스트가 없다고 검사된 크롭만 검색에 사용. 누락 시 다른 크롭/프레임을 사용하고 최소 3장 미만이면 실패를 명시. OCR 모델이 장식적인 글자를 반드시 찾는 것은 아니므로 실기기 적중률을 보장하지 않음.

PR #5: https://github.com/dmc0306/gpt-shorts-studio/pull/5 . PR Flutter analyze/test와 보조 워크플로 테스트 모두 성공. 앱 ZIP은 0.21.17+76으로 패키징됨 (commit 194583e2bb28374928a152027a8fd1bb1ecd1ff7). GitHub 자동 커밋에서 원래 빌드 트리거가 보장되지 않으므로 실제 APK 검증은 아래 main의 별도 커밋 후 실행 결과를 확인해야 함.

## 2026-11-04 — v0.21.18+77 Instagram 후보 상태·중앙 짧은 자막 오탐 수정
사용자 스크린샷: TikTok 후보 영상 중앙에 노란 "feeding" 영문 자막이 존재하고, 앱에서는 Instagram 릴스가 '확인 필요 · 영상 프레임 미검증'으로 나오는 문제. Cloud Vision의 이미지 6장/일치 웹페이지 57/소셜 단서 44/후보 8은 실제 영상 장면 및 자막 검사 성공 수가 아님. 앱의 Instagram 후보는 실제 영상 스트림 자동 다운로드/프레임 비교 미지원이며 이미지 매칭 단서만 제시했음(실영상 검사 2건, 통과 0건). 기존 OverlayCheck는 같은 위치의 3개 서로 다른 시점에 OCR 글자가 반복돼야 걸러지는 편이어서 한 장면의 잠깐 나타나는 영문 자막을 놓칠 수 있었음.

개선: OverlayCheck.verdict는 짧게 나타난 한 장면의 큰 중앙 글자(예: feeding)를 overlay로 판정하고, 소규모 글자 신호도 caption_possible로 구분해 자동 승인 보류. 장면마다 글자 위치가 달라지는 경우도 배제. OCR 결과 없음/불확실한 경우는 자동 통과시키지 않음. Instagram은 unsupported=실제 영상/길이/기존 자막 자동 검사 미지원이라 구체적으로 표시하고, 추적 한도 소진 후보는 unverified로 표시. 별도 '자막 있음 · 제외' 버튼을 추가해 benchState.captioned[videoId] 영구 저장, 다음 연속찾기에서 같은 URL을 제외하고 초기화 가능. 수동 '원본 확인·저장'시 영상 전체 일치, 글자 자막 부재 및 이용 권한 확인을 요구하는 문구 표시. '원본 아님'과 자막 포함은 구별함. 실제 영상 검증을 전혀 하지 않은 URL은 무자막 원본으로 자동 확정하지 않음.
PR #6 성공: https://github.com/dmc0306/gpt-shorts-studio/pull/6 ; 정적 분석 및 Flutter 테스트 https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41729633400 통과, 기존 OCR/연속찾기 회귀 검증도 성공. 앱 ZIP source 패키징 커밋 e36d08fcb3ffeae933191e6d0487f31764e7c6fd. 실기기에서 영어 자막 OCR 검출 성공률은 별도 실험 필요. 최신 Android APK 전체 빌드 검증은 이어서 기록.

## 2026-11-04 — v0.21.19+78 영상 0건·잔여 자막·느린 롱폼 검사 개선
사용자 실기기 화면: 한글 '오래된'과 빨간 큰 '아아악!!'이 크롭 검색 이미지에 남음, Cloud Vision 직접 일치 웹페이지 0건 빈발, 긴 영상 검색 때문에 느림. 기존에는 한국어 OCR TextRecognizer만 사용했고, 소스/벤치마킹 길이 <=180초여서 일반 가로 영상이나 긴 영상이 목록에 섞였음.

수정: 기존 Kotlin Bench OCR에 Latin ML Kit TextRecognizerOptions.DEFAULT_OPTIONS를 함께 사용, 1차/2차 크롭 OCR 둘 다 적용. 앱 bootstrap에서 ML Kit Latin bundled model Gradle 의존성 com.google.mlkit:text-recognition:16.0.1 추가. 프레임마다 OCR 재시도 영역을 8→3개로, 검색 장면 최대 9→6개로 줄여 OCR 실행량 제한. 1글자·장식 자막 인식 개선 기대지만 완전 제거 보장하지 않음. 자동 선정 가능한 영상 최대 60초(0.21.18까지 180초); 캐시된 기존 목록/랜덤 추첨에서도 61–180초 제거. 공식 61~180초 Shorts까지 제외하는 보수적 기준이며 YouTube Data API가 Shorts 플래그를 제공하는 것은 아님. 후보 MP4는 manifest 해상도에서 가로>세로면 실제 다운로드 전에 제외. 720px 근방 세로 스트림 선호, 35MiB 상한, 다운로드 timeout 85→60초. 실제 candidate 검사 5→3건, per-candidate 95→70초. 연속찾기에서 직접 일치 근거 없는 다른 이미지 조합이 연속 2회면 API 비용·시간 방지를 위해 조기 종료하고 다른 쇼츠를 선택하도록 안내. Google Cloud Vision에서 일치 0인 장면의 원본을 반드시 찾을 수 있는 것은 아님.
PR #7 https://github.com/dmc0306/gpt-shorts-studio/pull/7 ; Flutter analyze/test 통과, 이후 ZIP 패키징 main commit d1af862e54d55dc5fcfaa12492c42a2f64e0dbc7. Android 고정 서명과 Kotlin 컴파일 및 APK 아티팩트는 별도 빌드 성공 여부 확인 필요.

## 2026-11-04 — v0.21.20+79 벤치마킹 원본 탐색 UI/UX 전면 정리 및 삭제 대비 기록 백업
사용자 요청: 실수로 앱/데이터를 지운 상황에서 쇼츠 스튜디오 벤치마킹 원본 찾기 UI를 전반적으로 간결화. GitHub repository 자체는 살아 있어 APK 재설치 가능하나, **이전 앱 로컬 데이터가 삭제된 경우 사전 외부 백업 없이 복구된다고 보장하지 않는다**.
개선: 복잡한 기존 상단 버튼(전체 원클릭·무작위 추첨·채널당 추첨·개별 원클릭·연속찾기·원본 링크)을 정리해 [1. 소재 고르기]→[2. 원본 찾기] 2단계로 구성. 각 벤치마킹 쇼츠 카드의 메인 행동을 '자막 없는 원본 찾기'(최대 6 라운드 반복검증) 하나로 통합. 영상 길이/조회수·이름, 단계/중단 제어를 앞에 두고 상세 로그·직접 영상 선택·원본 링크 추가는 확장 메뉴로 이동. 후보는 원본 검증/자막 감지/동영상 미검증 상태별로 간결히, 처음에는 3건만 보이고 나머지는 더 보기. 동영상 후보별 열기/직접확인/선택/제외 동작을 간결한 그룹과 메뉴로 구성. 검색 프레임은 BoxFit.contain으로 정확한 크롭 이미지를 표시하고 터치 시 바로 Lens 공유. API 키·채널 설정과 검증 상세설명은 접히는 설정 메뉴로 이동. 빈 상태, 검색 실패·후보 수, 작은 화면 너비 대응 추가.
데이터 안전: 채널 제외 시 확인 다이얼로그와 SnackBar 실행 취소. BenchState.toJson 검색 기록을 클립보드에 복사해 개인 메모 등에 따로 보관 가능, 클립보드 JSON 복원은 유효성 검증·사용자 확인 후 상태를 교체. **기존 검색 기록이 이미 없으면 백업 기능으로 소급 복원 불가**. API 키와 제작 파일은 백업에 포함되지 않음, 기존 API 키는 별도로 Android 보안저장 유지. 테스트에 검색 기록 roundtrip/결정 상태 보존 추가.
기존 검색 기능(60초 이하·세로영상·한국어/영문 OCR·장면/기존자막 검증·취소·별도 제외), 편집기 연동과 암호화 API 자격정보 저장은 유지.
PR #8 https://github.com/dmc0306/gpt-shorts-studio/pull/8 . 모든 PR CI 통과: https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41832732776 . main 앱 패키징 417345386858db1aafb52ca8fbfe9cd3ea1c6e64 (v0.21.20+79). 이번 커밋으로 Android 고정 서명 APK 빌드를 다시 트리거하며 실제 설치파일/서명 검증은 Actions 최종 성공 확인 필요.

## 2026-11-04 — v0.21.21+80 TikTok 10204 추출 실패 시 일치 영상 증거 보존·파일 대조
사용자가 벤치마킹 쇼츠에서 첫 번째 TikTok 검색 후보가 실제 동일 영상임을 직접 확인했지만 후보 영상 자동 검사 단계에서 '추출기 오류 10204'로 미검증 표시되는 사례 보고. 코드 분석: CandidateFailure.describe에서 10204/PAGE_UNAVAILABLE은 TikTok 후보 영상의 메타데이터/스트림 확보 실패를 의미하며, 영상 내용 불일치의 증거가 아님. UI는 웹 이미지 일치, 실제 스트림 검증 성공, 무자막 여부, 권리 확인을 구분해야 함.
이번 릴리스: BenchState.matchedByUser와 localSceneChecks를 별도 저장하고 복원해, ‘같은 영상 확인’ 버튼이 영상 일치를 사용자가 확인한 상태로 보존하되 OCR/재사용권 승인과 자동 집계를 분리. TikTok 후보에 ‘영상 파일로 비교’ 버튼 추가. 사용자가 합법적으로 확보한 로컬 후보 파일을 Android benchmarkPickFrames에서 선택하여 YouTube 기준 쇼츠에서 추출한 OCR-스크리닝 장면과 비교. 3개 이상의 시각적으로 다른 장면이 시간순으로 근접 해시 일치, 길이 허용 범위 통과 시 로컬 파일의 영상 내용 일치 근거로만 표시. 선택한 파일이 해당 TikTok URL과 동일한 미디어인지는 사용자가 별도 연결 확인, 원본 전체 자막 없음이나 원제작자·이용 허가는 검증되지 않았다고 유지. 자동 검증이 실패해도 사용자가 확인한 첫 후보 링크는 검색 갱신 후 남음. 부적합 후보로 제외하면 사용자 확인/로컬 장면 증거 동시 정리.
테스트: 3장 이상 일치, 역시간 장면, 정적 반복 장면, 길이 불일치, 사용자 확인 URL/파일 증거 영속성과 검증 상태 구분. PR #9 https://github.com/dmc0306/gpt-shorts-studio/pull/9. 모든 Flutter PR CI 테스트 통과 https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41843920503 . v0.21.21+80 source ZIP 패키징 main commit 93d7d06e40fcbb724de6741b545f006a3075c263. Android 고정 서명 빌드는 이 기록 커밋에서 트리거해 후속 확인.

## 2026-11-05 — v0.21.22+81 YouTube 전체 공개 / 예약 공개 / 반복 공개 업로드
사용자 요청: Short Studio가 저장된 쇼츠를 비공개뿐 아니라 공개로 자동 업로드하고, 주기(매일/2일/3일/매주), 업로드 시각을 설정해 공개하게 만들기. 기존 OAuth Chrome 채널 확인 및 암호화 토큰, resumable uploader와 Editor/AutoBatch의 MP4 저장 후 자동 업로드 연결을 사용.
구현:
- lib/youtube_publish_plan.dart: 기본 private, 즉시 public, 예약 private+status.publishAt(UTC) 모드; 24/48/72/168h, 시/분, 기존 마지막 예약 이후의 다음 게시 시간, 최소 1시간 여유.
- youtube_channel.dart Preferences: publishMode, cadenceHours, publishHour, publishMinute, lastScheduledAtUtc, publicConsentChannel. 업로드 대상 채널 확인/아동용 설정과 **같은 채널의 명시적 공개 동의**가 있어야 public/scheduled. 기존 설정은 private 기본값 보존. 계정·채널이 바뀌면 공개 동의가 자동으로 유효하지 않음.
- youtube.dart: 새 MP4 저장 후 자동 업로드가 켜져 있으면 설정한 모드로 전송, 예약이면 다음 시간대를 먼저 예약하고 저장; 전송 세션을 이어 올릴 때 과거 비공개 세션의 게시 상태를 임의로 바꾸지 않음. YouTubeUpload 기존 세션/영상 ID 중복 방지 유지.
- youtube_upload.dart: videos.insert의 status.privacyStatus=public 즉시 공개 또는 private+publishAt 미래 예약, 응답 videoId/요청·실제 상태 저장. 업로드가 너무 늦어 예약 시각이 가까워지면 오류 처리.
- youtube_settings.dart: 공개 범위, 반복 주기, 로컬 게시 시각, 다음 예정일, 저작권/재게시 허가 동의 다이얼로그, 기존 자동 MP4 업로드 설정 통합.
- youtube_batch_publish_screen.dart: 완성 MP4 최대 20개 선택하여 지금 순차 전송하고 각 영상 YouTube 예약 공개. 미리 예약 시간 표시, 채널·권리 최종 승인, 진행·중단·중복방지 및 실패 시 남은 영상 보존. YouTubePanel/앱 메인 화면에서 진입 가능.
중요한 한계: 휴대폰 앱이 실행 중일 때만 새로운 영상 파일을 업로드함. YouTube가 업로드된 영상을 미래의 시각에 자동 공개하는 것은 앱이 꺼져도 동작. 휴대폰이 꺼진 상태에서 새 영상을 생성·업로드하는 무중단 백그라운드 서버 스케줄러는 포함되지 않음. 이미 비공개로 게시한 영상은 자동 공개 상태로 변경되지 않음(YouTube Studio에서 변경). TikTok 등 재사용 영상은 저작권/이용 권한 확인이 필요.
PR #10 https://github.com/dmc0306/gpt-shorts-studio/pull/10 , latest Flutter analyze/test PASS https://github.com/dmc0306/gpt-shorts-studio/actions/runs/41935991041 . Android signed build는 패키징 커밋 cf3474c6e3e105b2cca110757052e241c6e5095d 이후 본 문서 커밋으로 트리거.

## 2026-11-11 — v0.21.23+82 Gemini 한국형 쇼츠 제목 프롬프트 개선
요청: 이미 사용 중인 Gemini 영상→제목 명령문에 예시 스타일(액체 고양이, 나도 좀 먹고 살자, 복복복 가나디, 프로레슬링계 아이돌 등)의 자연스럽고 호기심/반전/공감형 제목을 적용하되, 화면 상단/하단 각각 공백 포함 5~11자라는 기존 제약을 유지.
실제 수정 위치는 ZIP 내부 lib/ai_rules.dart 의 const titleRules로, 영상 파일을 전달하는 GeminiCaptions.generate 및 저장된 장면만 이용하는 GeminiCaptions.createTitles/regenerate(titleOnly:true)가 모두 이 상수를 사용. curiosity/twist/humor 각 style의 top/bottom JSON 필드와 에디터 화면, 기존 자막 생성/배치 규칙 변경 없음.
새 프롬프트는 실제 관찰 행동·리액션 중심으로 자연스러운 카피, 원문 제목 직접 복사 금지, 입증되지 않은 상위 1%·세계 최초 등의 통계/랭킹과 억지 반전/허위 관계 금지, ㅋㅋ·ㄷㄷ은 과하지 않게 사용, 2줄 각 글자수 별도 확인 및 낱말 중간 분리 금지를 명시. 앱의 기존 grapheme-length validator (headline.dart / normalizeHeadline / decodeTitles) 및 최대 2회 재생성 기능을 그대로 보존. 새 test/gemini_title_style_test.dart에서 제목 예시/프롬프트/3종 후보 각각 길이 위반 거절 검사.
PR #11 https://github.com/dmc0306/gpt-shorts-studio/pull/11 ; GitHub Flutter analyze + 전체 테스트 통과 https://github.com/dmc0306/gpt-shorts-studio/actions/runs/43038692598 ; 최신 패키징 main commit d1ae03a350795e056373bc8fe4509e9b5b9eca77 (0.21.23+82). 테스트는 명령문의 포함과 글자수 규칙을 검증하며, 실기기 Gemini의 실제 생성 문체나 조회수 성과까지 보장하지 않음. 이 커밋에서 Android 고정 서명 APK 빌드를 다시 트리거.
