param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="mission console global"; ok=($raw -match 'missionConsole') },
  [pscustomobject]@{ item="mission console loader"; ok=($raw -match 'loadMissionConsole') },
  [pscustomobject]@{ item="mission renderer"; ok=($raw -match 'renderMissionConsole') },
  [pscustomobject]@{ item="blueprint readiness renderer"; ok=($raw -match 'renderBlueprintReadiness') },
  [pscustomobject]@{ item="value strip renderer"; ok=($raw -match 'renderWorkstationValueStrip') },
  [pscustomobject]@{ item="old capability start hidden"; ok=($raw -match 'capabilityStart" style="display:none"') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("MISSION_CONSOLE_UI_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_MISSION_CONSOLE_UI_AUDIT_OK" -ForegroundColor Green
