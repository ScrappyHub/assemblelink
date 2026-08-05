param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="popular toolkit renderer"; ok=($raw -match 'function renderDashboardToolkits') },
  [pscustomobject]@{ item="six job starters"; ok=($raw -match 'developer-essentials' -and $raw -match 'cloud-infrastructure' -and $raw -match 'cybersecurity' -and $raw -match 'local-ai' -and $raw -match 'game-development' -and $raw -match 'content-creation') },
  [pscustomobject]@{ item="toolkit choice action"; ok=($raw -match 'data-quick-toolkit') },
  [pscustomobject]@{ item="toolkit action opens setup"; ok=($raw -match 'Toolkit selected\. Review the included tools') },
  [pscustomobject]@{ item="all toolkit path visible"; ok=($raw -match 'See all \$\{all\.length\} toolkits') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_CAPABILITY_VISIBILITY_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_CAPABILITY_VISIBILITY_AUDIT_OK" -ForegroundColor Green
