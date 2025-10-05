#!/usr/bin/env bash
set -euo pipefail

CONF="$HOME/digi/direwolf.conf"
SERVICE_NAME="direwolf"

echo "=== Direwolf Health Check ($(date)) ==="

if systemctl status "$SERVICE_NAME" &>/dev/null; then
  systemctl --no-pager --lines=0 status "$SERVICE_NAME" | head -n 5
else
  echo "Systemd service '$SERVICE_NAME' not found or inactive (might be manual run)."
fi

echo "--- Process Check ---"
pgrep -a direwolf || echo "Direwolf process not found."

echo "--- Disk Space ---"
df -h "$HOME" | tail -n 1

echo "--- Audio Devices (arecord -l) ---"
arecord -l || true

echo "--- Recent Auth Failures ---"
sudo grep 'Failed password' /var/log/auth.log 2>/dev/null | tail -n 5 || echo "No failures or insufficient permission."

echo "--- Listening Ports (8000/8001) ---"
ss -tuln | grep -E ':8000|:8001' || echo "AGW/KISS ports not open."

echo "Health check complete."