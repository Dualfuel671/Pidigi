#!/usr/bin/env bash
# firstrun-example.sh -- One-shot first boot provisioning for PiDigi
# Place (renamed to firstrun.sh) on the FAT boot partition along with optional:
#   authorized_keys      -> SSH public keys
#   userconf.txt         -> (Optional) Raspberry Pi OS user & hashed password
# Idempotent: safe to re-run; will skip steps if already satisfied.

set -euo pipefail
LOG=/var/log/pidigi-firstrun.log
exec >>"$LOG" 2>&1

echo "[FIRSTRUN] Started $(date)"

# -------- Configuration (override via env if desired) --------
PIDIGI_USER=${PIDIGI_USER:-packet}
CLONE_URL=${CLONE_URL:-https://github.com/Dualfuel671/PiDigi.git}
REPO_DIR=/home/${PIDIGI_USER}/PiDigi
DIGI_DIR=/home/${PIDIGI_USER}/digi
AUTHORIZED_KEYS_SRC=/boot/authorized_keys
SENTINEL=/boot/pidigi-firstrun.done

# If sentinel exists, exit quietly
if [ -f "$SENTINEL" ]; then
  echo "[FIRSTRUN] Sentinel present; nothing to do."
  exit 0
fi

# -------- Helpers --------
install_keys() {
  local user="$1"; local src="$2"; local uhome="/home/$user"
  [ -f "$src" ] || return 0
  id "$user" &>/dev/null || return 0
  echo "[FIRSTRUN] Installing authorized_keys for $user"
  mkdir -p "$uhome/.ssh"
  cp "$src" "$uhome/.ssh/authorized_keys"
  chown -R "$user":"$user" "$uhome/.ssh"
  chmod 700 "$uhome/.ssh" && chmod 600 "$uhome/.ssh/authorized_keys"
}

ensure_user() {
  local user="$1"
  if ! id "$user" &>/dev/null; then
    echo "[FIRSTRUN] Creating user $user"
    useradd -m -s /bin/bash "$user"
  fi
}

clone_repo() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "[FIRSTRUN] Cloning repo -> $REPO_DIR"
    sudo -u "$PIDIGI_USER" git clone --depth 1 "$CLONE_URL" "$REPO_DIR"
  else
    echo "[FIRSTRUN] Repo exists; pulling latest"
    (cd "$REPO_DIR" && sudo -u "$PIDIGI_USER" git pull --ff-only || true)
  fi
}

# -------- System prep --------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git build-essential cmake libasound2-dev libudev-dev libgps-dev gpsd gpsd-clients multimon-ng

ensure_user "$PIDIGI_USER"
install_keys pi "$AUTHORIZED_KEYS_SRC" || true
install_keys "$PIDIGI_USER" "$AUTHORIZED_KEYS_SRC" || true

# -------- Repo / digi directory --------
clone_repo
# If repo layout differs (digi/ lives at repo root), symlink convenience
if [ ! -d "$DIGI_DIR" ] && [ -d "$REPO_DIR/digi" ]; then
  ln -s "$REPO_DIR/digi" "$DIGI_DIR"
fi
chown -h "$PIDIGI_USER":"$PIDIGI_USER" "$DIGI_DIR" 2>/dev/null || true

# -------- Direwolf build --------
DW_SRC=/home/${PIDIGI_USER}/direwolf
if [ ! -d "$DW_SRC/.git" ]; then
  echo "[FIRSTRUN] Cloning Direwolf"
  sudo -u "$PIDIGI_USER" git clone https://github.com/wb2osz/direwolf.git "$DW_SRC"
fi
mkdir -p "$DW_SRC/build"
cd "$DW_SRC/build"
cmake ..
make -j"$(nproc)"
make install

# -------- Config file --------
CONF="$DIGI_DIR/direwolf.conf"
if [ ! -f "$CONF" ]; then
  echo "[FIRSTRUN] Creating placeholder direwolf.conf"
  cat > "$CONF" <<'EOF'
ADEVICE plughw:1,0
ACHANNELS 1
MODEM 1200
MYCALL N0CALL-1
TXDELAY 300
TXTAIL 30
DIGIPEAT 0 0 ^WIDE[12]-[1-2]$ ^WIDE([12])-(\d)$
PBEACON delay=30 every=15 via=WIDE2-1 symbol=/r lat=00^00.00N long=000^00.00E alt=0 comment="FirstRun Digi"
AGWPORT 8000
KISSPORT 8001
EOF
  chown "$PIDIGI_USER":"$PIDIGI_USER" "$CONF"
fi

# -------- Systemd service (packet user variant) --------
SERVICE_DST=/etc/systemd/system/direwolf.service
if [ ! -f "$SERVICE_DST" ]; then
  echo "[FIRSTRUN] Installing systemd unit"
  cat > "$SERVICE_DST" <<EOF
[Unit]
Description=Direwolf APRS Digipeater (first-run)
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=${PIDIGI_USER}
WorkingDirectory=${DIGI_DIR}
ExecStart=/usr/local/bin/direwolf -c ${DIGI_DIR}/direwolf.conf -t 0
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

systemctl daemon-reload || true
systemctl enable direwolf || true
systemctl restart direwolf || true

# -------- Finalize --------
echo "[FIRSTRUN] Success $(date)" > "$SENTINEL"
chmod 644 "$SENTINEL"

echo "[FIRSTRUN] Completed $(date)"