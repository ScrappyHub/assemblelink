param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketId,
  [Parameter(Mandatory=$false)][string]$InboxRoot = "C:\dev\echo-transport\toolbelt\inbox",
  [Parameter(Mandatory=$false)][string]$StoreRoot = "C:\dev\echo-transport\toolbelt\store"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
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
function Verify-PacketDirectory([string]$Root,[string]$ExpectedPacketId,[string]$Prefix){
  if(-not (Test-Path -LiteralPath $Root -PathType Container)){ Die ($Prefix + "_PACKETDIR_MISSING: " + $Root) }
  $manPath = Join-Path $Root "manifest.json"
  $pktIdPath = Join-Path $Root "packet_id.txt"
  $sumsPath = Join-Path $Root "sha256sums.txt"
  if(-not (Test-Path -LiteralPath $manPath -PathType Leaf)){ Die ($Prefix + "_MISSING_MANIFEST: " + $manPath) }
  if(-not (Test-Path -LiteralPath $pktIdPath -PathType Leaf)){ Die ($Prefix + "_MISSING_PACKET_ID_TXT: " + $pktIdPath) }
  if(-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)){ Die ($Prefix + "_MISSING_SHA256SUMS: " + $sumsPath) }
  $pktIdText = ([System.IO.File]::ReadAllText($pktIdPath,[System.Text.UTF8Encoding]::new($false))).Trim()
  if([string]::IsNullOrWhiteSpace($pktIdText)){ Die ($Prefix + "_EMPTY_PACKET_ID_TXT") }
  $leaf = Split-Path -Leaf $Root
  if([string]$pktIdText -ne [string]$leaf){ Die ($Prefix + "_PACKET_ID_FOLDER_MISMATCH: folder=" + $leaf + " packet_id.txt=" + $pktIdText) }
  if([string]$pktIdText -ne [string]$ExpectedPacketId){ Die ($Prefix + "_PACKET_ID_EXPECTED_MISMATCH: expected=" + $ExpectedPacketId + " got=" + $pktIdText) }
  $lines = @([System.IO.File]::ReadAllLines($sumsPath,[System.Text.UTF8Encoding]::new($false)))
  if(@($lines).Count -lt 1){ Die ($Prefix + "_EMPTY_SHA256SUMS: " + $sumsPath) }
  foreach($ln in $lines){
    $t = ([string]$ln).Trim()
    if($t -eq ""){ continue }
    if($t.Length -lt 66){ Die ($Prefix + "_BAD_SHA256SUMS_LINE: " + $t) }
    $exp = $t.Substring(0,64)
    $rel = $t.Substring(66).Trim()
    $p = Join-Path $Root $rel
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ($Prefix + "_MISSING_FROM_SUMS: " + $rel) }
    $got = Sha256HexFile $p
    if([string]$got -ne [string]$exp){ Die ($Prefix + "_SHA256_MISMATCH: " + $rel + " exp=" + $exp + " got=" + $got) }
  }
  return [pscustomobject]@{
    PacketId = $pktIdText
    ManifestSha256 = (Sha256HexFile $manPath)
    Sha256SumsSha256 = (Sha256HexFile $sumsPath)
    Root = $Root
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPOROOT: " + $RepoRoot) }
Ensure-Dir $InboxRoot
Ensure-Dir $StoreRoot

$srcDir = Join-Path $InboxRoot $PacketId
$dstDir = Join-Path $StoreRoot $PacketId

$srcInfo = Verify-PacketDirectory -Root $srcDir -ExpectedPacketId $PacketId -Prefix "SRC"
Write-Host ("[DEV] SOURCE VERIFY PASS: " + $srcDir) -ForegroundColor Green

if(Test-Path -LiteralPath $dstDir){ Remove-Item -LiteralPath $dstDir -Recurse -Force }
Copy-Item -LiteralPath $srcDir -Destination $StoreRoot -Recurse -Force
if(-not (Test-Path -LiteralPath $dstDir -PathType Container)){ Die ("DST_PACKETDIR_MISSING: " + $dstDir) }

$dstInfo = Verify-PacketDirectory -Root $dstDir -ExpectedPacketId $PacketId -Prefix "DST"
Write-Host ("[DEV] STORE VERIFY PASS: " + $dstDir) -ForegroundColor Green

$rcpDir = Join-Path $StoreRoot "_receipts"
Ensure-Dir $rcpDir
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp = Join-Path $rcpDir ("dev.toolbelt.localize_receipt.v1_" + $stamp + ".txt")
$body = @(
  "schema=dev.toolbelt.localize_receipt.v1"
  ("packet_id=" + $PacketId)
  ("utc=" + (Get-Date).ToUniversalTime().ToString("o"))
  ("source=" + $srcDir)
  ("destination=" + $dstDir)
  ("source_manifest_sha256=" + $srcInfo.ManifestSha256)
  ("source_sha256sums_sha256=" + $srcInfo.Sha256SumsSha256)
  ("destination_manifest_sha256=" + $dstInfo.ManifestSha256)
  ("destination_sha256sums_sha256=" + $dstInfo.Sha256SumsSha256)
) -join "`n"
Write-Utf8NoBomLf $rcp $body
Write-Host ("[DEV] RECEIPT: " + $rcp) -ForegroundColor DarkGray
Write-Host ("CLEAR_OK_DEV_LOCALIZED: packet_id=" + $PacketId + " store=" + $dstDir + " receipt=" + $rcp) -ForegroundColor Green
