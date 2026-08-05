param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetClass,
  [switch]$Apply
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
  $installed=HasTool ([string]$t.command)
  $rows += [pscustomobject]@{
    id=[string]$t.id
    name=[string]$t.name
    command=[string]$t.command
    installed=$installed
    source=(ToolPath ([string]$t.command))
    action=$(if($installed){"already_present"}else{"plan_install"})
    install_hint=[string]$t.install_hint
  }
}

Write-Host "ASSEMBLELINK_INSTALL_PLAN_READY" -ForegroundColor Green
$rows | Format-Table -AutoSize

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$state=Join-Path $StateDir ("install_plan."+ $TargetClass + ".v1_"+$stamp+".json")
WriteUtf8 $state ($rows|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.install_plan_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.install_plan_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`ntargetclass="+$TargetClass+"`nstate="+$state+"`napply="+[string]$Apply+"`n")

Write-Host ("ASSEMBLELINK_INSTALL_PLAN_STATE: "+$state) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_INSTALL_PLAN_RECEIPT: "+$rcp) -ForegroundColor DarkGray

if(-not $Apply){
  Write-Host "ASSEMBLELINK_INSTALL_DRY_RUN_ONLY" -ForegroundColor Yellow
  return
}

$toInstall=@($rows | Where-Object { $_.action -eq "plan_install" })

if(@($toInstall).Count -lt 1){
  Write-Host "ASSEMBLELINK_APPLY_NOTHING_TO_INSTALL" -ForegroundColor Green
  Write-Host "ASSEMBLELINK_APPLY_OK" -ForegroundColor Green
  return
}

foreach($r in $toInstall){
  $hint=[string]$r.install_hint

  if([string]::IsNullOrWhiteSpace($hint)){
    throw ("INSTALL_HINT_EMPTY: "+$r.id)
  }

  if($hint -notlike "winget install *"){
    throw ("INSTALL_HINT_NOT_ALLOWED: "+$r.id+" hint="+$hint)
  }

  $cmd=$hint+" --accept-package-agreements --accept-source-agreements"

  Write-Host ("ASSEMBLELINK_APPLY_INSTALL_START: "+$r.id+" :: "+$cmd) -ForegroundColor Cyan
  cmd.exe /c $cmd

  if($LASTEXITCODE -ne 0){
    throw ("ASSEMBLELINK_APPLY_INSTALL_FAILED: "+$r.id+" exit="+$LASTEXITCODE)
  }

  Write-Host ("ASSEMBLELINK_APPLY_INSTALL_OK: "+$r.id) -ForegroundColor Green
}

Write-Host "ASSEMBLELINK_APPLY_OK" -ForegroundColor Green
