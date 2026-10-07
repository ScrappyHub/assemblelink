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
$scenes=Get-Content -LiteralPath (Join-Path $RepoRoot "ui\src\scenes.js") -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="inventory room renderer"; ok=($raw -match 'function renderInventory' -and $raw -match 'roomSvg') },
  [pscustomobject]@{ item="panda prompts"; ok=($raw -match 'data-panda-ask="updates"' -and $raw -match 'data-panda-ask="unknown"') },
  [pscustomobject]@{ item="long scroll with search and filters"; ok=($raw -match 'scrollWrap' -and $raw -match 'id="softwareSearch"' -and $raw -match 'data-inv-filter') },
  [pscustomobject]@{ item="long versions are truncated"; ok=($raw -match 'shortVersion') },
  [pscustomobject]@{ item="room scenery module"; ok=($scenes -match 'export function roomSvg') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("INVENTORY_ROOM_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_MISSION_LIST_V2_AUDIT_OK" -ForegroundColor Green
