#!/usr/bin/env bash
# setup-all.sh - Unified one-shot installer for Pidigi Direwolf environment
# Usage: bash digi/setup-all.sh [--user pi|packet] [--callsign N0CALL-1] [--lat 00^00.00N] [--lon 000^00.00E] [--alt 0] [--comment "My Digi"]
# Safe to re-run; it will update or skip steps as needed.
set -euo pipefail

# -------- Argument parsing --------
USER_OVERRIDE=""
CALLSIGN="N0CALL-1"
LAT="00^00.00N"
LON="000^00.00E"
ALT="0"
COMMENT="Unified Setup Digi"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_OVERRIDE="$2"; shift 2;;
    --callsign) CALLSIGN="$2"; shift 2;;
    --lat) LAT="$2"; shift 2;;
    --lon) LON="$2"; shift 2;;
    --alt) ALT="$2"; shift 2;;
    --comment) COMMENT="$2"; shift 2;;
    --help|-h)
      grep '^# Usage' "$0" | sed 's/# Usage: //'
      exit 0;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

CURRENT_USER=$(id -un)
TARGET_USER=${USER_OVERRIDE:-$CURRENT_USER}

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run with sudo: sudo bash digi/setup-all.sh [options]" >&2
  exit 1
fi

LOG=/var/log/pidigi-setup-all.log
exec >>"$LOG" 2>&1

echo "[SETUP] Started $(date) as root (target user: $TARGET_USER)"

# -------- Ensure target user exists if different from current --------
if ! id "$TARGET_USER" &>/dev/null; then
  echo "[SETUP] Creating user $TARGET_USER"
  useradd -m -s /bin/bash "$TARGET_USER"
fi

HOME_DIR="/home/$TARGET_USER"
DIGI_DIR="$HOME_DIR/digi"
REPO_ROOT="$HOME_DIR/Pidigi"
AUTHORIZED_KEYS_SOURCE="/boot/authorized_keys"

# -------- Dependencies --------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git build-essential cmake libasound2-dev libudev-dev libgps-dev gpsd gpsd-clients multimon-ng

# -------- Repo clone/update --------
if [ ! -d "$REPO_ROOT/.git" ]; then
  echo "[SETUP] Cloning repository into $REPO_ROOT"
  sudo -u "$TARGET_USER" git clone https://github.com/Dualfuel671/Pidigi.git "$REPO_ROOT"
else
  echo "[SETUP] Updating existing repository"
  (cd "$REPO_ROOT" && sudo -u "$TARGET_USER" git pull --ff-only || true)
fi

# Create digi symlink if not present
if [ ! -d "$DIGI_DIR" ] && [ -d "$REPO_ROOT/digi" ]; then
  ln -s "$REPO_ROOT/digi" "$DIGI_DIR"
fi
chown -h "$TARGET_USER":"$TARGET_USER" "$DIGI_DIR" 2>/dev/null || true

# -------- Authorized keys (optional) --------
if [ -f "$AUTHORIZED_KEYS_SOURCE" ]; then
  echo "[SETUP] Installing authorized_keys for $TARGET_USER"
  mkdir -p "$HOME_DIR/.ssh"
  cp "$AUTHORIZED_KEYS_SOURCE" "$HOME_DIR/.ssh/authorized_keys"
  chown -R "$TARGET_USER":"$TARGET_USER" "$HOME_DIR/.ssh"
  chmod 700 "$HOME_DIR/.ssh"
  chmod 600 "$HOME_DIR/.ssh/authorized_keys"
fi

# -------- Build Direwolf --------
DW_SRC="$HOME_DIR/direwolf"
if [ ! -d "$DW_SRC/.git" ]; then
  echo "[SETUP] Cloning Direwolf"
  sudo -u "$TARGET_USER" git clone https://github.com/wb2osz/direwolf.git "$DW_SRC"
fi
mkdir -p "$DW_SRC/build"
cd "$DW_SRC/build"
cmake ..
make -j"$(nproc)"
make install

# -------- Config file --------
CONF="$DIGI_DIR/direwolf.conf"
if [ ! -f "$CONF" ]; then
  echo "[SETUP] Creating new direwolf.conf with provided parameters"
  mkdir -p "$DIGI_DIR"
  cat > "$CONF" <<EOF
ADEVICE plughw:1,0
ACHANNELS 1
MODEM 1200
MYCALL $CALLSIGN
TXDELAY 300
TXTAIL 30
DIGIPEAT 0 0 ^WIDE[12]-[1-2]$ ^WIDE([12])-(\d)$
PBEACON delay=30 every=15 via=WIDE2-1 symbol=/r lat=$LAT long=$LON alt=$ALT comment="$COMMENT"
AGWPORT 8000
KISSPORT 8001
EOF
  chown "$TARGET_USER":"$TARGET_USER" "$CONF"
else
  echo "[SETUP] Existing direwolf.conf retained"
fi

# -------- Systemd Service --------
SERVICE_DST=/etc/systemd/system/direwolf.service
if [ ! -f "$SERVICE_DST" ]; then
  echo "[SETUP] Installing systemd unit"
  cat > "$SERVICE_DST" <<EOF
[Unit]
Description=Direwolf APRS Digipeater
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
WorkingDirectory=$DIGI_DIR
ExecStart=/usr/local/bin/direwolf -c $DIGI_DIR/direwolf.conf -t 0
Restart=on-failure
RestartSec=5
Nice=-2
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=false
PrivateTmp=yes
ProtectHostname=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable direwolf || true
systemctl restart direwolf || true

# -------- Summary --------
status_line=$(systemctl is-active direwolf || true)
if [[ "$status_line" == active ]]; then
  echo "[SETUP] Direwolf service active"
else
  echo "[SETUP] Direwolf service NOT active; check: systemctl status direwolf"
fi

echo "[SETUP] Complete $(date)"
echo "[SETUP] Log: $LOG"
echo "[SETUP] Next: edit $CONF for correct ADEVICE, MYCALL, coordinates if placeholders remain."
