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

## Headless SD-Card Prep on Windows (no SSH)
Goal: Prepare an SD so the Pi Zero 2 W boots without a monitor/keyboard and begins beaconing using your preloaded settings.

What you need
- Windows PC with PowerShell
- SD card flashed with Raspberry Pi OS Lite (use Raspberry Pi Imager)
- This repository cloned or downloaded on Windows

Step 1 — Get the repo onto your Windows machine
- Option A (Git for Windows):
  - Install Git for Windows, then in PowerShell: `git clone https://github.com/Dualfuel671/PiDigi.git`
- Option B (ZIP):
  - Click “Code > Download ZIP” on GitHub, then extract the archive locally.

Step 2 — Preseed station settings on the SD boot partition
- Insert the SD; note the boot drive letter (e.g., `E:`). The boot partition is the small FAT volume visible in Windows.
- Option A (recommended): run the helper to generate `/boot/pidigi.env`:
  - PowerShell (as your user):
    - `PowerShell -ExecutionPolicy Bypass -File .\digi\windows-prep-sd.ps1 -BootDriveLetter E: -Callsign KE8DCJ-1 -Lat '47^15.00N' -Lon '088^27.00W' -Alt 1260 -Comment 'AIOC Digi' -AudioName 'AllInOneCable' -CM108Hidraw 'hidraw1'`
- Option B (manual): copy `digi/pidigi.env.example` to the boot partition and rename to `pidigi.env`, then edit values (CALLSIGN, LAT/LON, ALT, ADEVICE, PTT_LINE, etc.).

Step 3 — Stage the digi files and bootstrap service onto the Linux rootfs
Windows can’t natively write the Linux partition. Use WSL to mount the SD’s ext4 partition, or a third‑party driver.

- Windows 11 (WSL supports `--mount`):
  1. Open PowerShell as Administrator and list disks to find the SD by size:
    - `Get-Disk`
  2. Mount the Linux rootfs partition (typically partition 2):
    - `wsl --mount \\.\PHYSICALDRIVE<N> --partition 2`
    - WSL will auto-mount at: `/mnt/wsl/PHYSICALDRIVE<N>/part2`
  3. Open your WSL distro (e.g., Ubuntu) and copy from your Windows repo (under `/mnt/c/...`) to the SD rootfs mount:
    - `sudo mkdir -p /mnt/wsl/PHYSICALDRIVE<N>/part2/home/packet/digi`
    - `sudo cp -r /mnt/c/Path/To/PiDigi/digi/* /mnt/wsl/PHYSICALDRIVE<N>/part2/home/packet/digi/`
    - `sudo cp /mnt/c/Path/To/PiDigi/digi/systemd/digi-bootstrap.service /mnt/wsl/PHYSICALDRIVE<N>/part2/etc/systemd/system/digi-bootstrap.service`
    - (optional) `sudo cp /mnt/c/Path/To/PiDigi/digi/udev/99-cm108-ptt.rules /mnt/wsl/PHYSICALDRIVE<N>/part2/etc/udev/rules.d/`
  4. Back in Admin PowerShell, unmount when done:
    - `wsl --unmount \\.\PHYSICALDRIVE<N>`

- Windows 10:
  - If you installed the latest WSL from the Microsoft Store and `wsl --mount` is available, follow the Windows 11 steps above.
  - If `wsl --mount` isn’t available on your build, use one of these:
   - Third‑party ext4 driver (e.g., “Linux File Systems for Windows by Paragon”) to mount the rootfs and copy the same files to `/home/packet/digi`, `/etc/systemd/system/`, and `/etc/udev/rules.d/`.
   - Or use the rc.local fallback from “Offline / SD Card Bootstrap”: place `digi/bootstrap.sh` on the boot partition as `/boot/digi-bootstrap.sh` and add the rc.local line after first boot via a monitor/keyboard session if you can’t access the ext4 partition from Windows.

On first boot, the one‑shot bootstrap will:
- Create the service user if missing (default `packet` or `USER` from pidigi.env)
- Install dependencies, clone/build Direwolf
- Generate `/home/<user>/digi/direwolf.conf` from your `/boot/pidigi.env`
- Add the user to audio/plugdev/input as needed
- Enable and start Direwolf
- Write `/boot/digi-bootstrap.done`

