# Short Studio — GitHub Actions 없이 매일 한 편 자동 제작

## 어떤 예약인가?

| 설정 | 의미 |
| --- | --- |
| `run_time` | 한국시간 매일 이 시각부터 새 원본 영상 **검색 → 검사 → 제목·자막 생성 → 편집 → YouTube 업로드** 작업을 시작 |
| `publish_mode` | 비공개(`private`), 즉시 공개(`public`), 예약 공개(`scheduled`) |
| `publish_time` | `scheduled`에서 YouTube가 공개할 한국시간. 업로드 진행 시각과 **별개** |

영상 검색·편집·업로드는 [daily_pipeline.py](daily_pipeline.py)를 재사용하고, [run_due.py](run_due.py)가 예약 시각 도달 여부를 검사하며, [configure_local.py](configure_local.py)는 설정만 변경합니다. **예약 실행에는 GitHub Actions가 쓰이지 않습니다.**

이는 **Linux 서버가 실행 중이어야 하는** 방식입니다. 휴대폰의 Android WorkManager 예약 알림과는 독립적입니다. **앱 UI에서 원격 서버 설정을 변경하는 기능은 아직 구현되지 않았습니다.** 설정은 서버의 CLI에서 합니다.

## 1. 설치

서버 OS에 Python 3.11 이상과 `python3-venv`, `ffmpeg`, `ffprobe`, `tesseract` 및 한국어·영어 OCR 언어 데이터, `Noto Sans CJK KR` 폰트가 있어야 합니다. Ubuntu/Debian에서는 예를 들어:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv ffmpeg tesseract-ocr tesseract-ocr-kor tesseract-ocr-eng fonts-noto-cjk
# git clone 후 저장소 최상위 폴더에서:
bash automation/install_systemd_user.sh
```

설치 프로그램은 서버 계정의 `~/.config/systemd/user/`에 타이머/서비스를 만들며, 처음부터 실제 업로드를 허용하지 않습니다.

로그아웃이나 재부팅 후에도 사용자 서비스를 실행하려면 아래 명령이 필요할 수 있습니다.

```bash
sudo loginctl enable-linger "$USER"
```

서버가 꺼져 있거나 네트워크가 불안정하면 지정 시각 실행이나 업로드 완료를 보장할 수 없습니다. 타이머는 1분마다 예약 가능 여부를 검사하며, 실제 시작은 서비스 정책에 따라 지연될 수 있습니다.

## 2. API 비밀값 등록

서버에서 `~/.config/shorts-studio/server.env`에 **개별 줄로** 다음 환경 변수를 넣습니다.

```dotenv
GEMINI_API_KEY=...
TAVILY_API_KEY=...
YOUTUBE_CLIENT_ID=...
YOUTUBE_CLIENT_SECRET=...
YOUTUBE_REFRESH_TOKEN=...
```

이 파일은 Git 저장소에 넣거나 공유하면 안 됩니다. 설치 프로그램이 권한을 `600`으로 제한합니다. 앱에 저장한 API 키/YouTube 로그인은 서버에 자동으로 전달되지 않습니다. YouTube 갱신 토큰 발급 방법은 [README_ko.md](README_ko.md)의 OAuth 절을 참고하세요.

## 3. 제작 예약과 공개 예약을 별도로 설정

다음은 **예시 명령**입니다. 계정·채널 ID를 실제 사용권을 확인한 값으로 바꾸고, 서버의 프로젝트 루트에서 실행합니다.

```bash
export SHORTS_CONFIG_PATH="$HOME/.config/shorts-studio/daily_config.json"
.venv/bin/python automation/configure_local.py \
  --run-time 09:00 \
  --publish-mode scheduled \
  --publish-time 18:00 \
  --topic "귀여운 강아지의 실제 순간" \
  --creators YOUR_AUTHORIZED_ACCOUNT \
  --channel-id UCxxxxxxxxxxxxxxxxxxxxxx \
  --rights-confirmed --enable
```

- 이 예시는 오전 **9시부터** 하루 한 편을 검색·제작·업로드하려고 시도하고, YouTube에 **18시 예약 공개**로 등록합니다.
- `--publish-mode private`면 비공개로 업로드합니다.
- `--publish-mode public --public-approved`는 즉시 전체 공개에 대한 별도 승인이 있어야 합니다.
- 제작 시작 시각만 변경하려면 `--run-time 13:00`만 입력합니다.
- 중단하려면 `--disable`을 사용합니다. 이미 업로드된 YouTube 예약 게시물은 취소되지 않습니다.
- 신규 설정을 반영하기 위해 서비스를 재설치할 필요는 없습니다. 타이머가 다음 점검에 새 JSON을 읽습니다.

## 4. 실행 확인 및 로그

```bash
systemctl --user list-timers shorts-daily.timer
journalctl --user -u shorts-daily.service -n 80 --no-pager
SHORTS_CONFIG_PATH="$HOME/.config/shorts-studio/daily_config.json" \
SHORTS_STATE_PATH="$HOME/.local/state/shorts-studio/daily_state.json" \
.venv/bin/python automation/run_due.py --dry-run
```

`--dry-run`은 실제 검색·업로드·예약 상태 변경을 하지 않습니다. 기본 상태 파일은 `~/.local/state/shorts-studio/daily_state.json`에 있고, 성공한 영상 ID와 사용한 원본 중복 기록이 남습니다.

## 5. 중복 방지와 주의점

1. 매일 한 번 **실행을 시도**합니다. 검색 후보가 없거나 접근 제한, 기존 자막, AI 응답 실패로 원본이 모두 제외되면 그날 업로드는 0편일 수 있습니다.
2. `flock`으로 중복 프로세스 실행을 막고, 원격 업로드 **전에** 날짜 및 원본 사용 기록을 남깁니다.
3. YouTube에 파일이 접수됐지만 응답이 유실된 경우 자동 재업로드하지 않습니다. YouTube Studio에서 확인해야 합니다.
4. 기존 제목 규칙(상·하단 각각 공백 포함 5~11자), 영상 길이·세로형 검사, 9프레임 OCR 및 Gemini 기존 자막 검증을 재사용합니다. 이것이 완벽한 영상 일치나 무자막을 보장하지는 않습니다.
5. 사용자가 소유하거나 수정·재게시 권한을 받은 계정만 등록해야 합니다. 계정 이름만 등록하는 것으로 이용권이 자동으로 증명되지 않습니다.
6. Android 앱의 기존 UI 기반 영상 제작과 서버의 FFmpeg 렌더링은 코드가 별도이므로 편집 결과가 완전히 같지는 않습니다.
7. YouTube API 채널 인증, 공개 승인, 할당량, Gemini 모델 접근 가능 여부, 틱톡 접근, 실서버의 OCR·영상 인코딩과 업로드 완료는 운영 환경에서 따로 확인해야 합니다.

## 6. 테스트

```bash
python3 -m pip install 'regex>=2024.11'
python3 -m compileall -q automation
python3 -m unittest discover -s automation -p 'test_*.py' -v
```

실제 계정/비밀값 없이 예약 시각, 중복 잠금, 상태 보존, 제목 길이 검사를 테스트합니다. 실시간 업로드 테스트가 아닙니다.
