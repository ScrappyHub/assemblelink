param(
  [Parameter(Mandatory=$false)][string]$PacketId = "",
  [Parameter(Mandatory=$false)][string]$UsbDriveLetter = "",
  [Parameter(Mandatory=$false)][string]$InboxRoot = "C:\dev\echo-transport\toolbelt\inbox"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $norm = $Text -replace "`r`n","`n" -replace "`r","`n"
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
      foreach($b in $h){
        [void]$sb.AppendFormat("{0:x2}",$b)
      }
      $sb.ToString()
    }
    finally{
      $sha.Dispose()
    }
  }
  finally{
    $fs.Dispose()
  }
}

function Get-VerifiedPacketInfo([string]$PacketRoot){
  if(-not (Test-Path -LiteralPath $PacketRoot -PathType Container)){
    Die ("PACKET_ROOT_MISSING: " + $PacketRoot)
  }

  $manPath = Join-Path $PacketRoot "manifest.json"
  $packetIdPath = Join-Path $PacketRoot "packet_id.txt"
  $sumsPath = Join-Path $PacketRoot "sha256sums.txt"

  if(-not (Test-Path -LiteralPath $manPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $manPath) }
  if(-not (Test-Path -LiteralPath $packetIdPath -PathType Leaf)){ Die ("MISSING_PACKET_ID_TXT: " + $packetIdPath) }
  if(-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)){ Die ("MISSING_SHA256SUMS: " + $sumsPath) }

  $folderLeaf = Split-Path -Leaf $PacketRoot
  $packetIdFromFile = ([System.IO.File]::ReadAllText($packetIdPath,[System.Text.UTF8Encoding]::new($false))).Trim()
  if([string]::IsNullOrWhiteSpace($packetIdFromFile)){ Die "EMPTY_PACKET_ID_TXT" }
  if([string]$packetIdFromFile -ne [string]$folderLeaf){
    Die ("PACKET_ID_FOLDER_MISMATCH: folder=" + $folderLeaf + " packet_id.txt=" + $packetIdFromFile)
  }

  $manifestObj = Get-Content -LiteralPath $manPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($null -eq $manifestObj){ Die ("MANIFEST_PARSE_FAILED: " + $manPath) }
  if($manifestObj.PSObject.Properties.Match("packet_id").Count -gt 0){
    $manifestPacketId = [string]$manifestObj.packet_id
    if(-not [string]::IsNullOrWhiteSpace($manifestPacketId)){
      if([string]$manifestPacketId -ne [string]$packetIdFromFile){
        Die ("MANIFEST_PACKET_ID_MISMATCH: file=" + $packetIdFromFile + " manifest=" + $manifestPacketId)
      }
    }
  }

  $lines = @([System.IO.File]::ReadAllLines($sumsPath,[System.Text.UTF8Encoding]::new($false)))
  if(@($lines).Count -lt 1){ Die ("EMPTY_SHA256SUMS: " + $sumsPath) }

  foreach($ln in $lines){
    $t = ([string]$ln).Trim()
    if($t -eq ""){ continue }
    if($t.Length -lt 66){ Die ("BAD_SHA256SUMS_LINE: " + $t) }

    $exp = $t.Substring(0,64)
    $rel = $t.Substring(66).Trim()
    $p   = Join-Path $PacketRoot $rel

    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
      Die ("MISSING_FROM_SUMS: " + $rel)
    }

    $got = Sha256HexFile $p
    if([string]$got -ne [string]$exp){
      Die ("SHA256_MISMATCH: " + $rel + " exp=" + $exp + " got=" + $got)
    }
  }

  [pscustomobject]@{
    PacketRoot         = $PacketRoot
    PacketId           = $packetIdFromFile
    ManifestPath       = $manPath
    PacketIdPath       = $packetIdPath
    Sha256SumsPath     = $sumsPath
    ManifestSha256     = (Sha256HexFile $manPath)
    Sha256SumsSha256   = (Sha256HexFile $sumsPath)
  }
}

