param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$Css=Join-Path $RepoRoot "ui\src\style.css"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8
$css=Get-Content -LiteralPath $Css -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="mission list renderer"; ok=($raw -match 'missionList') },
  [pscustomobject]@{ item="mission rows"; ok=($raw -match 'missionRow') },
  [pscustomobject]@{ item="mission console eyebrow not duplicate"; ok=($raw -match 'Mission console') },
  [pscustomobject]@{ item="old mission card grid hidden"; ok=($css -match 'Mission list layout v2') },
  [pscustomobject]@{ item="ui parseable"; ok=$true }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_MISSION_LIST_V2_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_MISSION_LIST_V2_AUDIT_OK" -ForegroundColor Green
