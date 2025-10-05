# APRS Digipeater (Raspberry Pi Zero 2 W + AIOC + Baofeng UV-5R)

This repository now targets a **Raspberry Pi Zero 2 W** acting as an **APRS / AX.25 1200 baud digipeater** using an **AIOC (All‑In‑One Cable)** for audio + PTT interfacing to a **Baofeng UV‑5R**. The earlier ESP32 AFSK experimental transmitter code has been removed as per project pivot (Option C). The new focus is rapid deployment of a reliable, maintainable digipeater with room for later iGate, GPS, and remote management features.

## Repository Layout
```
digi/
  direwolf.conf              # Active Direwolf config (edit MYCALL, coords)
  direwolf.conf.example      # Reference template
  scripts/
    install.sh               # Build & install Direwolf
    update.sh                # Update Direwolf from source
    health.sh                # Quick status diagnostics
  systemd/
    direwolf.service         # Systemd unit file (copy to /etc/systemd/system)
  README_LOCAL.md            # Local operational notes
README.md                    # (This file)
```

## Quick Start (On the Pi)
1. Copy repo to Pi (git clone or scp).
2. Edit `digi/direwolf.conf` (or copy from example and adjust `MYCALL`, coordinates, beacon text).
3. Run the installer:
    ```
    sudo bash pi/install.sh
    ```
4. (Optional) Enable & start as a service:
    ```
    sudo systemctl start direwolf
    journalctl -u direwolf -f
    ```
5. Adjust radio volume and ALSA capture gain until Direwolf reports good audio level (no clipping).

## Key Components
| Component | Role |
|-----------|------|
| Raspberry Pi Zero 2 W | Host running Direwolf modem + digi logic |
| AIOC Cable | USB sound + PTT interface (isolation, level shifting) |
| Baofeng UV-5R | RF front end (simplex APRS channel) |
| Direwolf | Software TNC (decode/encode AX.25, digipeat rules) |

## Direwolf Highlights in Template
- `ADEVICE plughw:1,0` (adjust to your USB sound card indices)
- `MODEM 1200` AFSK 1200 baud
- `DIGIPEAT` rule covering WIDE1-1 fill-in & WIDE2-N
- Dual `PBEACON` entries (short + status)
- KISS / AGW TCP ports enabled (8000 / 8001) for future monitoring

## Operations & Calibration
Detailed procedures: see `digi/README_LOCAL.md` and `digi/scripts/health.sh`.
Includes:
- RX/TX level tuning
- Verifying decode
- Adjusting `TXDELAY` / `TXTAIL`
- Optional iGate activation steps

## Roadmap
- Optional iGate (APRS-IS uplink)
- GPS integration (dynamic beacon, altitude)
- Remote monitoring (web dashboard or Prometheus exporter)
- Watchdog & health beacons
- Auto update script

## Security Essentials
- Change default passwords (`passwd`)
- Use SSH keys; disable password auth in `/etc/ssh/sshd_config`
- Restrict KISS/AGW ports (bind to localhost or firewall) if not needed externally

## Contributing
Pull requests welcome for: improved digipeat rules, dynamic beacon scripts, iGate integration, monitoring tooling.

## License
Specify your chosen license (MIT / Apache-2.0 / etc.) if you plan to share publicly.

---
Removed ESP32 AFSK prototype per project pivot. If you later want to reintroduce embedded transmitter logic, create a separate branch or a `firmware/` subtree and keep Pi assets isolated.
