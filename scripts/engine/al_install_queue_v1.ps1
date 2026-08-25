param(
  [string]$RepoRoot="C:\dev\assemblelink",
  [Parameter(Mandatory=$true)][string]$CapabilityId
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$CatalogPath=Join-Path $RepoRoot "catalog\approved_software_sources.v1.json"
$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

function EnsureDir($p){ if(-not(Test-Path $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8($p,$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $p)
  [IO.File]::WriteAllText($p,($t.Replace("`r`n","`n")),$enc)
}

if(-not(Test-Path $CatalogPath -PathType Leaf)){ throw "APPROVED_SOFTWARE_CATALOG_MISSING" }

$catalog=Get-Content $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items=@($catalog.items | Where-Object { @($_.capabilities) -contains $CapabilityId })

$queue=@()
foreach($i in $items){
  $canAuto=($i.license -in @("free","free_open_source")) -and ([string]$i.winget_id -ne "")
  $queue += [pscustomobject]@{
    id=$i.id
    name=$i.name
    license=$i.license
    winget_id=$i.winget_id
    admin_required=[bool]$i.admin_required
    install_mode=$(if($canAuto){"winget"}else{"manual_review"})
    package_identity=$(if($canAuto){[string]$i.winget_id}else{""})
    status=$(if($canAuto){"ready_for_user_approval"}else{"manual_review_required"})
  }
}

$outObj=[ordered]@{
  schema="assemblelink.install_queue.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  capability_id=$CapabilityId
  queue_count=@($queue).Count
  safety_policy=[ordered]@{
    requires_user_approval=$true
    no_silent_installs=$true
    licensed_tools_excluded=$true
    admin_prompts_expected=$true
  }
  queue=$queue
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("install_queue.$CapabilityId.v1_$stamp.json")
$latest=Join-Path $StateDir ("install_queue.$CapabilityId.latest.json")
WriteUtf8 $out ($outObj|ConvertTo-Json -Depth 20)
WriteUtf8 $latest ($outObj|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.install_queue_receipt.v1_$stamp.txt")
WriteUtf8 $rcp ("schema=assemblelink.install_queue_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`ncapability_id=$CapabilityId`nstate=$out`n")

$queue | Format-Table name,install_mode,winget_id,admin_required,status -AutoSize

Write-Host ("ASSEMBLELINK_INSTALL_QUEUE_STATE: "+$out) -ForegroundColor Green
Write-Host "ASSEMBLELINK_INSTALL_QUEUE_OK" -ForegroundColor Green
