param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="capability status index global"; ok=($raw -match 'capabilityStatusIndex') },
  [pscustomobject]@{ item="status loader"; ok=($raw -match 'loadCapabilityStatusIndex') },
  [pscustomobject]@{ item="status lookup"; ok=($raw -match 'getCapabilityStatus') },
  [pscustomobject]@{ item="mini stats"; ok=($raw -match 'miniStats') },
  [pscustomobject]@{ item="tracked/missing UI"; ok=($raw -match 'tracked' -and $raw -match 'missing') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("CAPABILITY_STATUS_UI_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_CAPABILITY_STATUS_UI_AUDIT_OK" -ForegroundColor Green
