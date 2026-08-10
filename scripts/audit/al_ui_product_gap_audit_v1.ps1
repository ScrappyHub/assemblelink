param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"

if(-not(Test-Path $Ui -PathType Leaf)){ throw "UI_MAIN_MISSING" }

$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8

$checks=@(
  [pscustomobject]@{ item="Configure Approved Toolkit primary action"; ok=($raw -match 'Configure Approved Toolkit') },
  [pscustomobject]@{ item="job toolkit handoff"; ok=($raw -match 'data-install-recommended' -and $raw -match 'toolkitByCapability') },
  [pscustomobject]@{ item="content-hashed setup flow"; ok=($raw -match 'build_setup_plan' -and $raw -match 'execute_setup') },
  [pscustomobject]@{ item="machine type and allocation planner"; ok=($raw -match 'data-machine-type="desktop"' -and $raw -match 'data-machine-type="laptop"' -and $raw -match 'maxAllocationGib') },
  [pscustomobject]@{ item="allocation limitations visible"; ok=($raw -match 'Planning estimate only' -and $raw -match 'virtual machines' -and $raw -match 'AI models') },
  [pscustomobject]@{ item="legacy install IPC absent"; ok=($raw -notmatch 'invokeDesktop\("(prepare_install|execute_install)') },
  [pscustomobject]@{ item="human status mapper"; ok=($raw -match 'function humanStatus') },
  [pscustomobject]@{ item="live setup result renderer"; ok=($raw -match 'function renderSetupResult') },
  [pscustomobject]@{ item="live progress renderer"; ok=($raw -match 'function renderSetupProgress') },
  [pscustomobject]@{ item="interrupted setup recovery"; ok=($raw -match 'get_setup_recovery' -and $raw -match 'resume_setup') },
  [pscustomobject]@{ item="approved catalog browse handoff"; ok=($raw -match 'Browse Approved Software' -and $raw -match 'data-browse-approved') },
  [pscustomobject]@{ item="false custom save removed"; ok=($raw -notmatch 'saveCustomSoftware|CLI save wiring comes next') },
  [pscustomobject]@{ item="legacy snapshot queues removed"; ok=($raw -notmatch 'install_queue\\.|function renderInstallQueue|function renderInstallPlan') }
)

foreach($c in $checks){
  if(-not $c.ok){ throw ("UI_PRODUCT_GAP_CHECK_FAIL: "+$c.item) }
}

$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_UI_PRODUCT_GAP_AUDIT_OK" -ForegroundColor Green
