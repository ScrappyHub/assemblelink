param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetClass
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

$p=Join-Path $ManifestRoot ($TargetClass+".json")
if(-not(Test-Path -LiteralPath $p -PathType Leaf)){
  throw ("TARGETCLASS_NOT_FOUND: "+$TargetClass)
}

$m=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
if($m.PSObject.Properties.Match("tools").Count -lt 1){
  throw ("TARGETCLASS_MANIFEST_MISSING_TOOLS: "+$p)
}

$rows=@()
foreach($t in @($m.tools)){
  $rows += [pscustomobject]@{
    id=[string]$t.id
    installed=(HasTool ([string]$t.command))
    source=(ToolPath ([string]$t.command))
    install_hint=[string]$t.install_hint
  }
}

$rows | Format-Table -AutoSize

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$state=Join-Path $StateDir ("versioncheck."+ $TargetClass + ".v1_"+$stamp+".json")
WriteUtf8 $state ($rows|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.versioncheck_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.versioncheck_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`ntargetclass="+$TargetClass+"`nstate="+$state+"`n")

Write-Host ("ASSEMBLELINK_VERSIONCHECK_STATE_WRITTEN: "+$state) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_VERSIONCHECK_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_VERSIONCHECK_OK" -ForegroundColor Green
