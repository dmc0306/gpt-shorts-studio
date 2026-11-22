# Shorts Studio — Windows PC에서 하루 2회 자동 제작, 09시/21시 YouTube 예약 공개

## 무엇이 바뀌었나요?

| 구분 | 오전 슬롯 | 오후 슬롯 |
|---|---|---|
| Windows 작업 스케줄러 제작 시작 | 06:00 KST | 18:00 KST |
| YouTube 예약 공개 시각 | 09:00 KST | 21:00 KST |
| 중복 실행 기록 | morning.json | evening.json |
| 이미 사용한 영상 기록 | 두 슬롯에서 공유 | 두 슬롯에서 공유 |

두 영상의 **공개 예정 시각이 12시간 간격**입니다. 두 번 제작/업로드를 **시도**하지만 검색 결과·권리·영상 검사·API·PC 상태에 따라 0~2개만 게시될 수도 있습니다. 예약 접수가 끝난 영상은 PC가 꺼져도 YouTube가 해당 시각에 공개할 수 있습니다. 아직 제작되지 않은 새 영상은 PC를 켜지 않으면 만들 수 없습니다.

**기본 설정은 비활성화**입니다. 승인한 제작자·계정·비밀값을 입력하고 직접 enabled=true를 설정하기 전에는 업로드하지 않습니다. GitHub Actions와 별개이며, Android 앱의 예약 업로드 UI도 변경하지 않습니다. Windows가 한국 시간대이고 **해당 사용자가 로그인해 있어야** 두 작업이 시작됩니다.

## 1. 준비

Windows PC에 Python 3.11+, FFmpeg(명령 `ffmpeg`, `ffprobe`), Tesseract OCR(`kor`, `eng` 언어 데이터), `Noto Sans CJK KR` 또는 동등한 한국어 폰트를 설치하고 경로(PATH)를 맞춥니다. 설치된 FFmpeg가 `ass` 자막 필터를 포함해야 합니다.

PowerShell에서 저장소를 열고:

```powershell
cd C:\path\to\gpt-shorts-studio
python --version
python -m pip install -r automation\requirements.txt
ffmpeg -version
ffprobe -version
tesseract --list-langs
```

영상 파일 다운로드와 편집에는 yt-dlp·Tavily·Gemini·FFmpeg 등이 사용됩니다. 해당 서비스를 이용할 수 없으면 실패한 슬롯에서 업로드를 진행하지 않습니다.

