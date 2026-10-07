# One command: build the installer and stage an UNSIGNED-DEVELOPMENT release candidate.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\release\build_candidate_v1.ps1
param([string]$RepoRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Set-Location $RepoRoot
$tauri=Get-Content -LiteralPath 'ui\src-tauri\tauri.conf.json' -Raw|ConvertFrom-Json
$Version=[string]$tauri.version
Write-Host "== AssembleLink ${Version}: build ==" -ForegroundColor Cyan
Push-Location ui
try{ npm ci; if($LASTEXITCODE -ne 0){throw 'NPM_CI_FAILED'}; npx tauri build; if($LASTEXITCODE -ne 0){throw 'TAURI_BUILD_FAILED'} } finally { Pop-Location }
$exe=Join-Path $RepoRoot "ui\src-tauri\target\release\bundle\nsis\AssembleLink_${Version}_x64-setup.exe"
if(-not(Test-Path -LiteralPath $exe)){throw "INSTALLER_NOT_FOUND: $exe"}
$h=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$exe.sha256","$h  $(Split-Path $exe -Leaf)`n",(New-Object Text.UTF8Encoding($false)))
Write-Host '== clean-machine matrix status ==' -ForegroundColor Cyan
& (Join-Path $RepoRoot 'scripts\audit\al_clean_machine_matrix_audit_v1.ps1') -RepoRoot $RepoRoot | Out-Null
Write-Host '== stage (unsigned development candidate) ==' -ForegroundColor Cyan
& (Join-Path $RepoRoot 'scripts\release\stage_release_v1.ps1') -RepoRoot $RepoRoot -Version $Version -InstallerPath $exe -AllowUnsignedDevelopmentCandidate
$out=Join-Path $RepoRoot "release\out\v$Version"
Write-Host "`nSTAGED: $out" -ForegroundColor Green
Get-ChildItem -LiteralPath $out | Format-Table Name,Length -AutoSize
