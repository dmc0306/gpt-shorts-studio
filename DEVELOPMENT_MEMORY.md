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
