param(
  [Parameter(Mandatory=$false)][string]$RepoRoot="C:\dev\assemblelink"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Registry=Join-Path $RepoRoot "manifests\applications\app_registry.v1.json"
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
function FindFirstPath([object[]]$patterns){
  foreach($pat in @($patterns)){
    $expanded=[Environment]::ExpandEnvironmentVariables([string]$pat)
    $hits=@(Get-ChildItem -Path $expanded -ErrorAction SilentlyContinue | Select-Object -First 1)
    if(@($hits).Count -gt 0){ return [string]$hits[0].FullName }
  }
  return ""
}
function FindCommand([object[]]$commands){
  foreach($cmd in @($commands)){
    $hit=Get-Command ([string]$cmd) -ErrorAction SilentlyContinue
    if($null -ne $hit){ return [string]$hit.Source }
  }
  return ""
}

if(-not(Test-Path -LiteralPath $Registry -PathType Leaf)){
  throw ("APP_REGISTRY_MISSING: "+$Registry)
}

$r=Get-Content -LiteralPath $Registry -Raw -Encoding UTF8 | ConvertFrom-Json
if($r.PSObject.Properties.Match("applications").Count -lt 1){
  throw "APP_REGISTRY_MISSING_APPLICATIONS"
}

$rows=@()

foreach($app in @($r.applications)){
  $path=FindFirstPath @($app.detection_paths)
  $cmd=FindCommand @($app.commands)
  $source=$(if(-not [string]::IsNullOrWhiteSpace($path)){$path}else{$cmd})
  $installed=(-not [string]::IsNullOrWhiteSpace($source))

  $rows += [pscustomobject]@{
    id=[string]$app.id
    name=[string]$app.name
    vendor=[string]$app.vendor
    installed=$installed
    source=$source
    license_gate=[string]$app.license_gate
    account_required=[bool]$app.account_required
    winget_id=[string]$app.winget_id
    official_source=[string]$app.official_source
  }
}

$rows | Format-Table -AutoSize

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$state=Join-Path $StateDir ("application_scan.v1_"+$stamp+".json")
WriteUtf8 $state ($rows|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.application_scan_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp (
  "schema=assemblelink.application_scan_receipt.v1`n"+
  "utc="+(Get-Date).ToUniversalTime().ToString("o")+"`n"+
  "registry="+$Registry+"`n"+
  "state="+$state+"`n"
)

Write-Host ("ASSEMBLELINK_APP_SCAN_STATE: "+$state) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_APP_SCAN_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_APP_REGISTRY_SCAN_OK" -ForegroundColor Green
