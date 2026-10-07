param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="setup-first quick start"; ok=($raw -match 'function renderDashboardQuickStart' -and $raw -match 'Set up this computer') },
  [pscustomobject]@{ item="software inventory overview"; ok=($raw -match 'function renderDashboardInventory' -and $raw -match 'Your software at a glance') },
  [pscustomobject]@{ item="machine summary"; ok=($raw -match 'function renderDashboardMachine') },
  [pscustomobject]@{ item="download by job"; ok=($raw -match 'function renderDashboardToolkits' -and $raw -match 'Popular workstation setups') },
  [pscustomobject]@{ item="direct setup navigation"; ok=($raw -match 'data-setup-jump="setup"' -and $raw -match 'data-setup-jump="browse"' -and $raw -match 'data-setup-jump="update"') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_ACTION_CONSOLE_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_ACTION_CONSOLE_AUDIT_OK" -ForegroundColor Green
