# Short Studio — 휴대폰에서 매일 쇼츠 1개 자동 검색·제작·업로드

**GitHub Actions, PC, 별도 서버를 예약 실행에 사용하지 않습니다.** 앱에서 한 번 설정하면 Android WorkManager가 매일 선택한 한국 시각을 기준으로 실행을 예약합니다.

## 자동화 흐름

1. WorkManager가 인터넷 연결과 배터리 상태를 확인하고 Android 포그라운드 작업을 시작합니다.
2. 앱 화면 없이 **독립 FlutterEngine**을 시작합니다. 화면의 LibraryScreen/AutoBatchScreen을 자동으로 띄우지 않습니다.
3. 사용자가 **직접 소유하거나 재게시 허가를 받은 TikTok 제작자 계정**에서 신규 세로 영상 후보를 찾습니다.
4. 중복 URL/영상 ID를 제외하고 5~60초 영상만 내려받습니다.
5. Gemini가 실제 영상에서 흥미로운 5~30초 구간을 선택하며 **기존 자막/편집본/AI 의심/판단 불확실** 후보를 제외합니다. 선택한 화면 크롭 영역에 Android ML Kit OCR을 다시 적용합니다.
6. 기존 Gemini 한국형 쇼츠 제목 규칙을 사용해 상단·하단을 **각각 공백 포함 5~11자**로 제한합니다.
7. 독립 Media3 영상 변환기가 상·하단 제목과 시간별 자막을 넣어 9:16 MP4를 생성하고 갤러리 및 프로젝트에 저장합니다.
8. 기존 **Chrome OAuth YouTube 계정**의 암호화된 갱신 토큰을 장치 내부에서 갱신해 확인된 채널로 MP4 1개를 업로드합니다.
9. 성공/실패를 예약 설정 화면과 Android 알림으로 남깁니다. 영상 원본 ID를 로컬에 선점 기록하여 응답이 불확실한 경우에도 같은 영상으로 중복 업로드하지 않습니다.

**하루 업로드 목표는 1개, 상한도 1개입니다.** 접근 가능한 후보가 없거나 자막/저작권/검증/API 조건을 통과하지 못하면 그날은 **0개**일 수 있으며 무조건 업로드하진 않습니다.

## 휴대폰에서 처음 설정하기

1. Short Studio의 AI 설정에서 **Gemini API 키**와 **Tavily 검색 API 키**를 연결합니다.
2. **YouTube 채널 설정 → Chrome 계정 연결**로 업로드 권한과 **오프라인 갱신 권한**을 받아 채널을 확인합니다. 다른 방식의 YouTube 연결은 현재 앱이 닫혔을 때 자동 갱신에 사용하지 않습니다.
3. 원하는 공개 범위와 시각을 선택하고 **완성 MP4 자동 업로드**를 활성화합니다. 공개 동의가 없는 영상은 업로드하지 않습니다.
4. **YouTube 채널 설정 → 휴대폰 백그라운드 자동 제작 예약 → 기기 내 예약 시간 설정**을 엽니다.
5. 본인 소유 또는 콘텐츠 재사용 허가를 받은 TikTok 계정명, 권리 동의, **매일 시작 시간**을 설정하고 예약을 켭니다.
6. 알림 권한과 백그라운드 실행 권한을 허용하고, 가능하면 기기 배터리 설정에서 Short Studio를 절전 제한 대상에서 제외합니다.

설정을 켜면 이후에는 Android가 가능한 상황에서 **그날 정해진 시각 이후** 새 영상 검색부터 업로드까지 실행합니다. YouTube *예약 공개 시간*은 시작 시간과 별개이며 YouTube가 업로드된 영상 공개를 처리합니다.

## 중요: 휴대폰 운영체제의 제한

- Android WorkManager는 **요청한 시각의 정확한 실행을 보장하지 않습니다**. 배터리 최적화, Doze, 백그라운드 네트워크 제한으로 시작이 지연될 수 있습니다.
- **앱을 화면에서 닫거나 최근 앱 목록에서 지워도** 기기 정책이 허용하고 앱을 강제 중지하지 않았다면 WorkManager의 예약 작업은 남아 있습니다. 이 버전은 화면 없이 새로운 Flutter 엔진을 실행할 수 있도록 구성돼 있습니다.
- **설정 → 앱 → 강제 중지(Force stop)**를 누르거나 제조사의 강한 배터리 제한이 적용되면 예약 실행이 중단될 수 있으며, 앱을 다시 실행해야 할 수 있습니다.
- Android 15 이상의 데이터 동기화·미디어 처리 Foreground Service에는 총 실행 시간 제한이 있고, 장시간 작업은 일정 시간 뒤 중단될 수 있습니다.
- 기기 전원이 꺼져 있거나 네트워크가 끊겼거나 Google OAuth 갱신이 실패하면 업로드되지 않습니다.
- UI 없이 Android 엔진을 실행하도록 코드는 구성했지만, **실제 단말에서 재부팅·잠금·Doze·YouTube 업로드가 성공하는지 반드시 검증해야 합니다.** CI에서 코드를 컴파일한 것만으로 완전 무인 동작을 보장하지는 않습니다.

## 상태와 중복 관리

- 마지막 예약 날짜 및 진행 상태: **기기 내 예약 시간 설정** 화면에서 확인합니다.
- 하루 한 번만 실행하며 WorkManager가 24시간마다 작업을 스케줄합니다. Android 지연으로 실행 시간이 하루씩 조금씩 달라질 수 있습니다.
- 한 번 업로드 대상으로 선점한 원본은 로컬 이력에 저장되므로 응답이 끊겨도 같은 영상을 자동 중복 게시하지 않습니다. 복구를 위해 임의로 이력을 지우지 마세요.
- 실패한 영상 원본, 판단이 불확실한 원본, 다른 사용자의 허가받지 않은 영상은 자동으로 게시하지 않습니다.
- 기존 YouTube 영상의 공개 상태를 일괄 수정하거나 이전 영상 전체를 비공개 전환하지 않습니다.

## 기술 구조

- 예약: `native/android/AndroidDailyScheduler.kt` (WorkManager)
- 별도 실행 엔진: `native/android/AndroidHeadlessDailyRunner.kt`, `lib/main.dart`의 `@pragma('vm:entry-point') dailyHeadlessMain`
- Android 네이티브 서비스 분리: `native/android/HeadlessDailyMedia.kt` (Media3, ML Kit OCR, Android Keystore, Chrome OAuth 갱신, 저장소)
- 영상 제작: `lib/daily_headless_runner.dart` (Tavily 검색, TikTok 다운로드, Gemini 장면 선택·제목/자막, MP4, YouTube 전송)
- 전체 파이프라인 실행은 **기기에서만** 이뤄지며 GitHub Actions는 개발 중 테스트와 APK 빌드에만 사용합니다.

## 참고 자료

- WorkManager periodic work: https://developer.android.com/reference/androidx/work/PeriodicWorkRequest
- Long-running WorkManager workers: https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running
- Foreground service timeout: https://developer.android.com/develop/background-work/services/fgs/timeout
