<#
.SYNOPSIS
    Offline SD-card staging helper for PiDigi.

.DESCRIPTION
    Mounts a Raspberry Pi OS SD card with WSL, copies the digi/ assets, enables the
    bootstrap systemd service, and writes /boot/pidigi.env so the Pi can boot
    headless and self-provision Direwolf.

.NOTES
    - Requires an elevated PowerShell session (Run as Administrator).
    - Requires Windows Subsystem for Linux with support for `wsl --mount`.
    - Tested on Windows 11; Windows 10 needs the Microsoft Store WSL build.
#>

[CmdletBinding()]
param(
    [int]$DiskNumber,
    [int]$RootfsPartitionNumber,
    [string]$Callsign,
    [string]$Latitude,
    [string]$Longitude,
    [string]$Altitude,
    [string]$Comment,
    [string]$AudioDevice = "plughw:AllInOneCable,0",
    [string]$Ptthidraw = "hidraw1",
    [string]$Symbol = "/r",
    [string]$ServiceUser = "packet"
)
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

function Ensure-Administrator {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $current
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run from an elevated (Run as Administrator) PowerShell session.'
    }
}

function Require-Command([string]$CommandName) {
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$CommandName' is not available in PATH."
    }
}

function Prompt-ForValue {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $suffix = if ([string]::IsNullOrWhiteSpace($Default)) { '' } else { " [${Default}]" }
    $response = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    return $response
}

Ensure-Administrator
Require-Command 'wsl.exe'
Require-Command 'Get-Disk'
Require-Command 'Get-Partition'
Require-Command 'Get-Volume'
Require-Command 'Remove-PartitionAccessPath'

if (-not $DiskNumber) {
    $candidateDisks = Get-Disk | Where-Object {
        $_.IsBoot -eq $false -and $_.IsSystem -eq $false -and $_.BusType -in ('SD','USB','MMC','SATA') -and $_.PartitionStyle -in ('GPT','MBR')
    }
    if (-not $candidateDisks) {
        throw 'No non-system GPT disks detected. Insert the SD card and retry, or specify -DiskNumber explicitly.'
    }
    Write-Host 'Detected removable disks:' -ForegroundColor Cyan
    foreach ($disk in $candidateDisks) {
        $sizeGb = [Math]::Round($disk.Size / 1GB, 2)
        Write-Host ("  #{0,-3} {1,-25} {2,6} GB" -f $disk.Number, $disk.FriendlyName, $sizeGb)
    }
    $DiskNumber = [int](Prompt-ForValue -Prompt 'Enter the disk number for the SD card' -Default $candidateDisks[0].Number)
}

$selectedDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
if ($selectedDisk.IsBoot -or $selectedDisk.IsSystem) {
    throw "Refusing to operate on system disk #{0}. Choose the removable SD card." -f $DiskNumber
}

$confirm = Prompt-ForValue -Prompt ("Type YES to stage disk #{0} ({1})" -f $selectedDisk.Number, $selectedDisk.FriendlyName) -Default ''
if ($confirm -ne 'YES') {
    Write-Host 'Aborted by user.'
    return
}

$partitions = Get-Partition -DiskNumber $DiskNumber
$bootPartition = $partitions | Where-Object { $_.Type -like '*FAT*' -or $_.GptType -eq '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}' -or $_.DriveLetter } | Select-Object -First 1
if (-not $bootPartition) {
    throw "Unable to locate the FAT boot partition on disk #{0}." -f $DiskNumber
}
$bootVolume = Get-Volume -Partition $bootPartition
if (-not $bootVolume.DriveLetter) {
    throw 'Boot partition is not mounted with a drive letter. Assign one in Disk Management and retry.'
}
$bootDrive = "$($bootVolume.DriveLetter):"

$rootfsPartition = $null
if ($RootfsPartitionNumber) {
    $rootfsPartition = $partitions | Where-Object { $_.PartitionNumber -eq $RootfsPartitionNumber }
    if (-not $rootfsPartition) {
        throw "Disk #{0} does not have a partition numbered {1}." -f $DiskNumber, $RootfsPartitionNumber
    }
} else {
    $rootfsPartition = $partitions |
        Where-Object {
            $_.PartitionNumber -ne $bootPartition.PartitionNumber -and (
                $_.GptType -eq '{0FC63DAF-8483-4772-8E79-3D69D8477DE4}' -or
                $_.Type -like '*Linux*' -or
                ($_.DriveLetter -eq $null)
            )
        } |
        Sort-Object -Property Size -Descending |
        Select-Object -First 1
    if (-not $rootfsPartition) {
        throw "Unable to find a Linux rootfs partition on disk #{0}. Specify -RootfsPartitionNumber if the layout is unusual." -f $DiskNumber
    }
}
$rootfsPartitionNumber = $rootfsPartition.PartitionNumber

if ($rootfsPartition.DriveLetter) {
    $accessPath = "$($rootfsPartition.DriveLetter):"
    Write-Host "Rootfs partition is currently mounted at $accessPath; removing drive letter before WSL mount..." -ForegroundColor Yellow
    Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $rootfsPartitionNumber -AccessPath $accessPath -ErrorAction Stop
}

