# Operations & Calibration Guide

## Quick Start
1. Copy `pi/direwolf.conf.example` to `~/direwolf/direwolf.conf` and edit MYCALL, coordinates, beacons.
2. Run `sudo bash pi/install.sh` (on the Pi) to install Direwolf & service file.
3. Start service: `sudo systemctl start direwolf`.
4. Monitor: `journalctl -u direwolf -f`.

## Audio Device Discovery
```
arecord -l
aplay -l
```
Adjust `ADEVICE plughw:Card,Device` in config.

## RX Level Tuning
Watch Direwolf log lines for audio level guidance. Goal: mid-range (50–70%) without clipping.
If clipping: lower radio volume or ALSA capture gain:
```
alsamixer
```
Select the USB sound device and reduce Capture.

## TX Deviation & Timing
- Start with `TXDELAY 300`, reduce in 20 ms steps if reliable decode persists.
- `TXTAIL 30` is usually sufficient; too long wastes airtime.
- Validate by decoding your frames on a second receiver running Direwolf or multimon-ng.

## Manual Test Recording
```
arecord -D plughw:1,0 -f S16_LE -r 48000 -c 1 -d 10 test.wav
multimon-ng -t wav -a AFSK1200 test.wav
```

## Checking KISS & AGW Ports
If enabled in config:
```
netstat -tnlp | grep 800
```
You should see 8000 (AGW) and 8001 (KISS).

## Updating Direwolf
```
cd ~/direwolf/build
git pull
make -j$(nproc)
sudo make install
sudo systemctl restart direwolf
```

## Adding iGate Later
Uncomment and set:
```
IGLOGIN CALLSIGN-SSID PASSCODE
IGSERVER noam.aprs2.net
IGFILTER r/lat/long/radius_km
```
Obtain passcode using standard APRS passcode generator (based on call).

## GPS Integration (Optional)
- Attach USB GPS; confirm with `cgps -s`.
- Enable `gpsd` on boot.
- Use a script or Direwolf's GPS parsing (if included) to dynamically update beacon (or switch to a cron job rewriting `direwolf.conf`).

## Log Files
If `LOGDIR` is enabled:
- Rotate with logrotate rule in `/etc/logrotate.d/direwolf`.
- Example snippet:
```
/var/log/direwolf/*.log {
  weekly
  rotate 4
  compress
  missingok
  notifempty
}
```

## Troubleshooting
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| No decodes | Wrong ADEVICE or audio cable | Re-list devices, check wiring/volume |
| Clipping warnings | Input too hot | Lower radio volume / ALSA gain |
| Frames truncated | TXDELAY too short | Increase by 40–60 ms |
| Excess airtime | TXDELAY/TXTAIL too long | Trim values |
| No PTT | Using VOX? Need hardware PTT | Enable PTT line / verify serial device |

## Security Hardening
- Change default passwords.
- Disable password SSH login (keys only).
- Firewall AGW/KISS ports if not needed externally.

## Future Enhancements
See `pi/NOTES.md` or root README for roadmap: iGate, remote dashboard, GPS dynamic beacon, watchdog.
