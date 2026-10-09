## 0.3.0 — 참고 영상 포맷 적용

- 참고 0326.mp4 기준: 1080×1920, 검정 배경, 중앙 1080×1080 영상 (Y=420~1500).
- 첨부 Gmarket Sans Bold 적용. 제목 108px 기준, 상단 두 줄 첫 줄 흰색/둘째 줄 노랑. Enter로 줄을 나눕니다. 긴 줄은 영역에 맞게 축소합니다.
- 상황 자막: 44px, Y=1200 기준, 검정 배경·흰색 글씨. 참고 영상의 장면별 자막 위치/시간 변경은 이번 고정 템플릿에 포함하지 않습니다.
- 미리보기와 Android 출력에 동일한 정사각 영상 배치를 적용합니다. 기존 프로젝트의 채우기 설정은 보존하며 신규 프로젝트는 중앙 채우기를 기본값으로 사용합니다.
- 사용자 요청에 따라 추가 실행 검증은 생략했습니다. 폰트는 사용자가 제공한 파일입니다.

## 빌드 수정

재생 원본 주소 사용 변경에 맞춰 실패 진단 테스트의 확인 필드를 playAddr로 수정했습니다.

## 0.2.4 — 재생 원본 주소 사용

- 공개 페이지가 제공하는 playAddr를 사용합니다. 워터마크 포함 가능성이 있는 downloadAddr로 대체하지 않습니다.
- 비공개·명시적 다운로드 비활성화 검사와 HTTPS 도메인 제한을 유지합니다. 원본 주소가 없으면 파일 연결을 안내합니다.
- 주소의 실제 워터마크 유무는 보장하지 않습니다. 사용자 요청에 따라 이번 변경의 분석·테스트·실기기 검증은 생략했습니다.

## 0.2.3 — TikTok 모바일 공유 페이지 구조 지원

- 사용자가 제공한 실패 링크 응답을 확인해 원인을 재현했습니다. HTTP 200 JSON의 영상 정보는 `webapp.reflow.video.detail`에 있지만 기존 파서는 `webapp.video-detail`만 조회했습니다.
- 두 구조에서 요청한 영상 ID와 일치하는 항목만 읽습니다. 기존 다운로드 허용·도메인 검사도 유지합니다.
- 실제 응답의 구조를 익명화한 테스트 fixture로 회귀 테스트를 추가했습니다.
- 제공된 링크의 downloadAddr에서 HTTP 200 video/mp4, 2,393,637 bytes 다운로드를 확인했습니다. ffprobe: H.264/AAC, 576×1024, 11.655초. 이는 작업 환경의 다운로드 검증이며 Android 실기기 실행은 별도 확인이 필요합니다.

## 0.2.2 — 보안 확인 오판 수정

- HTML 스크립트에 captcha라는 단어가 있는 것만으로 보안 확인 페이지로 판정하지 않습니다.
- 영상 메타데이터 없음 / 다운로드 주소 없음 / 비공개 / 다운로드 비활성화를 구분합니다.
- 오류 정보에 메타데이터 JSON 해석·영상 ID 일치·다운로드 주소 존재 여부와 숫자 상태 코드를 기록합니다. 쿠키·서명 URL·HTML 원문은 기록하지 않습니다.
- 실제 실패 링크가 제공되지 않아 해당 영상 다운로드 성공은 아직 검증하지 못했습니다.

## 0.2.1 다운로드 진단 업데이트

- 확인된 코드 문제: 응답에 Set-Cookie가 없으면 기존 쿠키를 지우던 동작 수정. 도메인·경로·만료 조건을 지키며 쿠키 유지.
- 링크·페이지 확인에 45초 제한, 파일 다운로드에 3분 제한 적용. 대기시간 초과 시 요청 종료.
- 실패 메시지에 PAGE/MEDIA/FILE 단계, HTTP 상태·응답 타입·본문 크기 추가.
- 오류 정보 복사 버튼 추가. 쿠키·서명된 다운로드 URL·인증 값은 진단에 포함하지 않음.
- 단위 테스트는 쿠키 유지·도메인 경계·경로·삭제 처리 확인.
- 사용자가 보고한 링크의 실패 원인은 아직 재현하지 못함. 실패 링크·오류 코드로 실전 검증 필요.

