#!/usr/bin/env bash
# bootstrap.sh - First boot installer for Direwolf digi (runs manually or via rc.local / systemd)
# Idempotent: safe to re-run; will skip steps if already done.
set -euo pipefail
LOG=/var/log/digi-bootstrap.log
exec >>"$LOG" 2>&1

echo "[BOOTSTRAP] Started at $(date)"

# Optional preseed from /boot
ENV_FILE=/boot/pidigi.env
if [ -f "$ENV_FILE" ]; then
  echo "[BOOTSTRAP] Loading environment from $ENV_FILE"
  # shellcheck source=/dev/null
  . "$ENV_FILE"
fi

TARGET_USER=${USER:-${TARGET_USER:-packet}}
HOME_DIR="/home/${TARGET_USER}"
DIGI_DIR="${HOME_DIR}/digi"
SYSTEMD_SERVICE_DST="/etc/systemd/system/direwolf.service"
DIREWOLF_SRC="${HOME_DIR}/direwolf"
AUTHORIZED_KEYS_SRC=/boot/authorized_keys

install_authorized_keys() {
  local user="$1"; shift
  local src="$1"; shift
  local uhome="/home/$user"
  [ -f "$src" ] || return 0
  if id "$user" &>/dev/null; then
    echo "[BOOTSTRAP] Installing authorized_keys for $user"
    mkdir -p "$uhome/.ssh"
    cp "$src" "$uhome/.ssh/authorized_keys"
    chown -R "$user":"$user" "$uhome/.ssh"
    chmod 700 "$uhome/.ssh"
    chmod 600 "$uhome/.ssh/authorized_keys"
  fi
}

# 1. Ensure user exists
if ! id "$TARGET_USER" &>/dev/null; then
  echo "[BOOTSTRAP] Creating user $TARGET_USER"
  useradd -m -s /bin/bash "$TARGET_USER"
fi
install_authorized_keys "$TARGET_USER" "$AUTHORIZED_KEYS_SRC"
install_authorized_keys pi "$AUTHORIZED_KEYS_SRC" || true

# 2. Update apt & install deps
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git build-essential cmake libasound2-dev libudev-dev libgps-dev gpsd gpsd-clients multimon-ng

# 3. Ensure digi directory (assume content pre-staged or create minimal)
if [ ! -d "$DIGI_DIR" ]; then
  echo "[BOOTSTRAP] Creating digi directory skeleton"
  mkdir -p "$DIGI_DIR/scripts" "$DIGI_DIR/systemd"
  chown -R "$TARGET_USER":"$TARGET_USER" "$HOME_DIR"
fi

# 4. Copy service if provided in staged directory (if not already)
if [ -f "$DIGI_DIR/systemd/direwolf.service" ] && [ ! -f "$SYSTEMD_SERVICE_DST" ]; then
  echo "[BOOTSTRAP] Installing direwolf.service"
  cp "$DIGI_DIR/systemd/direwolf.service" "$SYSTEMD_SERVICE_DST"
fi

# 5. Clone/build Direwolf (user context)
if [ ! -d "$DIREWOLF_SRC/.git" ]; then
  echo "[BOOTSTRAP] Cloning Direwolf"
  sudo -u "$TARGET_USER" git clone https://github.com/wb2osz/direwolf.git "$DIREWOLF_SRC"
fi

BUILD_DIR="$DIREWOLF_SRC/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake ..
make -j"$(nproc)"
make install

# 6. Ensure config exists
# Preseeded values with defaults
CALLSIGN=${CALLSIGN:-N0CALL-1}
LAT=${LAT:-00^00.00N}
LON=${LON:-000^00.00E}
ALT=${ALT:-0}
COMMENT=${COMMENT:-Bootstrap Digi}
ADEVICE_RX=${ADEVICE_RX:-plughw:0,0}
ADEVICE_TX=${ADEVICE_TX:-$ADEVICE_RX}
ARATE=${ARATE:-48000}
ACHANNELS_VAL=${ACHANNELS:-1}
PTT_LINE=${PTT_LINE:-}
PBEACON_DELAY=${PBEACON_DELAY:-30}
PBEACON_EVERY=${PBEACON_EVERY:-15}
PBEACON_VIA=${PBEACON_VIA:-via=WIDE2-1}
SYMBOL=${SYMBOL:-/r}
FORCE_CONFIG=${FORCE_CONFIG:-0}

CONF="$DIGI_DIR/direwolf.conf"
if [ ! -f "$CONF" ] || [ "$FORCE_CONFIG" = "1" ]; then
  echo "[BOOTSTRAP] Writing direwolf.conf (FORCE_CONFIG=$FORCE_CONFIG)"
  mkdir -p "$DIGI_DIR"
  {
    echo "ADEVICE $ADEVICE_RX $ADEVICE_TX"
    echo "ARATE $ARATE"
    echo "ACHANNELS $ACHANNELS_VAL"
    echo "MODEM 1200"
    echo "MYCALL $CALLSIGN"
    if [ -n "$PTT_LINE" ]; then
      echo "$PTT_LINE"
    fi
    echo "TXDELAY 30"
    echo "TXTAIL 30"
    echo "DWAIT 0"
    echo "SLOTTIME 0"
    echo "PERSIST 63"
    echo "DIGIPEAT 0 0 ^WIDE[12]-[1-2]$ ^WIDE([12])-(\\d)$"
    echo "PBEACON delay=$PBEACON_DELAY every=$PBEACON_EVERY $PBEACON_VIA symbol=$SYMBOL lat=$LAT long=$LON alt=$ALT comment=\"$COMMENT\""
    echo "AGWPORT 8000"
    echo "KISSPORT 8001"
  } > "$CONF"
  chown "$TARGET_USER":"$TARGET_USER" "$CONF"
fi

# Ensure user has audio (and potentially hidraw) access
usermod -aG audio "$TARGET_USER" || true
case "$PTT_LINE" in
  *CM108*|*/dev/hidraw*) usermod -aG plugdev "$TARGET_USER" 2>/dev/null || true ; usermod -aG input "$TARGET_USER" 2>/dev/null || true ;;
esac

# 7. Enable & start service
if systemctl list-unit-files | grep -q '^direwolf.service'; then
  echo "[BOOTSTRAP] Enabling Direwolf service"
  systemctl enable direwolf || true
  systemctl restart direwolf || true
else
  echo "[BOOTSTRAP] WARNING: direwolf.service not found; manual enable required."
fi

# 8. Mark success
marker=/boot/digi-bootstrap.done
if [ -w /boot ]; then
  echo "[BOOTSTRAP] Success $(date)" > "$marker"
fi

echo "[BOOTSTRAP] Completed at $(date)"
