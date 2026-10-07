param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$Css=Join-Path $RepoRoot "ui\src\style.css"
$Panda=Join-Path $RepoRoot "ui\src\panda.js"
foreach($p in @($Ui,$Css,$Panda)){ if(-not(Test-Path -LiteralPath $p -PathType Leaf)){ throw ("UI_FILE_MISSING: "+$p) } }
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8
$css=Get-Content -LiteralPath $Css -Raw -Encoding UTF8
$panda=Get-Content -LiteralPath $Panda -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="reduced motion respected"; ok=($css -match 'prefers-reduced-motion: reduce') },
  [pscustomobject]@{ item="no radar"; ok=($css -notmatch 'radar' -and $raw -notmatch 'radar') },
  [pscustomobject]@{ item="lazy panda poses"; ok=($panda -match '"idle", "scan", "think", "happy", "sad", "carry"' -or $panda -match 'idle.*scan.*think.*happy.*sad.*carry') },
  [pscustomobject]@{ item="text wraps instead of overflowing"; ok=($css -match 'overflow-wrap:anywhere') },
  [pscustomobject]@{ item="slow panda motion only"; ok=($css -match '\.panda\[data-pose="carry"\]') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("CALM_MOTION_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_MISSION_POLISH_V1_AUDIT_OK" -ForegroundColor Green