Tip: For testing only, set `PBEACON_DELAY=5` and `PBEACON_EVERY=1` in `pidigi.env` and omit `PBEACON_VIA` to keep transmissions local. Restore a responsible interval afterward.

## Troubleshooting: TX keys immediately or no tones
- Symptom: Radio keys as soon as Direwolf starts and stays keyed.
  - If using VOX, ensure all PTT lines are commented in `direwolf.conf` (no `PTT ...`).
  - If using CM108 GPIO PTT, use only one PTT method. Remove serial PTT lines.
  - CM108: stray GPIO wiring can assert PTT; verify wiring or temporarily comment `PTT CM108` to test.
  - Some Baofeng VOX levels are very sensitive; reduce VOX level or set PTT control instead of VOX.
- Symptom: No AFSK tones heard while keyed.
  - Verify ALSA device and mono channel: set `ADEVICE plughw:0,0` (or per `aplay -l`) and `ACHANNELS 1`.
  - Run `alsamixer` and select the correct sound card (F6). Raise PCM/Output and ensure not muted (MM).
  - Foreground test for errors:
    - Stop service: `sudo systemctl stop direwolf`
    - Run: `/usr/local/bin/direwolf -c /home/<user>/digi/direwolf.conf -t 0`
    - Watch for messages like "audio open error" or device busy.
  - Increase `TXDELAY` (e.g., 30 = 300ms) if VOX clips the packet start.
  - Confirm `MODEM 1200` is present and only one audio channel is used.
  - If your interface uses DC-coupled audio, add a series capacitor to block PTT bias from audio path.

## Verifying headless bring‑up
- Power the Pi with the AIOC and radio connected/configured.
- Allow several minutes on first boot (build + install). Subsequent boots are fast.
- You should hear AFSK tones per your beacon cadence.

## Working reference: AIOC + CM108 PTT
This is a minimal, proven config for an AIOC cable using the CM108 GPIO for PTT and the AIOC audio as both RX/TX.

Example `direwolf.conf` snippet:

```
ADEVICE plughw:AllInOneCable,0 plughw:AllInOneCable,0
ARATE 48000
ACHANNELS 1
MODEM 1200
MYCALL KE8DCJ-1
PTT CM108 /dev/hidraw1

# Timing
TXDELAY 30
TXTAIL 30

# Digi & beacons (set responsibly after testing)
DIGIPEAT 0 0 ^WIDE[12]-[1-2]$ ^WIDE([12])-(\d)$
# During testing, keep short and local (no via=):
# PBEACON delay=5 every=1 symbol=/r lat=47^15.00N long=088^27.00W alt=1260 comment="TEST"
# Restore to something like every=15 via=WIDE2-1 after verification.
```

Permissions and ownership (replace <user> with your service user, e.g., `pi` or `packet`):

```bash
sudo chown <user>:<user> /home/<user>/digi/direwolf.conf
sudo chmod 640 /home/<user>/digi/direwolf.conf

# Allow audio access
sudo usermod -aG audio <user>

# Allow CM108 /dev/hidraw access (group depends on your distro rules)
# 1) Check current device permissions
ls -l /dev/hidraw1

# 2) If needed, add user to the group owning hidraw (often plugdev or input)
sudo usermod -aG plugdev <user>  # or: sudo usermod -aG input <user>

# 3) Optional: make it consistent with a udev rule for CM108
cat | sudo tee /etc/udev/rules.d/99-cm108-ptt.rules > /dev/null <<'RULE'
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0d8c", MODE="0660", GROUP="plugdev"
RULE
sudo udevadm control --reload
sudo udevadm trigger
# Unplug/replug the AIOC afterwards
```

Foreground test and service control:

```bash
sudo systemctl stop direwolf
/usr/local/bin/direwolf -c /home/<user>/digi/direwolf.conf -t 0
# Expect to see PTT ON/OFF around beacon time and no ALSA errors.

# When satisfied, run as a service again
sudo systemctl start direwolf
sudo systemctl status direwolf --no-pager
```

Optional: commit and push your working config to GitHub (from your repo root on the Pi):

```bash
git add digi/direwolf.conf digi/README_LOCAL.md
git commit -m "AIOC CM108 working config: ALSA device, ARATE, PTT; permissions notes"
git push
```

