param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

$SysPath=Join-Path $StateDir "system_profile.latest.json"
$DrvPath=Join-Path $StateDir "driver_profile.latest.json"
$CapPath=Join-Path $StateDir "capability_graph.latest.json"
$ActionsPath=Join-Path $StateDir "recommended_actions.latest.json"

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
function Clamp([int]$n){
  if($n -lt 0){ return 0 }
  if($n -gt 100){ return 100 }
  return $n
}

if(-not(Test-Path -LiteralPath $SysPath -PathType Leaf)){ throw "SYSTEM_PROFILE_MISSING" }
if(-not(Test-Path -LiteralPath $CapPath -PathType Leaf)){ throw "CAPABILITY_GRAPH_MISSING" }

$sys=Get-Content -LiteralPath $SysPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cap=Get-Content -LiteralPath $CapPath -Raw -Encoding UTF8 | ConvertFrom-Json

$drv=$null
if(Test-Path -LiteralPath $DrvPath -PathType Leaf){
  $drv=Get-Content -LiteralPath $DrvPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$actions=$null
if(Test-Path -LiteralPath $ActionsPath -PathType Leaf){
  $actions=Get-Content -LiteralPath $ActionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Storage score
$storageScore=100
$storageWarnings=@()
foreach($d in @($sys.storage.drives)){
  $pct=[double]$d.free_percent
  if($pct -lt 10){
    $storageScore -= 20
    $storageWarnings += ("Drive "+$d.drive+" is critically low: "+$pct+"% free")
  } elseif($pct -lt 15){
    $storageScore -= 10
    $storageWarnings += ("Drive "+$d.drive+" is getting low: "+$pct+"% free")
  }
}
$storageScore=Clamp $storageScore

# Hardware score
$hardwareScore=100
$hardwareNotes=@()
$ram=[double]$sys.memory.total_gb
if($ram -lt 16){ $hardwareScore-=30; $hardwareNotes+="RAM below 16 GB" }
elseif($ram -lt 32){ $hardwareScore-=10; $hardwareNotes+="RAM below 32 GB" }
else{ $hardwareNotes+=("RAM strong: "+$ram+" GB") }

if($sys.gpu -and @($sys.gpu).Count -gt 0){
  $gpuName=[string]$sys.gpu[0].name
  $vram=[double]$sys.gpu[0].vram_gb
  $vramConfidence=$(if($sys.gpu[0].PSObject.Properties.Name-contains'vram_confidence'){[string]$sys.gpu[0].vram_confidence}else{''})
  $vramObserved=($vramConfidence-eq'high'-or([string]::IsNullOrWhiteSpace($vramConfidence)-and$vram-gt0))
  $hardwareNotes+=("GPU detected: "+$gpuName)
  if($gpuName -match "NVIDIA" -and-not$vramObserved){
    $hardwareNotes+="GPU VRAM capacity is unknown because Windows reported a limited WMI value"
  }elseif($gpuName -match "NVIDIA" -and $vram -lt 8){
    $hardwareScore-=8
    $hardwareNotes+=("VRAM is usable but limited for local AI: "+$vram+" GB")
  }
}else{
  $hardwareScore-=15
  $hardwareNotes+="No GPU profile detected"
}
$hardwareScore=Clamp $hardwareScore

# Driver score
$driverScore=100
$driverNotes=@()
if($null -eq $drv){
  $driverScore=70
  $driverNotes+="Driver profile missing"
}else{
  $recs=@($drv.recommendations)
  if($recs.Count -gt 0){
    $driverScore -= [math]::Min(12,($recs.Count * 2))
    foreach($r in $recs){ $driverNotes += ("Review: "+[string]$r.name) }
  }else{
    $driverNotes+="No driver recommendations pending"
  }
}
$driverScore=Clamp $driverScore

# Capability/software score
$capScores=@()
foreach($c in @($cap.capabilities)){ $capScores += [int]$c.score }
$softwareScore=0
if($capScores.Count -gt 0){
  $softwareScore=[int][math]::Round(($capScores | Measure-Object -Average).Average)
}

# Action pressure
$actionPenalty=0
if($null -ne $actions){
  foreach($a in @($actions.actions)){
    if([string]$a.priority -eq "High"){ $actionPenalty += 3 }
    elseif([string]$a.priority -eq "Recommended"){ $actionPenalty += 1 }
  }
}

$overall=[int][math]::Round((($storageScore*0.25)+($hardwareScore*0.25)+($driverScore*0.20)+($softwareScore*0.30)) - $actionPenalty)
$overall=Clamp $overall

$profile=[ordered]@{
  schema="assemblelink.workstation_health.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  score=$overall
  areas=@(
    [pscustomobject]@{ name="Storage"; score=$storageScore; notes=@($storageWarnings) },
    [pscustomobject]@{ name="Hardware"; score=$hardwareScore; notes=@($hardwareNotes) },
    [pscustomobject]@{ name="Drivers"; score=$driverScore; notes=@($driverNotes) },
    [pscustomobject]@{ name="Software Capabilities"; score=$softwareScore; notes=@("Average capability readiness") }
  )
  summary=[ordered]@{
    machine=[string]$sys.machine.name
    cpu=[string]$sys.cpu.name
    ram_gb=$ram
    gpu=$(if($sys.gpu -and @($sys.gpu).Count -gt 0){ [string]$sys.gpu[0].name }else{ "" })
    total_storage_gb=[double]$sys.storage.total_gb
    free_storage_gb=[double]$sys.storage.free_gb
  }
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("workstation_health.v1_"+$stamp+".json")
$latest=Join-Path $StateDir "workstation_health.latest.json"

WriteUtf8 $out ($profile|ConvertTo-Json -Depth 20)
WriteUtf8 $latest ($profile|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.workstation_health_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.workstation_health_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nstate="+$out+"`nscore="+$overall+"`n")

$profile.areas | Format-Table name,score -AutoSize
Write-Host ("WORKSTATION_HEALTH_SCORE: "+$overall) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_WORKSTATION_HEALTH_STATE: "+$out) -ForegroundColor Green
Write-Host "ASSEMBLELINK_WORKSTATION_HEALTH_OK" -ForegroundColor Green