## 0.2 업데이트 — TikTok 링크에서 원본 다운로드

- 링크 추가 또는 Android 공유로 등록하면 공개 영상 페이지의 `downloadAddr`에서 MP4 다운로드를 시도합니다.
- 별도 AI API·서버 없이 휴대폰에서 처리합니다. 워터마크는 제거하지 않습니다.
- 다운로드 진행률·취소·재시도·실패 사유·수동 파일 연결을 지원합니다.
- TikTok의 공식 다운로드 API가 아닙니다. 페이지 변경·로그인·지역·요청 제한으로 실패할 수 있습니다. 모든 링크 다운로드를 보장하지 않습니다.
- 재생 전용 주소를 다운로드 주소로 대신 사용하거나 비공개·인증·요청 제한을 우회하지 않습니다.
- 성공한 파일은 앱 전용 원본 저장소에 보관하고 카드 클릭으로 편집합니다. 편집 결과의 갤러리 저장은 기존과 같습니다.
- `shorts-studio-source.zip`에 소스가 들어 있습니다. 루트 워크플로는 압축을 `app/`에 풀어 빌드합니다.
- GitHub Actions → Android debug APK → Run workflow로 빌드를 다시 실행할 수 있습니다. 성공한 실행의 Artifacts에서 APK를 받습니다.
- 0.2 라이브 TikTok 다운로드는 실제 기기·링크로 확인해야 합니다. 빌드·파서 테스트 통과와 실제 다운로드 성공은 별개입니다.

아래는 초기 MVP의 기능·설계 기록입니다. 자동 다운로드 미지원이라는 초기 설명은 위 0.2 범위로 대체합니다.

# Shorts Studio — Android MVP 0.2

15초 내외 영상을 수집함에서 선택하고, 템플릿·제목·상황 자막을 적용해 MP4로 저장하는 Flutter 앱의 첫 구현입니다.

**상태: 소스 구현 / APK 빌드·실기기 검증 전.** 이 파일 묶음은 설치 APK가 아닙니다. 작성 환경에 Flutter·Android SDK 및 브라우저 실행 파일이 없고 SDK 다운로드가 차단되어, Flutter 분석·테스트·컴파일과 네이티브 출력 품질을 확인하지 못했습니다.

## 이번 버전에 들어간 것

| 기능 | 구현 범위 |
|---|---|
| 공유로 수집 | Android 공유 메뉴의 텍스트(TikTok URL)·영상 파일 받기 |
| TikTok 정보 | 공식 oEmbed로 제목·제작자 조회 시도. 실패하면 링크를 유지 |
| 자동 수집 | 사용자가 선택한 기기 폴더의 새 영상, 앱이 실행 중일 때 15초 간격 검사 및 재진입 시 검사 |
| 영상 가져오기 | 시스템 파일 선택기, 앱 전용 공간에 복사, 썸네일 생성 |
| 자동 편집 | 영상 클릭 시 기본 템플릿 적용. 제목은 파일명으로 초기화 |
| 편집 | 미니멀/볼드/블루 3종, 제목·상황 자막, 구간 자르기, 중앙 채우기 또는 원본 맞춤, 음소거 |
| 저장 | Media3로 1080×1920 H.264/AAC MP4 합성, 갤러리 Movies/ShortsStudio에 저장 |
| 프로젝트 | 앱 전용 JSON 원자적 교체 저장. 공유 수집함은 확인 응답 후 제거 |
| 출력 UX | 실제 렌더링 진행률(제공되지 않으면 미정 진행), 취소, 오류, 저장 완료 알림 |

**아직 구현하지 않은 핵심 범위:** TikTok 전체 영상 자동 검색·원본 자동 다운로드. 폴더 수집은 이미 기기에 확보한 파일을 대상으로 하며 TikTok 수집 서비스와 다릅니다. TikTok API 계정 인증도 연결하지 않았습니다. 일반 공개 영상 자동 수집을 완료했다고 해석하면 안 됩니다.

외부 AI API, 온디바이스 AI 분석, 대사 인식, 자동 상황 이해, YouTube 업로드, iOS 영상 엔진, 앱 종료 중 백그라운드 수집은 포함하지 않았습니다.

