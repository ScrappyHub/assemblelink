param(
  [Parameter(Mandatory=$false)][string]$RepoRoot="C:\dev\assemblelink"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$CommandDir=Join-Path $RepoRoot "scripts\commands"
$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WriteUtf8([string]$p,[string]$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  $d=Split-Path -Parent $p
  if($d){ EnsureDir $d }
  $u=$t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $u.EndsWith("`n")){ $u+="`n" }
  [IO.File]::WriteAllText($p,$u,$enc)
}

function ParseGate([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){
    Die ("MODULE_MISSING: "+$p)
  }

  $tok=$null
  $err=$null

  [void][Management.Automation.Language.Parser]::ParseFile(
    $p,
    [ref]$tok,
    [ref]$err
  )

  if($err -and @($err).Count -gt 0){
    Die ("MODULE_PARSE_FAIL: "+$p+" :: "+@($err)[0].Message)
  }

  Write-Host ("MODULE_PARSE_OK: "+$p) -ForegroundColor Green
}

if(-not(Test-Path -LiteralPath $CommandDir -PathType Container)){
  Die ("COMMAND_DIR_MISSING: "+$CommandDir)
}

$ExportModule=Join-Path $CommandDir "al_export_v1.ps1"
$ImportModule=Join-Path $CommandDir "al_import_v1.ps1"
$VersioncheckModule=Join-Path $CommandDir "al_versioncheck_v1.ps1"
$InstallModule=Join-Path $CommandDir "al_install_v1.ps1"

ParseGate $ExportModule
ParseGate $ImportModule
ParseGate $VersioncheckModule
ParseGate $InstallModule

Write-Host "MODULE_RUN: export" -ForegroundColor Cyan
$outExport=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExportModule -RepoRoot $RepoRoot 2>&1
$outExport | Out-Host

if($LASTEXITCODE -ne 0){
  Die ("MODULE_EXPORT_FAILED_EXITCODE="+$LASTEXITCODE)
}

$LatestProfile=Get-ChildItem -LiteralPath $StateDir -Filter "workstation_profile.v1_*.json" |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if($null -eq $LatestProfile){
  Die "MODULE_SELFTEST_NO_EXPORTED_PROFILE"
}

Write-Host "MODULE_RUN: import" -ForegroundColor Cyan
$outImport=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ImportModule -RepoRoot $RepoRoot -ProfilePath $LatestProfile.FullName 2>&1
$outImport | Out-Host

if($LASTEXITCODE -ne 0){
  Die ("MODULE_IMPORT_FAILED_EXITCODE="+$LASTEXITCODE)
}

Write-Host "MODULE_RUN: versioncheck" -ForegroundColor Cyan
$outVersioncheck=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VersioncheckModule -RepoRoot $RepoRoot -TargetClass cybersecurity 2>&1
$outVersioncheck | Out-Host

if($LASTEXITCODE -ne 0){
  Die ("MODULE_VERSIONCHECK_FAILED_EXITCODE="+$LASTEXITCODE)
}

Write-Host "MODULE_RUN: install_dryrun_cybersecurity" -ForegroundColor Cyan
$outInstallCyber=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $InstallModule -RepoRoot $RepoRoot -TargetClass cybersecurity 2>&1
$outInstallCyber | Out-Host

if($LASTEXITCODE -ne 0){
  Die ("MODULE_INSTALL_CYBERSECURITY_FAILED_EXITCODE="+$LASTEXITCODE)
}

Write-Host "MODULE_RUN: install_dryrun_game_design" -ForegroundColor Cyan
$outInstallGame=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $InstallModule -RepoRoot $RepoRoot -TargetClass game-design 2>&1
$outInstallGame | Out-Host

if($LASTEXITCODE -ne 0){
  Die ("MODULE_INSTALL_GAME_DESIGN_FAILED_EXITCODE="+$LASTEXITCODE)
}

EnsureDir $ReceiptDir
$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp=Join-Path $ReceiptDir ("assemblelink.module_selftest_receipt.v1_"+$stamp+".txt")

WriteUtf8 $rcp (
  "schema=assemblelink.module_selftest_receipt.v1`n"+
  "utc="+(Get-Date).ToUniversalTime().ToString("o")+"`n"+
  "export_module="+$ExportModule+"`n"+
  "import_module="+$ImportModule+"`n"+
  "versioncheck_module="+$VersioncheckModule+"`n"+
  "install_module="+$InstallModule+"`n"+
  "profile="+$LatestProfile.FullName+"`n"
)

Write-Host ("ASSEMBLELINK_MODULE_SELFTEST_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_MODULE_SELFTEST_OK" -ForegroundColor Green