param(
  [Parameter(Mandatory=$false)][string]$PacketId = "",
  [Parameter(Mandatory=$false)][string]$InboxRoot = "C:\dev\assemblelink\toolbelt\inbox",
  [Parameter(Mandatory=$false)][string]$ProofRoot = "C:\dev\assemblelink\proofs\receipts\vader_toolbelt_ingest_seal_v1"
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
  [pscustomobject]@{
    PacketId       = $pktId
    PacketRoot     = $PacketRoot
    ManifestPath   = $manPath
    PacketIdPath   = $pktIdPath
    Sha256SumsPath = $sumsPath
    ManifestSha256 = (Sha256HexFile $manPath)
    Sha256SumsSha256 = (Sha256HexFile $sumsPath)
    PacketIdTxtSha256 = (Sha256HexFile $pktIdPath)
  }
}
if(-not (Test-Path -LiteralPath $InboxRoot -PathType Container)){ Die ("INBOX_ROOT_MISSING: " + $InboxRoot) }
$resolvedPacketId = $null
if(-not [string]::IsNullOrWhiteSpace($PacketId)){
  $resolvedPacketId = $PacketId.Trim()
} else {
  $dirs = @(Get-ChildItem -LiteralPath $InboxRoot -Force | Where-Object { $_.PSIsContainer -and $_.Name -ne "_receipts" })
  if(@($dirs).Count -lt 1){ Die ("INBOX_EMPTY: " + $InboxRoot) }
  $ordered = @($dirs | Sort-Object @{Expression={$_.LastWriteTimeUtc};Descending=$true}, @{Expression={$_.Name};Descending=$false})
  $resolvedPacketId = [string]$ordered[0].Name
}
if([string]::IsNullOrWhiteSpace($resolvedPacketId)){ Die "PACKETID_RESOLVE_FAILED" }
$pkt = Join-Path $InboxRoot $resolvedPacketId
$info = Get-VerifiedPacketInfo $pkt
Write-Host ("[NODE] INBOX sha256 verify PASS: " + $pkt) -ForegroundColor Green
Write-Host "[NODE] OptionA PASS: packet_id.txt == folder" -ForegroundColor Green
Ensure-Dir $ProofRoot
$outDir = Join-Path $ProofRoot ((Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss"))
Ensure-Dir $outDir
$seal = Join-Path $outDir "seal_receipt.txt"
$hostName = $env:COMPUTERNAME
$utc = (Get-Date).ToUniversalTime().ToString("o")
$body = @(
  "schema=assemblelink.ingest_seal.v1"
  ("packet_id=" + $info.PacketId)
  ("utc=" + $utc)
  ("host=" + $hostName)
  ("inbox_packet_dir=" + $pkt)
  ("manifest_sha256=" + $info.ManifestSha256)
  ("sha256sums_sha256=" + $info.Sha256SumsSha256)
  ("packet_id_txt_sha256=" + $info.PacketIdTxtSha256)
) -join "`n"
Write-Utf8NoBomLf $seal $body
Write-Host ("[NODE] SEALED: " + $outDir) -ForegroundColor Green
Write-Host ("CLEAR_OK_VADER_SEALED: packet_id=" + $info.PacketId + " seal_dir=" + $outDir + " seal_receipt=" + $seal) -ForegroundColor Green