## 실행

필요 환경: Flutter 3.44 이상 stable (Dart 3.12 이상), Android Studio/SDK, JDK 17, Python 3, Android 10(API 29) 이상 기기. 패키지 다운로드를 위한 인터넷이 필요합니다.

압축을 풀고 `shorts_studio` 디렉터리에서:

```bash
python tool/bootstrap.py
flutter analyze
flutter test
flutter run
```

Windows에서 `python` 명령이 없으면 `py tool/bootstrap.py`를 사용합니다. `tool/bootstrap.py`는 Flutter SDK 버전에 맞는 Android 뼈대를 생성하고 네이티브 코드·매니페스트·의존성을 설치합니다. Gradle/Kotlin 플러그인 설정은 설치된 Flutter의 기본값을 유지합니다.

APK 만들기:

```bash
flutter build apk --debug
```

결과: `build/app/outputs/flutter-apk/app-debug.apk`. 개발용 디버그 빌드이며 앱스토어 출시 서명은 포함하지 않습니다.

GitHub 저장소의 루트에 이 폴더 **내용**을 올리면 `.github/workflows/android.yml`로 테스트와 APK 빌드를 실행할 수 있습니다. 코드는 저장소에 업로드하지 않았으며 워크플로도 실행되지 않았습니다. Actions 완료 후 `shorts-studio-debug-apk` 아티팩트에서 APK를 받습니다.

## 사용 순서

1. `샘플 영상으로 시작` 또는 `영상 가져오기`.
2. 자동 수집을 쓰려면 우측 상단 설정 → 수집 폴더 선택. Android 정책상 루트 Download 등을 선택할 수 없으면 별도 하위 폴더를 만듭니다.
3. TikTok에서 공유 → Shorts Studio를 선택하면 링크가 수집함에 추가됩니다. 앱 목록에서 보이지 않으면 링크 복사 → 앱의 `링크 추가`를 사용합니다.
4. 링크 카드에 원본이 없으면 파일을 한 번 연결합니다. 링크만으로 영상 파일을 내려받지는 않습니다.
5. 영상 카드 탭 → 기본 템플릿 적용 → 제목·자막·구간 확인 → `MP4로 저장`.
6. 갤러리의 Movies/ShortsStudio에서 결과 확인. 저장함 카드로 편집을 다시 열 수 있습니다.

저장 중에는 앱을 켜두세요. OS가 앱을 종료하면 작업을 다시 시작해야 합니다. 강제 종료 중인 작업의 이어서 렌더링은 미지원입니다.

## 디자인

사용자가 제공한 See for Yourself 디자인 토큰을 적용했습니다.

- 흰색 #FFFFFF, 검정 #101010/#000000, 파랑 #0099FF.
- 회색 #C6C6C6, 절제된 구분선, 8px 중심 간격.
- 큰 얇은 헤드라인, 둥근 카드, 알약형 버튼.
- 수집함 → 편집 → 갤러리 저장, 업로드 탭 없음.
- Inter Display/PP Neue Montreal 폰트 바이너리·라이선스가 제공되지 않아 시스템 sans-serif를 사용합니다. 원본 폰트를 무단 번들하지 않았습니다.

`design/preview.html`은 두 화면을 비교하는 **별도 HTML 디자인 미리보기**입니다. 브라우저에서 열면 템플릿·제목·자막·영상 재생·기기 파일 미리보기를 조작할 수 있습니다. Flutter를 실행한 캡처가 아니며 이 HTML은 실제 MP4 저장을 하지 않습니다. 버튼은 그 한계를 안내합니다. 샘플 영상은 코드로 직접 만든 15초 모션 그래픽이고 TikTok 영상이 아닙니다.

## 코드 지도

- `lib/main.dart`: 수집함, 저장함, 공유 수집함 병합, 폴더 검사, 상태 관리
- `lib/editor.dart`: 플레이어, 템플릿, 공통 자막 오버레이, 편집·저장 UX
- `lib/theme.dart`: 디자인 토큰
- `lib/model.dart`: 프로젝트 데이터와 TikTok URL 검증
- `lib/bridge.dart`: Flutter ↔ Android 통신
- `native/android/MainActivity.kt`: SAF 파일·폴더, 메타데이터, 공유, Media3, MediaStore
- `tool/bootstrap.py`: Flutter 플랫폼 생성·네이티브 설치
- `.github/workflows/android.yml`: 분석·테스트·디버그 APK 빌드

