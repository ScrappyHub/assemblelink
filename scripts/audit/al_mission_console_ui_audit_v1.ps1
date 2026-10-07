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
  [pscustomobject]@{ item="program uninstall is approval bound"; ok=($raw -match 'invokeDesktop\("uninstall_software",\{catalogId,approved:true\}\)' -and $raw -match 'window\.confirm') },
  [pscustomobject]@{ item="self uninstall is approval bound"; ok=($raw -match 'invokeDesktop\("uninstall_assemblelink",\{approved:true\}\)' -and $raw -match 'id="selfAck"') },
  [pscustomobject]@{ item="uninstall only for catalog entries"; ok=($raw -match 'winget_id' -and $raw -match 'Only tools in the approved catalog') },
  [pscustomobject]@{ item="silent removal explained"; ok=($raw -match 'Removal runs without installer windows') },
  [pscustomobject]@{ item="uninstall page reachable"; ok=($raw -match 'function renderUninstall') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("UNINSTALL_UI_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_MISSION_CONSOLE_UI_AUDIT_OK" -ForegroundColor Green