if (-not $Callsign) { $Callsign = Prompt-ForValue -Prompt 'APRS CALLSIGN (e.g. KE8DCJ-1)' -Default $null }
if (-not $Latitude) { $Latitude = Prompt-ForValue -Prompt 'Latitude (e.g. 47^15.00N)' -Default $null }
if (-not $Longitude) { $Longitude = Prompt-ForValue -Prompt 'Longitude (e.g. 088^27.00W)' -Default $null }
if (-not $Altitude) { $Altitude = Prompt-ForValue -Prompt 'Altitude feet (e.g. 1260)' -Default '0' }
if (-not $Comment) { $Comment = Prompt-ForValue -Prompt 'Beacon comment' -Default 'AIOC Digi' }
$AudioDevice = Prompt-ForValue -Prompt 'ALSA device name' -Default $AudioDevice
$Ptthidraw = Prompt-ForValue -Prompt 'CM108 hidraw device (hidrawX)' -Default $Ptthidraw
$ServiceUser = Prompt-ForValue -Prompt 'Service user' -Default $ServiceUser
$Symbol = Prompt-ForValue -Prompt 'APRS symbol (/r, etc.)' -Default $Symbol

if ([string]::IsNullOrWhiteSpace($Callsign) -or [string]::IsNullOrWhiteSpace($Latitude) -or [string]::IsNullOrWhiteSpace($Longitude)) {
    throw 'CALLSIGN, Latitude, and Longitude are required.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoWslPath = (wsl.exe -e wslpath -a $repoRoot).Trim()
if (-not $repoWslPath) {
    throw 'Failed to translate repository path for WSL.'
}

$physicalDrive = "\\\\.\\PHYSICALDRIVE$DiskNumber"
$targetMount = "/mnt/wsl/PHYSICALDRIVE$DiskNumber/part$rootfsPartitionNumber"

$mounted = $false
try {
    Write-Host "Mounting ext4 rootfs from $physicalDrive (partition $rootfsPartitionNumber) via WSL..." -ForegroundColor Cyan
    wsl.exe --mount $physicalDrive --partition $rootfsPartitionNumber | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'wsl --mount failed. Ensure no other process is using the disk and that your WSL build supports disk mounting.'
    }
    $mounted = $true

    $wslScriptTemplate = @'
set -euo pipefail
TARGET='{{TARGET}}'
REPO='{{REPO}}'
SERVICE_USER='{{SERVICE_USER}}'

echo "[PiDigi] Syncing repo into $TARGET/home/$SERVICE_USER/digi"
mkdir -p "$TARGET/home/$SERVICE_USER"
rm -rf "$TARGET/home/$SERVICE_USER/digi.new"
cp -r "$REPO/digi" "$TARGET/home/$SERVICE_USER/digi.new"
rm -rf "$TARGET/home/$SERVICE_USER/digi.bak"
if [ -d "$TARGET/home/$SERVICE_USER/digi" ]; then
  mv "$TARGET/home/$SERVICE_USER/digi" "$TARGET/home/$SERVICE_USER/digi.bak"
fi
mv "$TARGET/home/$SERVICE_USER/digi.new" "$TARGET/home/$SERVICE_USER/digi"

mkdir -p "$TARGET/etc/systemd/system"
cp "$REPO/digi/systemd/digi-bootstrap.service" "$TARGET/etc/systemd/system/digi-bootstrap.service"
mkdir -p "$TARGET/etc/systemd/system/multi-user.target.wants"
ln -sf ../digi-bootstrap.service "$TARGET/etc/systemd/system/multi-user.target.wants/digi-bootstrap.service"

if [ -f "$REPO/digi/udev/99-cm108-ptt.rules" ]; then
  mkdir -p "$TARGET/etc/udev/rules.d"
  cp "$REPO/digi/udev/99-cm108-ptt.rules" "$TARGET/etc/udev/rules.d/99-cm108-ptt.rules"
fi

sync
'@

    $wslScript = $wslScriptTemplate.Replace('{{TARGET}}', $targetMount).Replace('{{REPO}}', $repoWslPath).Replace('{{SERVICE_USER}}', $ServiceUser)
    Write-Host 'Copying digi assets and enabling bootstrap...' -ForegroundColor Cyan
    wsl.exe -u root -- bash -lc $wslScript | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to copy files inside WSL.'
    }
}
finally {
    if ($mounted) {
        Write-Host 'Unmounting disk from WSL...' -ForegroundColor Cyan
        wsl.exe --unmount $physicalDrive | Out-Null
    }
}

$commentEscaped = $Comment -replace '"', '\"'
$pttLine = "PTT CM108 /dev/$Ptthidraw"
$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$envContent = @"
# Auto-generated by PiDigi install.ps1 on $timestamp
USER=$ServiceUser

CALLSIGN=$Callsign
LAT=$Latitude
LON=$Longitude
ALT=$Altitude
COMMENT="$commentEscaped"
SYMBOL=$Symbol

ADEVICE_RX=$AudioDevice
ADEVICE_TX=$AudioDevice
ARATE=48000
ACHANNELS=1
PTT_LINE="$pttLine"

PBEACON_DELAY=30
PBEACON_EVERY=15
PBEACON_VIA="via=WIDE2-1"

FORCE_CONFIG=1
"@

$envPath = Join-Path $bootDrive 'pidigi.env'
Set-Content -Path $envPath -Value $envContent -Encoding Ascii

Write-Host ''
Write-Host 'PiDigi SD card staging complete:' -ForegroundColor Green
Write-Host "  - Rootfs synced to /home/$ServiceUser/digi"
Write-Host "  - digi-bootstrap.service enabled (multi-user target)"
Write-Host "  - pidigi.env written to $envPath"
Write-Host ''
Write-Host 'You can now eject the SD card safely and boot the Pi. The bootstrap will run once and bring Direwolf online without console access.' -ForegroundColor Green
