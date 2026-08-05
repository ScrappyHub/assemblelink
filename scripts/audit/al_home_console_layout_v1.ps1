param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="overview and setup workspace separated"; ok=($raw -match 'sidebarContext!=="overview"' -and $raw -match 'function renderSetupWorkspace') },
  [pscustomobject]@{ item="quick start before inventory"; ok=($raw.IndexOf('${renderDashboardQuickStart()}') -lt $raw.IndexOf('${renderDashboardInventory()}')) },
  [pscustomobject]@{ item="inventory before job toolkits"; ok=($raw.IndexOf('${renderDashboardInventory()}') -lt $raw.IndexOf('${renderDashboardToolkits()}')) },
  [pscustomobject]@{ item="plain language inventory"; ok=($raw -match 'known tools' -and $raw -match 'updates available' -and $raw -match 'versions to review') },
  [pscustomobject]@{ item="responsive dashboard styles"; ok=((Get-Content (Join-Path $RepoRoot 'ui\src\style.css') -Raw) -match 'quickStartGrid' -and (Get-Content (Join-Path $RepoRoot 'ui\src\style.css') -Raw) -match '@media \(max-width:620px\)') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_CONSOLE_LAYOUT_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_CONSOLE_LAYOUT_AUDIT_OK" -ForegroundColor Green
