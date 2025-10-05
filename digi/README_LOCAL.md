# Local Digi Notes

Config: /home/packet/digi/direwolf.conf
Service: systemd unit 'direwolf'
Logs: (enable by uncommenting LOGDIR in config)

Scripts:
  scripts/install.sh   # Initial build
  scripts/update.sh    # Pull & rebuild
  scripts/health.sh    # Status summary

Adjust beacons responsibly; avoid network congestion.

Security:
  - Use SSH keys only (disable password auth when comfortable)
  - Keep system updated: sudo apt update && sudo apt full-upgrade -y

To enable service:
  sudo cp /home/packet/digi/systemd/direwolf.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now direwolf
  journalctl -u direwolf -f

Future:
  - iGate (uncomment IGLOGIN/IGSERVER)
  - GPS dynamic beacon
  - Monitoring export / Prometheus
