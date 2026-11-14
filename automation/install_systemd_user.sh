#!/usr/bin/env bash
# Install a persistent per-user Linux scheduler. Invoke with: bash automation/install_systemd_user.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
CFG_DIR="$HOME/.config/shorts-studio"
STATE_DIR="$HOME/.local/state/shorts-studio"
UNIT_DIR="$HOME/.config/systemd/user"
VENV="$ROOT/.venv"
mkdir -p "$CFG_DIR" "$STATE_DIR" "$UNIT_DIR"

if [ ! -f "$CFG_DIR/daily_config.json" ]; then
    cp "$ROOT/automation/daily_config.json" "$CFG_DIR/daily_config.json"
fi
if [ ! -f "$STATE_DIR/daily_state.json" ]; then
    cp "$ROOT/automation/daily_state.json" "$STATE_DIR/daily_state.json"
fi
if [ ! -f "$CFG_DIR/server.env" ]; then
    cat > "$CFG_DIR/server.env" <<'ENV'
# Fill values locally; never commit this file.
GEMINI_API_KEY=
TAVILY_API_KEY=
YOUTUBE_CLIENT_ID=
YOUTUBE_CLIENT_SECRET=
YOUTUBE_REFRESH_TOKEN=
ENV
fi
chmod 700 "$CFG_DIR" "$STATE_DIR"
chmod 600 "$CFG_DIR/server.env" "$CFG_DIR/daily_config.json" "$STATE_DIR/daily_state.json"

if [ ! -d "$VENV" ]; then
    "$PYTHON" -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install -r "$ROOT/automation/requirements.txt"

cat > "$UNIT_DIR/shorts-daily.service" <<UNIT
[Unit]
Description=Short Studio: check and produce one licensed Short per day
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$ROOT
EnvironmentFile=$CFG_DIR/server.env
Environment=SHORTS_CONFIG_PATH=$CFG_DIR/daily_config.json
Environment=SHORTS_STATE_PATH=$STATE_DIR/daily_state.json
ExecStart=$VENV/bin/python $ROOT/automation/run_due.py
TimeoutStartSec=90min
UNIT

cat > "$UNIT_DIR/shorts-daily.timer" <<'UNIT'
[Unit]
Description=Check daily Short start time every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s
Persistent=true
Unit=shorts-daily.service

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now shorts-daily.timer

echo
echo "Shorts systemd timer installed. It remains OFF until you configure and enable production."
echo "1. Fill secrets: $CFG_DIR/server.env (chmod 600)"
echo "2. Set allowed creator handles, YouTube channel and two independent times:"
echo "   SHORTS_CONFIG_PATH=$CFG_DIR/daily_config.json $VENV/bin/python $ROOT/automation/configure_local.py --run-time 09:00 --publish-time 18:00 --publish-mode scheduled --creators YOUR_ACCOUNT --channel-id UC... --rights-confirmed --enable"
echo "3. Check: systemctl --user list-timers shorts-daily.timer"
echo "4. Logs: journalctl --user -u shorts-daily.service -n 50 --no-pager"
echo "Important: to run after reboot without a login session, an administrator must enable user lingering:"
echo "   sudo loginctl enable-linger $USER"
echo "Required OS packages: ffmpeg, ffprobe, tesseract-ocr (Korean + English language data), and a Korean font."
