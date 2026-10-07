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
  [pscustomobject]@{ item="get-started splash"; ok=($raw -match 'function renderHome' -and $raw -match 'id="getStarted"') },
  [pscustomobject]@{ item="new and returning welcome"; ok=($raw -match 'Welcome to AssembleLink' -and $raw -match 'Welcome back') },
  [pscustomobject]@{ item="click-through wizard with back and next"; ok=($raw -match 'function renderWizard' -and $raw -match 'id="wizNext"' -and $raw -match 'id="wizBack"') },
  [pscustomobject]@{ item="four named steps"; ok=($raw -match 'Your computer' -and $raw -match 'Pick tools' -and $raw -match 'Review' -and $raw -match 'Install') },
  [pscustomobject]@{ item="direct inventory shortcut"; ok=($raw -match 'data-go="inventory"') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_ACTION_CONSOLE_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_ACTION_CONSOLE_AUDIT_OK" -ForegroundColor Green
