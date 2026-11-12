# Short Studio — 매일 1개 영상 자동 검색·제작·YouTube 업로드

이 문서는 **새 클라우드 자동화** 안내입니다. 기존 앱의 '예약 공개'와 다릅니다.

## 지원하는 작업

매일 선택한 한국 시각에 GitHub Actions가 시작되어 다음 작업을 순서대로 수행합니다.

1. Tavily API로 **재사용이 허가된 TikTok 제작자 계정**의 새 영상 후보 검색
2. 이전에 사용한 영상 제외, 길이 5~60초·세로 영상만 수집
3. 한글/영문 OCR로 원본에 이미 합성된 글자·자막 검사
4. Gemini가 영상 장면을 분석하고 기존 자막 없음으로 판단한 경우에만 제목·상황 자막 생성
5. 상단/하단 각 **공백 포함 5~11자**를 별도로 검사
6. FFmpeg로 세로 9:16 MP4 제작
7. 설정된 내 YouTube 채널에 **비공개 / 즉시 공개 / 예약 공개**로 하루 최대 한 개 업로드
8. 중복 방지 기록을 별도 `automation-state` 브랜치에 저장

원본이 검색되지 않거나 TikTok 접근 오류(10204/403 등), 자막 검출, Gemini 검사 실패가 발생하면 무리하게 업로드하지 않습니다. **매일 반드시 1개를 확보한다고 보장할 수는 없습니다.**

## 처음 활성화하는 방법 (GitHub)

### 1. 안전한 계정 연결 준비

저장소의 **Settings → Secrets and variables → Actions → New repository secret**에서 다음 다섯 비밀값을 각각 등록합니다.

- `GEMINI_API_KEY`: 현재 사용하는 Gemini API 키
- `TAVILY_API_KEY`: Tavily 검색 API 키
- `YOUTUBE_CLIENT_ID`: Google Cloud의 OAuth **데스크톱 앱** 클라이언트 ID
- `YOUTUBE_CLIENT_SECRET`: 같은 OAuth 클라이언트의 secret
- `YOUTUBE_REFRESH_TOKEN`: 업로드 대상 YouTube 채널에 로그인한 OAuth 갱신 토큰

기존 Android 앱의 암호화된 YouTube 로그인 정보와 Gemini/Tavily 키는 GitHub로 **자동 복사되지 않습니다.** 비밀번호·토큰·API 키를 채팅이나 저장소 소스 파일에 넣지 마세요.

갱신 토큰은 개인 PC에서 `python -m pip install google-auth-oauthlib` 후 `python automation/get_youtube_refresh_token.py` 를 실행하여 Google 로그인·권한 동의로 생성할 수 있습니다. `youtube.upload`, `youtube.readonly` 두 권한에 동의하고, 자신이 관리하는 YouTube 채널로 로그인해야 합니다. 새로 승인하는 별도 OAuth 클라이언트입니다.

Google Cloud Console OAuth 동의 화면이 Testing 상태이면 refresh token이 조기에 만료될 수 있어, 지속 자동화를 사용하려면 승인 상태와 OAuth 설정을 확인해야 합니다.

### 2. 원하는 날짜·시간·계정 설정

GitHub 저장소의 **Actions → Configure daily Shorts automation → Run workflow**를 열어 입력합니다.

| 항목 | 예시 | 의미 |
| --- | --- | --- |
| enabled | true | 자동화 켜기 |
| run_time | 09:00 | 매일 한국시간 영상 **검색·제작·업로드 시작** 시각 |
| publish_mode | scheduled | private / public / scheduled 중 하나 |
| publish_time | 18:00 | scheduled 모드의 실제 **공개** 시각 |
| topic | 강아지의 재미있는 반응 | 검색 주제 |
| licensed_creators | my_account,partner_account | 직접 소유하거나 서면 재사용 허가를 받은 TikTok 계정 |
| youtube_channel_id | UC로 시작하는 채널 ID | 실제 업로드 대상 채널 |
| rights_attested | true | 위 계정에서 영상을 수정·재게시할 권리 확인 |

예를 들어 오전 9시에 1개를 제작해서 당일 오후 6시 YouTube에 공개하도록 설정할 수 있습니다. 업로드/처리 시간이 걸리고 예약 공개가 너무 가까우면, 해당 영상은 다음 날 같은 시각으로 예약됩니다.

