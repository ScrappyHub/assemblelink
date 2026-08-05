param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

$CapPath=Join-Path $StateDir "capability_graph.latest.json"
$SysPath=Join-Path $StateDir "system_profile.latest.json"
$DriverPath=Join-Path $StateDir "driver_profile.latest.json"

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

if(-not(Test-Path -LiteralPath $CapPath -PathType Leaf)){ throw "CAPABILITY_GRAPH_MISSING" }
if(-not(Test-Path -LiteralPath $SysPath -PathType Leaf)){ throw "SYSTEM_PROFILE_MISSING" }

$capGraph=Get-Content -LiteralPath $CapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sys=Get-Content -LiteralPath $SysPath -Raw -Encoding UTF8 | ConvertFrom-Json

$driverProfile=$null
if(Test-Path -LiteralPath $DriverPath -PathType Leaf){
  $driverProfile=Get-Content -LiteralPath $DriverPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$actions=@()

foreach($d in @($sys.storage.drives)){
  if([double]$d.free_percent -lt 10){
    $actions += [pscustomobject]@{
      priority="High"
      title=("Clean up drive "+[string]$d.drive)
      reason=("Only "+[string]$d.free_percent+"% free. Large SDKs, engines, model caches, and exports may fail.")
      source="system_profile"
      action="Review storage"
      risk="safe"
    }
  }
}

if($null -ne $driverProfile){
  foreach($r in @($driverProfile.recommendations)){
    $actions += [pscustomobject]@{
      priority="Recommended"
      title=[string]$r.name
      reason=[string]$r.reason
      source="driver_profile"
      action="Review official vendor source"
      risk=[string]$r.risk
    }
  }
}

$gpuName=""
$vram=0.0
if($sys.gpu -and @($sys.gpu).Count -gt 0){
  $gpuName=[string]$sys.gpu[0].name
  $vram=[double]$sys.gpu[0].vram_gb
}
if($gpuName -match "NVIDIA" -and $vram -lt 8){
  $actions += [pscustomobject]@{
    priority="Info"
    title="Local AI model sizing"
    reason=("RTX/NVIDIA detected with "+[string]$vram+" GB VRAM. Prefer small or quantized local models.")
    source="system_profile"
    action="Map model runtime"
    risk="safe"
  }
}

$outObj=[ordered]@{
  schema="assemblelink.recommended_actions.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  action_count=@($actions).Count
  actions=@($actions | Select-Object -First 20)
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("recommended_actions.v1_"+$stamp+".json")
$latest=Join-Path $StateDir "recommended_actions.latest.json"

WriteUtf8 $out ($outObj|ConvertTo-Json -Depth 20)
WriteUtf8 $latest ($outObj|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.recommended_actions_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.recommended_actions_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nstate="+$out+"`naction_count="+@($actions).Count+"`n")

$actions | Select-Object priority,title,source,risk | Format-Table -AutoSize

Write-Host ("ASSEMBLELINK_RECOMMENDED_ACTIONS_STATE: "+$out) -ForegroundColor Green
Write-Host "ASSEMBLELINK_RECOMMENDED_ACTIONS_OK" -ForegroundColor Green