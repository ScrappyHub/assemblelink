param(
  [Parameter(Mandatory=$true)][string]$PacketId,
  [Parameter(Mandatory=$false)][string]$UsbDriveLetter = "",
  [Parameter(Mandatory=$false)][string]$InboxRoot = "C:\dev\assemblelink\toolbelt\inbox"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $norm = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $norm.EndsWith("`n")){ $norm += "`n" }
  [System.IO.File]::WriteAllText($Path,$norm,$enc)
}
function Sha256HexFile([string]$p){
  $fs = [System.IO.File]::OpenRead($p)
  try{
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try{
      $h = $sha.ComputeHash($fs)
      $sb = New-Object System.Text.StringBuilder
      foreach($b in $h){ [void]$sb.AppendFormat("{0:x2}",$b) }
      $sb.ToString()
    }
    finally{ $sha.Dispose() }
  }
  finally{ $fs.Dispose() }
}
function Get-VerifiedPacketInfo([string]$PacketRoot){
  if(-not (Test-Path -LiteralPath $PacketRoot -PathType Container)){ Die ("PACKET_ROOT_MISSING: " + $PacketRoot) }
  $manPath = Join-Path $PacketRoot "manifest.json"
  $pktIdPath = Join-Path $PacketRoot "packet_id.txt"
  $sumsPath = Join-Path $PacketRoot "sha256sums.txt"
  if(-not (Test-Path -LiteralPath $manPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $manPath) }
  if(-not (Test-Path -LiteralPath $pktIdPath -PathType Leaf)){ Die ("MISSING_PACKET_ID_TXT: " + $pktIdPath) }
  if(-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)){ Die ("MISSING_SHA256SUMS: " + $sumsPath) }
  $leaf = Split-Path -Leaf $PacketRoot
  $pktId = ([System.IO.File]::ReadAllText($pktIdPath,[System.Text.UTF8Encoding]::new($false))).Trim()
  if([string]::IsNullOrWhiteSpace($pktId)){ Die "EMPTY_PACKET_ID_TXT" }
  if([string]$pktId -ne [string]$leaf){ Die ("PACKET_ID_FOLDER_MISMATCH: folder=" + $leaf + " packet_id.txt=" + $pktId) }
  $lines = @([System.IO.File]::ReadAllLines($sumsPath,[System.Text.UTF8Encoding]::new($false)))
  if(@($lines).Count -lt 1){ Die ("EMPTY_SHA256SUMS: " + $sumsPath) }
  foreach($ln in $lines){
    $t = ([string]$ln).Trim()
    if($t -eq ""){ continue }
    if($t.Length -lt 66){ Die ("BAD_SHA256SUMS_LINE: " + $t) }
    $exp = $t.Substring(0,64)
    $rel = $t.Substring(66).Trim()
    $p = Join-Path $PacketRoot $rel
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FROM_SUMS: " + $rel) }
    $got = Sha256HexFile $p
    if([string]$got -ne [string]$exp){ Die ("SHA256_MISMATCH: " + $rel + " exp=" + $exp + " got=" + $got) }
  }
  [pscustomobject]@{ PacketId=$pktId; ManifestSha256=(Sha256HexFile $manPath); Sha256SumsSha256=(Sha256HexFile $sumsPath) }
}
$usb = ($UsbDriveLetter.TrimEnd(":") + ":")
if([string]::IsNullOrWhiteSpace($UsbDriveLetter)){
  $d = @(
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" |
    Where-Object { Test-Path -LiteralPath (Join-Path ([string]$_.DeviceID) "echo_transport\toolbelt\outbox") -PathType Container } |
    Sort-Object @{Expression={$_.DeviceID};Descending=$false} |
    Select-Object -First 1
  )
  if(@($d).Count -lt 1){ Die "NO_TOOLBELT_USB_OUTBOX_DETECTED" }
  $usb = [string]$d[0].DeviceID
}
if(-not (Test-Path -LiteralPath $usb -PathType Container)){ Die ("USB_ROOT_NOT_FOUND: " + $usb) }
$usbOutbox = Join-Path $usb "echo_transport\toolbelt\outbox"
if(-not (Test-Path -LiteralPath $usbOutbox -PathType Container)){ Die ("USB_OUTBOX_NOT_FOUND: " + $usbOutbox) }
$src = Join-Path $usbOutbox $PacketId
if(-not (Test-Path -LiteralPath $src -PathType Container)){ Die ("PACKET_NOT_FOUND_ON_USB: " + $src) }
$srcInfo = Get-VerifiedPacketInfo $src
Write-Host ("[NODE] USB sha256 verify PASS: " + $src) -ForegroundColor Green
Write-Host "[NODE] OptionA PASS: packet_id.txt == folder" -ForegroundColor Green
Ensure-Dir $InboxRoot
$dst = Join-Path $InboxRoot $srcInfo.PacketId
if(Test-Path -LiteralPath $dst){ Remove-Item -LiteralPath $dst -Recurse -Force }
Copy-Item -LiteralPath $src -Destination $InboxRoot -Recurse -Force
$null = Get-VerifiedPacketInfo $dst
Write-Host ("[NODE] Copy+verify PASS: " + $dst) -ForegroundColor Green
$rcpDir = Join-Path $InboxRoot "_receipts"
Ensure-Dir $rcpDir
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp = Join-Path $rcpDir ("assemblelink.ingest_receipt.v1_" + $stamp + ".txt")
$body = @(
  "schema=assemblelink.ingest_receipt.v1"
  ("packet_id=" + $srcInfo.PacketId)
  ("utc=" + (Get-Date).ToUniversalTime().ToString("o"))
  ("usb=" + $usb)
  ("source=" + $src)
  ("destination=" + $dst)
  ("manifest_sha256=" + $srcInfo.ManifestSha256)
  ("sha256sums_sha256=" + $srcInfo.Sha256SumsSha256)
) -join "`n"
Write-Utf8NoBomLf $rcp $body
Write-Host ("[NODE] Wrote receipt: " + $rcp) -ForegroundColor DarkGray
Write-Host ("DONE: ingested packet -> " + $dst) -ForegroundColor Green
