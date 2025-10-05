#!/usr/bin/env bash
set -euo pipefail

DW_SRC="$HOME/direwolf"
DW_BUILD="$DW_SRC/build"

if [ ! -d "$DW_SRC/.git" ]; then
  echo "Direwolf source not found at $DW_SRC. Run install.sh first." >&2
  exit 1
fi

cd "$DW_SRC"
git pull --ff-only

mkdir -p "$DW_BUILD"
cd "$DW_BUILD"
cmake ..
make -j"$(nproc)"
sudo make install

echo "Direwolf updated. Restart service if running:"
echo "  sudo systemctl restart direwolf"