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
  [pscustomobject]@{ item="toolkit handoff"; ok=($raw -match 'data-kit-start') },
  [pscustomobject]@{ item="content-hashed setup flow"; ok=($raw -match 'build_setup_plan' -and $raw -match 'execute_setup') },
  [pscustomobject]@{ item="machine type and allocation planner"; ok=($raw -match 'data-machine-type="desktop"' -and $raw -match 'data-machine-type="laptop"' -and $raw -match 'maxAllocationGib') },
  [pscustomobject]@{ item="allocation limitations visible"; ok=($raw -match 'Planning estimate only' -and $raw -match 'virtual machines' -and $raw -match 'AI models') },
  [pscustomobject]@{ item="legacy install IPC absent"; ok=($raw -notmatch 'invokeDesktop\("(prepare_install|execute_install)') },
  [pscustomobject]@{ item="human status mapper"; ok=($raw -match 'function humanStatus') },
  [pscustomobject]@{ item="live setup result renderer"; ok=($raw -match 'function renderInstallStep') },
  [pscustomobject]@{ item="live progress renderer"; ok=($raw -match 'carryTrack' -and $raw -match 'get_setup_progress') },
  [pscustomobject]@{ item="interrupted setup recovery"; ok=($raw -match 'get_setup_recovery' -and $raw -match 'resume_setup') },
  [pscustomobject]@{ item="approved catalog browse handoff"; ok=($raw -match 'function renderCatalog' -and $raw -match 'id="addToSetup"') },
  [pscustomobject]@{ item="false custom save removed"; ok=($raw -notmatch 'saveCustomSoftware|CLI save wiring comes next') },
  [pscustomobject]@{ item="legacy snapshot queues removed"; ok=($raw -notmatch 'install_queue\\.|function renderInstallQueue|function renderInstallPlan') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("UI_PRODUCT_GAP_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_UI_PRODUCT_GAP_AUDIT_OK" -ForegroundColor Green
