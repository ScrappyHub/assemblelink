param(
  [string]$RepoRoot="C:\dev\assemblelink",
  [Parameter(Mandatory=$true)][string]$CapabilityId
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$GraphPath=Join-Path $StateDir "capability_graph.latest.json"

function EnsureDir([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function WriteUtf8([string]$p,[string]$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $p)
  $u=$t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $u.EndsWith("`n")){ $u+="`n" }
  [IO.File]::WriteAllText($p,$u,$enc)
}

if(-not(Test-Path -LiteralPath $GraphPath -PathType Leaf)){ throw "CAPABILITY_GRAPH_MISSING" }

$graph=Get-Content -LiteralPath $GraphPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cap=@($graph.capabilities | Where-Object { $_.id -eq $CapabilityId } | Select-Object -First 1)
if($null -eq $cap){ throw ("CAPABILITY_NOT_FOUND: "+$CapabilityId) }

$catalog=@{
  "local-ai"=@(
    @{name="Ollama"; state="installed_or_recommended"; license="free"; mode="official_download"; source="Ollama official installer"},
    @{name="Python"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="Python.org or winget"},
    @{name="Docker Desktop"; state="installed"; license="license_depends_on_use"; mode="official_download"; source="Docker official installer"},
    @{name="NVIDIA CUDA Toolkit"; state="recommended"; license="free"; mode="official_download"; source="NVIDIA official installer"},
    @{name="PyTorch CUDA"; state="recommended"; license="free_open_source"; mode="package_manager"; source="pip/conda"},
    @{name="Model cache folder"; state="needs_mapping"; license="depends_on_models"; mode="local_config"; source="Local path"}
  )
  "game-development"=@(
    @{name="Blender"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="Blender official installer"},
    @{name="Unity Hub"; state="account_gated"; license="account_license"; mode="manual_approval"; source="Unity official installer"},
    @{name="Unreal / Epic Games Launcher"; state="account_gated"; license="account_license"; mode="manual_approval"; source="Epic official installer"},
    @{name="Visual Studio Build Tools"; state="recommended"; license="free"; mode="official_download"; source="Microsoft installer"},
    @{name="Godot"; state="installed_or_recommended"; license="free_open_source"; mode="official_or_winget"; source="Godot official installer"}
  )
  "content-creation"=@(
    @{name="Adobe Creative Cloud"; state="installed_subscription"; license="subscription"; mode="manual_license"; source="Adobe official installer"},
    @{name="OBS Studio"; state="recommended"; license="free_open_source"; mode="official_or_winget"; source="OBS official installer"},
    @{name="GIMP"; state="installed_or_recommended"; license="free_open_source"; mode="official_or_winget"; source="GIMP official installer"},
    @{name="Audacity"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="Audacity official installer"}
  )
  "cybersecurity"=@(
    @{name="Wireshark"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="Wireshark official installer"},
    @{name="Nmap"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="Nmap official installer"},
    @{name="Burp Suite Community"; state="installed"; license="free_tier_pro_available"; mode="official_download"; source="PortSwigger official installer"},
    @{name="Ghidra"; state="recommended"; license="free_open_source"; mode="official_download"; source="Official GitHub release"}
  )
  "software-development"=@(
    @{name="Git"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="Git official installer"},
    @{name="VS Code"; state="installed"; license="free"; mode="official_or_winget"; source="Microsoft installer"},
    @{name="Visual Studio"; state="installed"; license="free_or_licensed"; mode="manual_approval"; source="Visual Studio Installer"},
    @{name="JetBrains Toolbox"; state="licensed_optional"; license="subscription_possible"; mode="manual_approval"; source="JetBrains official installer"}
  )
  "infrastructure"=@(
    @{name="Docker Desktop"; state="installed"; license="license_depends_on_use"; mode="official_download"; source="Docker official installer"},
    @{name="WSL"; state="recommended"; license="free"; mode="windows_feature"; source="Windows feature"},
    @{name="PostgreSQL"; state="installed"; license="free_open_source"; mode="official_or_winget"; source="PostgreSQL official installer"},
    @{name="VirtualBox"; state="installed"; license="free"; mode="official_download"; source="Oracle official installer"}
  )
}

$items=@()
if($catalog.ContainsKey($CapabilityId)){
  foreach($x in $catalog[$CapabilityId]){
    $items += [pscustomobject]$x
  }
}

$plan=[ordered]@{
  schema="assemblelink.install_plan.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  capability_id=$CapabilityId
  capability_name=[string]$cap.name
  readiness_score=[int]$cap.score
  status=[string]$cap.status
  safety_policy=[ordered]@{
    no_silent_licensed_installs=$true
    official_sources_required=$true
    driver_installs_require_admin_and_restore_point=$true
    user_approval_required_before_changes=$true
  }
  detected=$(if($cap.PSObject.Properties["detected"]){ @($cap.PSObject.Properties["detected"].Value) }else{ @() })
  missing_required=$(if($cap.PSObject.Properties["missing_required"]){ @($cap.PSObject.Properties["missing_required"].Value) }else{ @() })
  install_items=$items
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("install_plan."+($CapabilityId -replace '[^a-zA-Z0-9_-]','_')+".v1_"+$stamp+".json")
$latest=Join-Path $StateDir ("install_plan."+($CapabilityId -replace '[^a-zA-Z0-9_-]','_')+".latest.json")

WriteUtf8 $out ($plan|ConvertTo-Json -Depth 20)
WriteUtf8 $latest ($plan|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.install_plan_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.install_plan_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`ncapability_id="+$CapabilityId+"`nstate="+$out+"`n")

$items | Select-Object name,state,license,mode | Format-Table -AutoSize

Write-Host ("ASSEMBLELINK_INSTALL_PLAN_STATE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_INSTALL_PLAN_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_INSTALL_PLAN_FROM_CAPABILITY_OK" -ForegroundColor Green