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
