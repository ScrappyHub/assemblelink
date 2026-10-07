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
  [pscustomobject]@{ item="toolkit gallery renderer"; ok=($raw -match 'function renderToolkits') },
  [pscustomobject]@{ item="job family filter"; ok=($raw -match 'data-kit-family' -and $raw -match 'job_family') },
  [pscustomobject]@{ item="toolkit start action"; ok=($raw -match 'Start with this' -and $raw -match 'startWizard') },
  [pscustomobject]@{ item="toolkit gallery has its own layout"; ok=($css -match '\.kitGrid' -and $css -match '\.kitCard') },
  [pscustomobject]@{ item="every tool visible per toolkit"; ok=($raw -match 'See the \$\{p\.total\} tools') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_CAPABILITY_VISIBILITY_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_CAPABILITY_VISIBILITY_AUDIT_OK" -ForegroundColor Green
