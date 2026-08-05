param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$Css=Join-Path $RepoRoot "ui\src\style.css"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8
$css=Get-Content -LiteralPath $Css -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="mission title simplified"; ok=($raw -match 'Workstation missions') },
  [pscustomobject]@{ item="mission impact hidden class"; ok=($raw -match 'missionImpact') },
  [pscustomobject]@{ item="mission next class"; ok=($raw -match 'missionNext') },
  [pscustomobject]@{ item="blueprint collapsed"; ok=($raw -match '<details class="panel blueprintPanel">') },
  [pscustomobject]@{ item="recommended collapsed"; ok=($raw -match '<details class="panel recommendedNow">') },
  [pscustomobject]@{ item="compact mission css"; ok=($css -match 'Mission Console polish') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_MISSION_POLISH_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_MISSION_POLISH_AUDIT_OK" -ForegroundColor Green
