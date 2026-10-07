param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$State=Join-Path $RepoRoot "state"
$Public=Join-Path $RepoRoot "ui\public\state"
$Console=Join-Path $State "mission_console.latest.json"
$PublicConsole=Join-Path $Public "mission_console.latest.json"

if(-not(Test-Path -LiteralPath $Console -PathType Leaf)){ throw "MISSION_CONSOLE_MISSING" }
if(-not(Test-Path -LiteralPath $PublicConsole -PathType Leaf)){ throw "PUBLIC_MISSION_CONSOLE_MISSING" }

$j=Get-Content -LiteralPath $Console -Raw -Encoding UTF8 | ConvertFrom-Json
if([string]$j.schema -ne "assemblelink.mission_console.v1"){ throw "MISSION_CONSOLE_SCHEMA_INVALID" }
if(@($j.missions).Count -lt 6){ throw "MISSION_COUNT_TOO_SMALL" }

foreach($m in @($j.missions)){
  $p=Join-Path $State ("mission."+[string]$m.mission_id+".latest.json")
  $pp=Join-Path $Public ("mission."+[string]$m.mission_id+".latest.json")
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){ throw "MISSION_FILE_MISSING: "+[string]$m.mission_id }
  if(-not(Test-Path -LiteralPath $pp -PathType Leaf)){ throw "PUBLIC_MISSION_FILE_MISSING: "+[string]$m.mission_id }
}

$j.missions | Sort-Object completion_percent | Format-Table title,status,completion_percent,next_action -AutoSize
Write-Host "ASSEMBLELINK_MISSION_CONSOLE_AUDIT_OK" -ForegroundColor Green
