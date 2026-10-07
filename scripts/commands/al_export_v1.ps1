param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$ManifestRoot=Join-Path $RepoRoot "manifests\targetclasses"
$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

function EnsureDir([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function WriteUtf8([string]$p,[string]$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $p)
  $u=$t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $u.EndsWith("`n")){ $u+="`n" }
  [IO.File]::WriteAllText($p,$u,$enc)
}
function HasTool([string]$n){
  if($n -eq "tshark" -and (Test-Path "C:\Program Files\Wireshark\tshark.exe")){ return $true }
  return ($null -ne (Get-Command $n -ErrorAction SilentlyContinue))
}
function ToolPath([string]$n){
  if($n -eq "tshark" -and (Test-Path "C:\Program Files\Wireshark\tshark.exe")){ return "C:\Program Files\Wireshark\tshark.exe" }
  try{ return [string](Get-Command $n -ErrorAction Stop).Source }catch{ return "" }
}
function InventoryRows(){
  $tools=@("git","node","npm","python","pip","code","docker","winget","pwsh","nmap","tshark","blender")
  foreach($t in $tools){
    [pscustomobject]@{tool=$t;installed=(HasTool $t);source=(ToolPath $t)}
  }
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$rows=@(InventoryRows)

$profile=[ordered]@{
  schema="assemblelink.workstation_profile.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  repo=$RepoRoot
  targetclasses=@()
  inventory=$rows
}

foreach($f in Get-ChildItem -LiteralPath $ManifestRoot -Filter "*.json"){
  $m=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $profile.targetclasses += [ordered]@{
    targetclass=[string]$m.targetclass
    label=[string]$m.label
  }
}

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("workstation_profile.v1_"+$stamp+".json")
WriteUtf8 $out ($profile|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.export_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.export_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nprofile="+$out+"`n")

Write-Host ("ASSEMBLELINK_EXPORT_PROFILE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_EXPORT_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_EXPORT_OK" -ForegroundColor Green
