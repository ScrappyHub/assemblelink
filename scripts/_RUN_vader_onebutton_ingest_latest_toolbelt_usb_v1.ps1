param(
  [Parameter(Mandatory=$false)][string]$PacketId = "",
  [Parameter(Mandatory=$false)][string]$UsbDriveLetter = "",
  [Parameter(Mandatory=$false)][string]$InboxRoot = "C:\dev\assemblelink\toolbelt\inbox"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Ingest = Join-Path $ScriptsDir "_RUN_vader_ingest_toolbelt_usb_v2.ps1"
if(-not (Test-Path -LiteralPath $Ingest -PathType Leaf)){ Die ("MISSING_DEP: " + $Ingest) }
$usb = ($UsbDriveLetter.TrimEnd(":") + ":")
if([string]::IsNullOrWhiteSpace($UsbDriveLetter)){
  $candidates = @(
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" |
    ForEach-Object {
      $root = [string]$_.DeviceID
      $outbox = Join-Path $root "echo_transport\toolbelt\outbox"
      $dirs = @()
      if(Test-Path -LiteralPath $outbox -PathType Container){ $dirs = @(Get-ChildItem -LiteralPath $outbox -Force | Where-Object { $_.PSIsContainer }) }
      [pscustomobject]@{ DeviceID=$root; DirCount=@($dirs).Count }
    } |
    Where-Object { $_.DirCount -ge 1 } |
    Sort-Object @{Expression={$_.DeviceID};Descending=$false}
  )
  if(@($candidates).Count -lt 1){ Die "NO_TOOLBELT_USB_OUTBOX_DETECTED" }
  $usb = [string]$candidates[0].DeviceID
}
$usbOutbox = Join-Path $usb "echo_transport\toolbelt\outbox"
if(-not (Test-Path -LiteralPath $usbOutbox -PathType Container)){ Die ("USB_OUTBOX_NOT_FOUND: " + $usbOutbox) }
$chosen = $null
if(-not [string]::IsNullOrWhiteSpace($PacketId)){
  $chosen = $PacketId.Trim()
} else {
  $dirs = @(Get-ChildItem -LiteralPath $usbOutbox -Force | Where-Object { $_.PSIsContainer })
  if(@($dirs).Count -lt 1){ Die ("USB_OUTBOX_EMPTY: " + $usbOutbox) }
  $ordered = @($dirs | Sort-Object @{Expression={$_.LastWriteTimeUtc};Descending=$true}, @{Expression={$_.Name};Descending=$false})
  $chosen = [string]$ordered[0].Name
}
if([string]::IsNullOrWhiteSpace($chosen)){ Die "PACKETID_RESOLVE_FAILED" }
Write-Host ("[ONEBUTTON] Using USB=" + $usb + " packet_id=" + $chosen) -ForegroundColor Cyan
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Ingest -PacketId $chosen -UsbDriveLetter ($usb.TrimEnd(":")) -InboxRoot $InboxRoot
if($LASTEXITCODE -ne 0){ Die ("INGEST_FAILED: exit=" + $LASTEXITCODE) }
$rcpDir = Join-Path $InboxRoot "_receipts"
$rcp = $null
if(Test-Path -LiteralPath $rcpDir -PathType Container){
  $r = @(Get-ChildItem -LiteralPath $rcpDir -Force | Where-Object { -not $_.PSIsContainer -and $_.Name -like "assemblelink.ingest_receipt.v1_*" } | Sort-Object LastWriteTimeUtc -Descending)
  if(@($r).Count -ge 1){ $rcp = $r[0].FullName }
}
$dst = Join-Path $InboxRoot $chosen
Write-Host ("CLEAR_OK_TO_UNPLUG_USB: usb=" + $usb + " packet_id=" + $chosen + " dst=" + $dst + " receipt=" + $rcp) -ForegroundColor Green
