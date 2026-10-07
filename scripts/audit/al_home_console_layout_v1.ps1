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
  [pscustomobject]@{ item="top menu bar"; ok=($raw -match 'role="menubar"' -and $raw -match 'function renderMenuBar') },
  [pscustomobject]@{ item="File Logs Drivers Help menus"; ok=($raw -match 'label:"File"' -and $raw -match 'label:"Logs"' -and $raw -match 'label:"Drivers"' -and $raw -match 'label:"Help"') },
  [pscustomobject]@{ item="menus close on Escape"; ok=($raw -match 'e\.key==="Escape"') },
  [pscustomobject]@{ item="uninstall lives in Help"; ok=($raw -match '"go","uninstall","Uninstall') },
  [pscustomobject]@{ item="responsive layout"; ok=($css -match '@media \(max-width:820px\)' -and $css -match '\.wizNav') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("HOME_CONSOLE_LAYOUT_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_HOME_CONSOLE_LAYOUT_AUDIT_OK" -ForegroundColor Green