미리보기 자막 레이어를 PNG로 캡처하여 동일한 레이어를 Media3에 전달합니다. OS별 텍스트 재조판 차이를 줄이기 위한 구조이며, 실제 정합도는 기기 테스트가 필요합니다. 출력은 원본을 유지하는 fit이 기본값입니다. crop을 켜면 중앙 기준으로 화면을 채우므로 가장자리가 잘립니다. 자막은 전체 편집 구간 동안 표시됩니다. 별도의 자막 타이밍·발화 트랙은 아직 없습니다.

## 한계와 실기기 확인 항목

- Android만 연결되어 있습니다. Flutter UI를 공유하더라도 iOS는 별도 Swift 구현이 필요합니다.
- 0.2초~120초, 최대 512MB 입력을 처리합니다. 주요 목표는 5~30초 MP4입니다.
- 폴더는 한 단계만 검사합니다. SAF 권한이 취소되면 다시 선택해야 합니다.
- 기본 15초 간격은 스케줄 목표이며 폴더 IO 시간·OS 중단에 따라 늦어집니다.
- 새 파일의 이름/URI/크기/수정시각으로 중복을 줄입니다. 같은 영상의 별도 복사본까지 해시로 제거하지 않습니다.
- 무음 원본에 AAC 트랙을 새로 만들지는 않습니다.
- HDR·회전 메타데이터·저장 공간 부족·저사양 인코더는 아직 검증되지 않았습니다.
- 앱 삭제 시 원본 사본·프로젝트 정보는 삭제됩니다. 갤러리에 내보낸 영상은 별개입니다.
- 원본 영상·음악의 이용 범위는 사용자가 확인합니다. 현재 버전은 권리 증빙 DB와 발행 기능이 없습니다.

### 빌드 후 필수 확인

1. 세로 H.264 15초 영상: 제목·자막이 미리보기와 저장본에 동일하게 나타나는지.
2. 가로 영상: fit은 전체 보존, crop은 중앙 잘림이 일치하는지.
3. 구간 2~8초: 저장본 길이가 약 6초인지, 음소거를 켜면 오디오가 없는지.
4. 한글·긴 제목·빈 제목·세 템플릿을 확인.
5. 앱 종료 후 프로젝트 복원, 콜드/웜 공유 인텐트, 동일 URL 중복 처리.
6. 폴더 파일 추가 → 수집 → 다시 스캔해도 중복 생성되지 않는지.
7. 저장 취소·공간 부족·인코더 오류 때 성공으로 표시하지 않는지.
8. 저사양 실기기에서 1080p 출력·온도·메모리·발열 확인.

## 검증 기록

작성 환경에서 수행: Dart 파일 구분자 균형 점검, Python 문법 점검, Android XML 구문 점검, 샘플 파일 ffprobe 확인(H.264, 360×640, 24fps, 15초), HTML JavaScript 구문 확인.

수행하지 못함: `flutter analyze`, `flutter test`, Gradle/Kotlin 빌드, APK 설치, Flutter UI 렌더링, Android MP4 내보내기, 브라우저 실제 렌더링. 정적 구문 확인만으로 빌드나 실행 성공을 보장하지 않습니다.

## 확인한 공식 문서

- TikTok Display API: https://developers.tiktok.com/docs/en/display-api-overview
- TikTok oEmbed: https://developers.tiktok.com/docs/en/embed-videos
- Media3 Transformer: https://developer.android.com/media/media3/transformer/getting-started
- Media3 BitmapOverlay: https://developer.android.com/reference/androidx/media3/effect/BitmapOverlay
- Media3 Presentation: https://developer.android.com/reference/androidx/media3/effect/Presentation
- Flutter video_player: https://pub.dev/packages/video_player/versions/2.14.1
- Android video player changelog: https://pub.dev/packages/video_player_android/changelog