# 1) Resolve USB
$usb = ($UsbDriveLetter.TrimEnd(":") + ":")
if([string]::IsNullOrWhiteSpace($UsbDriveLetter)){
  $candidates = @(
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" |
    ForEach-Object {
      $root = [string]$_.DeviceID
      $outbox = Join-Path $root "echo_transport\toolbelt\outbox"
      $dirs = @()
      if(Test-Path -LiteralPath $outbox -PathType Container){
        $dirs = @(Get-ChildItem -LiteralPath $outbox -Force | Where-Object { $_.PSIsContainer })
      }
      [pscustomobject]@{
        DeviceID = $root
        Outbox   = $outbox
        DirCount = @($dirs).Count
      }
    } |
    Where-Object { (Test-Path -LiteralPath $_.Outbox -PathType Container) -and $_.DirCount -ge 1 } |
    Sort-Object @{Expression={$_.DeviceID};Descending=$false}
  )

  if(@($candidates).Count -lt 1){
    Die "NO_TOOLBELT_USB_OUTBOX_DETECTED"
  }

  $usb = [string]$candidates[0].DeviceID
}

if(-not (Test-Path -LiteralPath $usb -PathType Container)){ Die ("USB_ROOT_NOT_FOUND: " + $usb) }

$usbOutbox = Join-Path $usb "echo_transport\toolbelt\outbox"
if(-not (Test-Path -LiteralPath $usbOutbox -PathType Container)){ Die ("USB_OUTBOX_NOT_FOUND: " + $usbOutbox) }

# 2) Resolve packet id
$resolvedPacketId = $null
if(-not [string]::IsNullOrWhiteSpace($PacketId)){
  $resolvedPacketId = $PacketId.Trim()
} else {
  $dirs = @(Get-ChildItem -LiteralPath $usbOutbox -Force | Where-Object { $_.PSIsContainer })
  if(@($dirs).Count -lt 1){ Die ("USB_OUTBOX_EMPTY: " + $usbOutbox) }

  $ordered = @(
    $dirs | Sort-Object `
      @{Expression={$_.LastWriteTimeUtc};Descending=$true}, `
      @{Expression={$_.Name};Descending=$false}
  )

  $resolvedPacketId = [string]$ordered[0].Name
}

if([string]::IsNullOrWhiteSpace($resolvedPacketId)){ Die "PACKET_ID_RESOLVE_FAILED" }

Write-Host ("[DEV] Using USB=" + $usb + " packet_id=" + $resolvedPacketId) -ForegroundColor Cyan

# 3) Verify source
$srcDir = Join-Path $usbOutbox $resolvedPacketId
$srcInfo = Get-VerifiedPacketInfo $srcDir
Write-Host ("[DEV] SOURCE VERIFY PASS: " + $srcDir) -ForegroundColor Green

# 4) Copy to inbox
Ensure-Dir $InboxRoot
$dstDir = Join-Path $InboxRoot $resolvedPacketId
if(Test-Path -LiteralPath $dstDir){
  Remove-Item -LiteralPath $dstDir -Recurse -Force
}
Copy-Item -LiteralPath $srcDir -Destination $InboxRoot -Recurse -Force

if(-not (Test-Path -LiteralPath $dstDir -PathType Container)){
  Die ("DST_PACKETDIR_MISSING: " + $dstDir)
}

# 5) Verify destination
$dstInfo = Get-VerifiedPacketInfo $dstDir
Write-Host ("[DEV] DEST VERIFY PASS: " + $dstDir) -ForegroundColor Green

# 6) Receipt
$rcpDir = Join-Path $InboxRoot "_receipts"
Ensure-Dir $rcpDir
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp   = Join-Path $rcpDir ("dev.toolbelt.ingest_receipt.v3_" + $stamp + ".txt")

$body = @(
  "schema=dev.toolbelt.ingest_receipt.v3"
  ("packet_id=" + $resolvedPacketId)
  ("utc=" + (Get-Date).ToUniversalTime().ToString("o"))
  ("usb=" + $usb)
  ("source=" + $srcDir)
  ("destination=" + $dstDir)
  ("source_manifest_sha256=" + $srcInfo.ManifestSha256)
  ("source_sha256sums_sha256=" + $srcInfo.Sha256SumsSha256)
  ("destination_manifest_sha256=" + $dstInfo.ManifestSha256)
  ("destination_sha256sums_sha256=" + $dstInfo.Sha256SumsSha256)
) -join "`n"

Write-Utf8NoBomLf $rcp $body
Write-Host ("[DEV] RECEIPT: " + $rcp) -ForegroundColor DarkGray
Write-Host ("CLEAR_OK_DEV_GREEN: packet_id=" + $resolvedPacketId + " dst=" + $dstDir + " receipt=" + $rcp) -ForegroundColor Green
