# windows-prep-sd.ps1 - Prep an SD card boot partition with pidigi.env for headless first boot
# Usage (in an elevated PowerShell):
#   .\windows-prep-sd.ps1 -BootDriveLetter E: -Callsign KE8DCJ-1 -Lat '47^15.00N' -Lon '088^27.00W' -Alt 1260 -Comment 'AIOC Digi' -AudioName 'AllInOneCable' -CM108Hidraw 'hidraw1'

param(
  [Parameter(Mandatory=$true)][string]$BootDriveLetter,
  [Parameter(Mandatory=$true)][string]$Callsign,
  [Parameter(Mandatory=$true)][string]$Lat,
  [Parameter(Mandatory=$true)][string]$Lon,
  [Parameter(Mandatory=$true)][int]$Alt,
  [Parameter(Mandatory=$false)][string]$Comment = 'AIOC Digi',
  [Parameter(Mandatory=$false)][string]$User = 'packet',
  [Parameter(Mandatory=$false)][string]$AudioName = 'AllInOneCable',
  [Parameter(Mandatory=$false)][string]$CM108Hidraw = 'hidraw1',
  [Parameter(Mandatory=$false)][int]$PBeaconDelay = 30,
  [Parameter(Mandatory=$false)][int]$PBeaconEvery = 15,
  [Parameter(Mandatory=$false)][string]$PBeaconVia = 'via=WIDE2-1'
)

$boot = $BootDriveLetter.TrimEnd(':') + ':/'
if (-not (Test-Path $boot)) { throw "Boot drive $boot not found" }

$envPath = Join-Path $boot 'pidigi.env'
$content = @()
$content += "USER=$User"
$content += "CALLSIGN=$Callsign"
$content += "LAT=$Lat"
$content += "LON=$Lon"
$content += "ALT=$Alt"
$content += "COMMENT=$Comment"
$content += "SYMBOL=/r"
$content += "ADEVICE_RX=plughw:$AudioName,0"
$content += "ADEVICE_TX=plughw:$AudioName,0"
$content += "ARATE=48000"
$content += "ACHANNELS=1"
if ($CM108Hidraw) { $content += ('PTT_LINE="PTT CM108 /dev/{0}"' -f $CM108Hidraw) }
$content += "PBEACON_DELAY=$PBeaconDelay"
$content += "PBEACON_EVERY=$PBeaconEvery"
if ($PBeaconVia) { $content += ('PBEACON_VIA="{0}"' -f $PBeaconVia) } else { $content += 'PBEACON_VIA=' }
$content += 'FORCE_CONFIG=1'

Set-Content -LiteralPath $envPath -Value ($content -join "`n") -Encoding Ascii
Write-Host "Wrote $envPath"

# Optional: place authorized_keys if present in current directory
$authSrc = Join-Path (Get-Location) 'authorized_keys'
if (Test-Path $authSrc) {
  Copy-Item $authSrc (Join-Path $boot 'authorized_keys') -Force
  Write-Host "Copied authorized_keys to boot partition"
}
