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
