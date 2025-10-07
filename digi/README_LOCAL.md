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

## Offline / SD Card Bootstrap
Low‑memory Pi Zero scenario: stage everything so the device self‑installs Direwolf + service on first boot without a heavy remote IDE session.

Included artifacts:
- `digi/bootstrap.sh` (idempotent, logs to `/var/log/digi-bootstrap.log`)
- `digi/systemd/digi-bootstrap.service` (one‑shot, gated by absence of `/boot/digi-bootstrap.done`)
- `digi/systemd/direwolf.service` (runs as `packet`)
- `digi/systemd/direwolf.service.pi` (alternate unit running as `pi`)

What the bootstrap does:
1. Ensures user `packet` exists (creates if missing).
2. Installs apt dependencies (git, build toolchain, ALSA, GPS libs, multimon-ng, etc.).
3. Clones & builds Direwolf in `/home/packet/direwolf` (if not already present) and runs `make install`.
4. Ensures `/home/packet/digi/direwolf.conf` exists (creates placeholder if missing).
5. Installs and enables `direwolf.service` (if not already installed) and starts it.
6. Writes sentinel `/boot/digi-bootstrap.done` to prevent re-running automatically.

### Method A (preferred): systemd one‑shot
1. Copy the whole repo (or at minimum the `digi/` directory) into `/home/packet/digi` on the SD card rootfs (ext4 partition). Ensure ownership will be fine (it will fix user creation itself).
2. Place `digi/systemd/digi-bootstrap.service` into `/etc/systemd/system/digi-bootstrap.service` (same path is fine if you copied the tree and then copy it over).
3. Enable it:
  `sudo systemctl enable digi-bootstrap.service`
4. Boot (or reboot). Monitor progress:
  `sudo journalctl -u digi-bootstrap.service -f`
5. After completion verify:
  - `ls /boot/digi-bootstrap.done`
  - `systemctl status direwolf`
  - `sudo less /var/log/digi-bootstrap.log`

### Method B: rc.local fallback
If you cannot (or prefer not to) install the systemd bootstrap unit yet, copy `bootstrap.sh` onto the FAT boot partition as `/boot/digi-bootstrap.sh` and add to `/etc/rc.local` before `exit 0`:
```
[ -x /boot/digi-bootstrap.sh ] && /boot/digi-bootstrap.sh || true
```
On success the script writes `/boot/digi-bootstrap.done`; you can delete that file and rerun manually if you need to re-provision.

### Manual re-run
You can safely rerun any time:
`sudo bash /home/packet/digi/bootstrap.sh`

If you want the systemd one‑shot to run again, remove the sentinel first:
`sudo rm /boot/digi-bootstrap.done && sudo systemctl start digi-bootstrap.service`

### Provision SSH keys (passwordless login)
Place a file named `authorized_keys` on the FAT boot partition root (e.g. `D:\authorized_keys`). On first bootstrap run it will be copied into:
 - `/home/packet/.ssh/authorized_keys` (or your `TARGET_USER`)
 - `/home/pi/.ssh/authorized_keys` (if `pi` exists)
Permissions are fixed automatically. Generate a key on Windows PowerShell:
```
ssh-keygen -t ed25519 -f $HOME\.ssh\pidigi -C "pidigi"
Get-Content $HOME\.ssh\pidigi.pub | Out-File -Encoding ascii D:\authorized_keys
```
Then connect after boot:
```
ssh -i $HOME/.ssh/pidigi pi@raspberrypi.local
```

## Unified One-Step Install (after SSH login)
Instead of running individual steps you can execute the consolidated script:
```
sudo bash digi/setup-all.sh --user pi --callsign N0CALL-1 --lat 00^00.00N --lon 000^00.00E --alt 0 --comment "My Digi"
```
Omit or adjust arguments as needed. Re-running will update the repo, rebuild Direwolf, and preserve an existing `direwolf.conf`.

## Keeping SSH Sessions Alive / Avoiding Disconnects
Long builds can outlive a flaky connection. Use one of these:
1. `tmux` (recommended):
  ```
  sudo apt install -y tmux
  tmux new -s pidigi
  # run long commands
  # Detach: Ctrl-b then d; Reattach: tmux attach -t pidigi
  ```
2. OpenSSH keepalives (client side edit `~/.ssh/config` on your workstation):
  ```
  Host raspberrypi 192.168.* *.local
    ServerAliveInterval 30
    ServerAliveCountMax 4
  ```
3. `screen` alternative:
  ```
  sudo apt install -y screen
  screen -S pidigi
  # detach: Ctrl-a d; list: screen -ls; resume: screen -r pidigi
  ```
If a session drops inside tmux/screen, just reconnect via SSH and reattach—your process continues running.

