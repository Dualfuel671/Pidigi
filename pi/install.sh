#!/usr/bin/env bash
# install.sh - Bootstrap Direwolf digipeater environment on Raspberry Pi
# Usage: sudo bash install.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

USER_NAME=${SUDO_USER:-pi}
HOME_DIR=$(eval echo ~"${USER_NAME}")
DIR_DW_SRC="${HOME_DIR}/direwolf"
CONF_DIR="${HOME_DIR}/direwolf"
CONF_FILE="${CONF_DIR}/direwolf.conf"
SERVICE_FILE="/etc/systemd/system/direwolf.service"

apt update
apt full-upgrade -y
apt install -y git build-essential cmake libasound2-dev libudev-dev libgps-dev gpsd gpsd-clients multimon-ng screen

if [[ ! -d ${DIR_DW_SRC} ]]; then
  sudo -u "${USER_NAME}" git clone https://github.com/wb2osz/direwolf.git "${DIR_DW_SRC}"
fi

cd "${DIR_DW_SRC}"
mkdir -p build
cd build
cmake ..
make -j$(nproc)
make install
make install-conf || true

# Copy example config if not present
if [[ ! -f ${CONF_FILE} ]]; then
  sudo -u "${USER_NAME}" mkdir -p "${CONF_DIR}"
  sudo -u "${USER_NAME}" cp /usr/local/share/direwolf/direwolf.conf "${CONF_FILE}" || true
  echo "# See pi/direwolf.conf.example in repo for a tuned config." >> "${CONF_FILE}"
fi

cat > "${SERVICE_FILE}" <<'EOF'
[Unit]
Description=Direwolf APRS TNC/Digipeater
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
ExecStart=/usr/local/bin/direwolf -c /home/pi/direwolf/direwolf.conf -t 0
Restart=on-failure
RestartSec=5
Nice=-2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable direwolf

echo "Installation complete. Edit ${CONF_FILE}, then: systemctl start direwolf"