**다른 사람의 TikTok 영상을 발견했다는 사실만으로 재업로드 권한이 생기지 않습니다.** 소유하거나 허가받은 계정만 등록하세요. 앱의 화면 일치 검증이나 AI가 권리를 대신 확인해주지는 않습니다.

설정 변경 뒤 GitHub Actions가 저장소의 `automation/daily_config.json`과 **GitHub Actions UTC cron**을 수정합니다. 예약 시각은 Asia/Seoul 기준으로 입력하면 됩니다.

### 3. 안전하게 시험하기

- **Actions → Daily discover, create and publish Shorts → Run workflow**의 `dry_run=true`는 예약 및 설정만 확인하고 **영상 업로드를 하지 않습니다**.
- 실제 전송 시험은 게시 방식을 **private**로 바꾸고 `dry_run=false`로 실행해 주세요.
- 그날 이미 실행을 시도했다면 중복 방지를 위해 추가 전송하지 않습니다. 실제 접수 여부는 YouTube Studio에서도 확인해 주세요.
- **작업 로그 / Artifacts → daily-shorts-report**에서 날짜, 동작 여부, 업로드 결과를 확인할 수 있습니다.
- 자동화를 끄려면 Configure workflow에서 `enabled=false`로 저장하세요. 이미 YouTube에 등록된 예약 영상은 취소되지 않습니다.

## 현재 자동화와 기존 앱 기능의 차이

| 항목 | 앱의 기존 예약 공개 | 새 클라우드 자동 제작 |
| --- | --- | --- |
| 영상 검색 | 없음 | Tavily로 새 후보 검색 |
| 원본·자막 검사 | 기존 제작 과정 | 클라우드 FFmpeg/OCR/Gemini 검사 |
| 제목·MP4 생성 | 앱에서 수동/자동 제작 실행 | 예약 작업에서 자동 처리 |
| 새 파일 업로드 | 앱이 실행되어 있을 때 | GitHub 실행기에서 전송 |
| 정해진 시각 공개 | YouTube publishAt | YouTube publishAt |
| 앱 종료 후 새 영상 제작 | 불가 | GitHub 연결 및 활성화 후 가능 |

기존 휴대폰의 **혼합 영상 5개 자동 제작** 코드와 별개인 클라우드용 구현이므로 자막·편집 스타일이 완전히 동일하지는 않습니다. 클라우드 버전은 GitHub 실행기에서 FFmpeg와 한글/영문 OCR을 사용합니다.

## 한계 및 주의

- **현재 기본값은 비활성화**입니다. 위 다섯 Secrets와 채널·영상 권한 설정 전에는 실제 자동 업로드가 실행되지 않습니다.
- GitHub Actions 예약 작업은 지정 시각보다 늦게 시작될 수 있습니다. 따라서 매일 09:00에 정확히 **업로드 완료**를 보장할 수 없습니다. 정해진 시각의 공개가 더 중요하다면 **먼저 제작·업로드**, **YouTube 예약 공개**를 사용하세요.
- 이미 업로드된 비공개 영상의 상태를 일괄 변경하지 않습니다.
- 영상 저작권, 출처, 플랫폼의 이용 규정, YouTube 업로드 할당량을 준수해야 합니다.
- 기존 자막 검사는 9개 시점의 OCR과 Gemini 판단을 결합하지만 **모든 프레임에서 자막이 없다는 것을 100% 증명하지는 못합니다**.
- TikTok 영상 접근 제약/로그인 문제, Tavily 색인 누락, Gemini·YouTube API 장애 시 업로드하지 않을 수 있습니다.
- 하루 한 번 시도만 허용하고, YouTube 업로드 결과가 불확실한 경우에는 **중복 게시를 방지하기 위해 자동 재시도하지 않습니다**.
- 비용이 발생할 수 있습니다: Gemini API 사용량, Tavily 검색량, GitHub Actions 분량, YouTube API 할당량.

## 참고 문서

- YouTube `videos.insert`: https://developers.google.com/youtube/data/reference/rest/v3/videos/insert
- YouTube `status.publishAt`: https://developers.google.com/youtube/data/reference/rest/v3/videos
- GitHub Actions schedule: https://docs.github.com/actions/using-workflows/events-that-trigger-workflows#schedule
- Android 백그라운드 제한: https://developer.android.com/develop/background-work/services/fgs/changes