## 2. Windows 작업 두 개 등록 (업로드 활성화 아님)

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\install_windows.ps1
```

- `ShortsStudio-Morning`: Windows 로컬 시간 매일 06:00
- `ShortsStudio-Evening`: Windows 로컬 시간 매일 18:00

처음 실행하면 `%LOCALAPPDATA%\ShortsStudioAutomation\daily_config.json`이 **enabled=false**로 생성됩니다. 이미 있으면 덮어쓰지 않습니다.

Windows 시간대를 확인합니다:

```powershell
Get-TimeZone
```

한국이 아니면 Windows 시간 설정에서 **(UTC+09:00) 서울**로 바꿔야 06:00/18:00에 실행됩니다. 사용자가 로그인 중이고 절전 모드가 아니어야 합니다. 전원/절전 설정은 스스로 조정하세요.

## 3. Desktop Google OAuth 갱신 토큰과 API 키 준비

Android 앱의 Chrome OAuth 토큰이 자동으로 Windows에 복사되지 않습니다. Google Cloud의 **동일한 프로젝트**에서 **데스크톱 앱 유형** OAuth 클라이언트를 준비한 뒤:

```powershell
python automation\get_youtube_refresh_token.py
```

Chrome 로그인에서 자신이 소유한 YouTube 채널을 승인하고 새 refresh token을 발급받으세요. 이전 `invalid_grant` 토큰을 재사용하지 않습니다. Google OAuth 게시 상태가 Testing이면 새 토큰도 7일 제한을 받을 수 있으므로 Production 상태를 먼저 확인하세요.

이어서 아래 파일을 **저장소 밖**에 만들어 값을 채웁니다.

```powershell
notepad "$env:LOCALAPPDATA\ShortsStudioAutomation\server.env"
```

```dotenv
GEMINI_API_KEY=YOUR_GEMINI_API_KEY
TAVILY_API_KEY=YOUR_TAVILY_API_KEY
YOUTUBE_CLIENT_ID=YOUR_DESKTOP_OAUTH_CLIENT_ID
YOUTUBE_CLIENT_SECRET=YOUR_DESKTOP_OAUTH_CLIENT_SECRET
YOUTUBE_REFRESH_TOKEN=YOUR_FRESH_REFRESH_TOKEN
```

- `server.env`는 **암호화 파일이 아니므로** Windows 사용자 계정과 디스크 접근을 보호하세요. GitHub에 올리거나 채팅으로 공유하면 안 됩니다.
- 데스크톱 OAuth 클라이언트 ID/Secret은 Android OAuth 클라이언트와 다릅니다.
- 토큰을 발급받는 동안 민감한 사용자 데이터를 녹화·공유하지 마세요.

## 4. 로컬 설정에서 사용자 승인 후 활성화

```powershell
notepad "$env:LOCALAPPDATA\ShortsStudioAutomation\daily_config.json"
```

다음 값들을 실제 계정 정보에 맞게 설정하고 저장합니다.

```json
{
  "enabled": true,
  "timezone": "Asia/Seoul",
  "run_time": "06:00",
  "publish_mode": "scheduled",
  "publish_time": "09:00",
  "topic": "귀여운 동물, 재미있는 반전, 짧은 일상 상황",
  "licensed_tiktok_creators": ["OWN_OR_LICENSED_CREATOR"],
  "rights_attested": true,
  "youtube_channel_id": "UCxxxxxxxxxxxxxxxxxxxxxx",
  "gemini_model": "gemini-3.5-flash",
  "max_candidates": 8,
  "min_duration_seconds": 5,
  "max_duration_seconds": 60
}
```

위는 **입력 예시**입니다. `UC...` 채널 ID와 제작자 계정은 정확한 실제 값으로 바꿔야 합니다. `rights_attested=true`는 해당 영상의 수정·재게시 허가를 확인한 경우에만 선택하세요. 검색 결과에 나왔다는 이유만으로 타인의 영상을 재게시할 권리는 생기지 않습니다.

설정의 `run_time`과 `publish_time`은 구버전과 호환되는 기본 필드입니다. **Windows 전용 실행기는 고정된 오전/오후 두 슬롯의 06/18시 제작과 09/21시 공개 예약을 각각 적용**합니다. 두 슬롯을 다른 시각으로 바꾸려면 `windows_twice_daily.py`의 SLOTS 및 Windows 작업 트리거를 함께 변경해야 합니다.

## 5. 안전한 점검, 실행 결과 확인

```powershell
python automation\windows_twice_daily.py --slot morning --dry-run
python automation\windows_twice_daily.py --slot evening --dry-run
Get-ScheduledTask -TaskName "ShortsStudio-*"
```

`--dry-run`은 예약 가능 여부만 출력하고 **비밀값 조회·영상 검색·상태 변경·업로드를 하지 않습니다**. 아직 시간 전이거나 오늘 해당 슬롯이 이미 시도되었다면 실행하지 않는 게 정상입니다.

실제 실행 로그 및 상태는 아래에만 남습니다.

- `%LOCALAPPDATA%\ShortsStudioAutomation\logs\YYYY-MM-DD_morning.log`
- `%LOCALAPPDATA%\ShortsStudioAutomation\logs\YYYY-MM-DD_evening.log`
- `%LOCALAPPDATA%\ShortsStudioAutomation\state\morning.json`
- `%LOCALAPPDATA%\ShortsStudioAutomation\state\evening.json`

두 슬롯은 **같은 원본 사용 기록을 병합**합니다. 각 슬롯의 작업은 원격 업로드 전에 먼저 날짜를 예약합니다. 실행 도중 오류가 나거나 YouTube 응답이 유실된 경우 같은 슬롯에서 자동 재시도하지 않아 중복 게시 위험을 줄입니다.

예약 공개까지 2시간 이하로 남았으면 실행하지 않습니다. 편집이 오래 걸려 마감 시각을 넘었다면 **다음 날 공개로 자동 이월하지 않고 실패**합니다. 따라서 하루 2개가 반드시 보장되지는 않습니다.

## 6. 일시 중지, 삭제

- 작업 중지: 작업 스케줄러에서 `ShortsStudio-Morning`, `ShortsStudio-Evening` 사용 안 함 처리
- 자동 업로드 중지: `daily_config.json`의 `enabled`를 `false`로 변경
- 작업만 제거: `powershell -ExecutionPolicy Bypass -File .\automation\install_windows.ps1 -Uninstall`

이미 YouTube에 접수된 예약 영상은 작업을 중지하더라도 남아 있습니다. 삭제·공개 취소는 YouTube Studio에서 별도로 해야 합니다.

## 테스트

Windows에서 네트워크 호출 없이 시간·상태·안전 규칙 확인:

```powershell
python automation\test_windows_twice_daily.py
```

Windows에서는 기존 Linux `fcntl` 기반 테스트 파일을 포함하는 전체 `test_*.py` 일괄 실행 대신 위 Windows 전용 테스트를 사용합니다.

**주의:** 저장소 코드·단위 테스트만으로 실제 PC의 작업 실행이나 YouTube API 업로드 성공을 보장할 수 없습니다. 자동 게시를 시작하기 전 본인 소유 영상으로 1회 비공개 업로드를 검증하세요.
