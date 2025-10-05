#!/usr/bin/env bash
set -euo pipefail

# Install Direwolf for user 'packet'
DW_SRC="$HOME/direwolf"
DW_BUILD="$DW_SRC/build"
CONF_PATH="$HOME/digi/direwolf.conf"

sudo apt update
sudo apt install -y git build-essential cmake libasound2-dev libudev-dev libgps-dev gpsd gpsd-clients multimon-ng

if [ ! -d "$DW_SRC" ]; then
  git clone https://github.com/wb2osz/direwolf.git "$DW_SRC"
fi

mkdir -p "$DW_BUILD"
cd "$DW_BUILD"
cmake ..
make -j"$(nproc)"
sudo make install

if [ ! -f "$CONF_PATH" ]; then
  echo "Missing $CONF_PATH - create it before starting service." >&2
fi

echo "Install complete. Run service or:"
echo "  direwolf -c $CONF_PATH -t 0"