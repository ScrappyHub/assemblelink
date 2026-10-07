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
  [pscustomobject]@{ item="job readiness renderer"; ok=($raw -match 'function renderReadiness') },
  [pscustomobject]@{ item="toolkit progress from live inventory"; ok=($raw -match 'function kitProgress' -and $raw -match 'installedByCatalog') },
  [pscustomobject]@{ item="progress ring"; ok=($raw -match 'function ring' -and $css -match '\.ring \{') },
  [pscustomobject]@{ item="complete-this-toolkit action"; ok=($raw -match 'Complete this toolkit' -and $raw -match 'data-kit-start') },
  [pscustomobject]@{ item="grouped by readiness"; ok=($raw -match 'Almost there' -and $raw -match 'Getting started' -and $raw -match 'Not started') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("CAPABILITY_STATUS_UI_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_CAPABILITY_STATUS_UI_AUDIT_OK" -ForegroundColor Green
