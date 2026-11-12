"""Obtain a cloud-only refresh token locally; never run this in GitHub CI."""
import getpass
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES=[
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
]


def main():
    print("Google Cloud Console에서 OAuth 클라이언트 유형 '데스크톱 앱'을 만든 뒤 사용하세요.")
    client_id=input("데스크톱 OAuth Client ID: ").strip()
    client_secret=getpass.getpass("데스크톱 OAuth Client Secret: ")
    if not client_id or not client_secret:
        raise SystemExit("Client ID와 secret이 필요합니다.")
    flow=InstalledAppFlow.from_client_config({
        "installed":{
            "client_id":client_id,
            "client_secret":client_secret,
            "auth_uri":"https://accounts.google.com/o/oauth2/auth",
            "token_uri":"https://oauth2.googleapis.com/token",
            "redirect_uris":["http://localhost"],
        }
    },scopes=SCOPES)
    credentials=flow.run_local_server(host="localhost",port=0,prompt="consent",
                                      access_type="offline",open_browser=True)
    if not credentials.refresh_token:
        raise SystemExit("refresh token 미발급. 기존 연결 권한을 해제한 뒤 재동의가 필요할 수 있습니다.")
    print("\n이 토큰을 GitHub Actions Secrets의 YOUTUBE_REFRESH_TOKEN으로 저장하세요.")
    print("이 화면/터미널 기록을 공개하거나 저장소에 커밋하지 마세요.")
    print("\n" + credentials.refresh_token)


if __name__=="__main__":
    main()
