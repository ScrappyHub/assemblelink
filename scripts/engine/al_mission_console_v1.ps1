param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$PublicState=Join-Path $RepoRoot "ui\public\state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

$StatusIndex=Join-Path $StateDir "capability_status_index.latest.json"
$SystemProfile=Join-Path $StateDir "system_profile.latest.json"
$QueueDir=$StateDir

function EnsureDir([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $Path)
  $t=$Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t+="`n" }
  [IO.File]::WriteAllText($Path,$t,$enc)
}

function MissionTitle([string]$Id,[string]$Name){
  switch($Id){
    "local-ai" { return "Build a Local AI Workstation" }
    "cybersecurity" { return "Build a Cybersecurity Lab" }
    "content-creation" { return "Build a Content Creation Studio" }
    "game-development" { return "Build a Game Development Workstation" }
    "infrastructure" { return "Build an Infrastructure / Homelab Workstation" }
    "software-development" { return "Build a Software Development Workstation" }
    default { return ("Build "+$Name) }
  }
}

function MissionImpact([string]$Id){
  switch($Id){
    "local-ai" { return "Enable local model development, GPU acceleration checks, and AI runtime readiness." }
    "cybersecurity" { return "Prepare authorized security research, analysis, and lab tooling." }
    "content-creation" { return "Prepare media, video, design, audio, and streaming workflows." }
    "game-development" { return "Prepare engines, art tools, SDKs, and build runtimes." }
    "infrastructure" { return "Prepare containers, databases, shells, and local service tooling." }
    "software-development" { return "Prepare source control, editors, SDKs, package managers, and build tools." }
    default { return "Prepare this workstation capability." }
  }
}

function NextAction([string]$Id,[int]$Missing,[int]$Optional){
  if($Missing -gt 0){ return "Install missing required tools" }
  if($Id -eq "local-ai" -and $Optional -gt 0){ return "Review CUDA / GPU runtime" }
  if($Id -eq "cybersecurity" -and $Optional -gt 0){ return "Review optional lab tools" }
  if($Optional -gt 0){ return "Review optional recommended tools" }
  return "Open workspace"
}

function EstimateMinutes([int]$Missing,[int]$Optional){
  $m=2 + ($Missing * 4) + ([Math]::Min($Optional,2) * 2)
  if($m -lt 2){ $m=2 }
  return $m
}

if(-not(Test-Path -LiteralPath $StatusIndex -PathType Leaf)){ throw "CAPABILITY_STATUS_INDEX_MISSING" }

EnsureDir $StateDir
EnsureDir $PublicState
EnsureDir $ReceiptDir

$status=Get-Content -LiteralPath $StatusIndex -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities=@($status.capabilities)

$system=$null
if(Test-Path -LiteralPath $SystemProfile -PathType Leaf){
  $system=Get-Content -LiteralPath $SystemProfile -Raw -Encoding UTF8 | ConvertFrom-Json
}

$missions=@()
$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")

foreach($c in $capabilities){
  $id=[string]$c.capability_id
  $name=[string]$c.name
  $score=[int]$c.score
  $missing=[int]$c.missing
  $optional=[int]$c.optional
  $installed=[int]$c.installed

  $queuePath=Join-Path $StateDir ("install_queue.$id.latest.json")
  $queueCount=0
  if(Test-Path -LiteralPath $queuePath -PathType Leaf){
    try{
      $q=Get-Content -LiteralPath $queuePath -Raw -Encoding UTF8 | ConvertFrom-Json
      if($q.PSObject.Properties["queue"]){ $queueCount=@($q.queue).Count }
    }catch{}
  }

  $missionStatus="ready"
  if($missing -gt 0){ $missionStatus="needs_setup" }
  elseif($optional -gt 0 -or $queueCount -gt 0){ $missionStatus="ready_with_recommendations" }

  $mission=[ordered]@{
    schema="assemblelink.mission.v1"
    created_utc=(Get-Date).ToUniversalTime().ToString("o")
    mission_id=$id
    capability_id=$id
    title=MissionTitle $id $name
    capability_name=$name
    status=$missionStatus
    completion_percent=$score
    installed_count=$installed
    missing_count=$missing
    optional_count=$optional
    recommended_install_count=$queueCount
    next_action=NextAction $id $missing $optional
    estimated_minutes=EstimateMinutes $missing $optional
    impact=MissionImpact $id
  }

  $missionJson=$mission | ConvertTo-Json -Depth 20
  $missionOut=Join-Path $StateDir ("mission.$id.v1_$stamp.json")
  $missionLatest=Join-Path $StateDir ("mission.$id.latest.json")
  $missionPublic=Join-Path $PublicState ("mission.$id.latest.json")

  WriteUtf8NoBomLf $missionOut $missionJson
  WriteUtf8NoBomLf $missionLatest $missionJson
  WriteUtf8NoBomLf $missionPublic $missionJson

  $missions += [pscustomobject]$mission
}

$storageWarnings=@()
if($system -and $system.PSObject.Properties["storage"]){
  foreach($d in @($system.storage.drives)){
    if([double]$d.free_percent -lt 10){
      $storageWarnings += [pscustomobject]@{
        type="storage"
        severity="high"
        title=("Clean up drive "+[string]$d.drive)
        detail=("Only "+[string]$d.free_gb+" GB free ("+[string]$d.free_percent+"%).")
        action="Review cleanup"
      }
    }
  }
}

$recommended=@()
foreach($m in @($missions | Sort-Object @{Expression="completion_percent";Descending=$false})){
  if($m.status -ne "ready"){
    $recommended += [pscustomobject]@{
      type="mission"
      severity=$(if($m.missing_count -gt 0){"high"}else{"recommended"})
      title=$m.next_action
      detail=($m.title+" · "+$m.completion_percent+"% complete")
      mission_id=$m.mission_id
      action=$(if($m.missing_count -gt 0){"Finish setup"}else{"Review"})
    }
  }
}

foreach($s in $storageWarnings){ $recommended += $s }

$blueprint=[ordered]@{
  readiness_percent=65
  tracked=@("software","hardware","capabilities","install queues","receipts")
  missing=@("version pinning","source locking","blueprint import","rebuild executor")
  next_action="Complete Blueprint Export"
}

$console=[ordered]@{
  schema="assemblelink.mission_console.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  workstation=$(if($system){ [ordered]@{
    name=$system.machine.name
    os=$system.os.caption
    cpu=$system.cpu.name
    gpu=$(if(@($system.gpu).Count -gt 0){ $system.gpu[0].name }else{ "" })
    vram_gb=$(if(@($system.gpu).Count -gt 0){ $system.gpu[0].vram_gb }else{ 0 })
    ram_gb=$system.memory.total_gb
    free_storage_gb=$system.storage.free_gb
  }}else{ $null })
  mission_count=@($missions).Count
  ready_count=@($missions | Where-Object { $_.status -eq "ready" }).Count
  recommendation_count=@($recommended).Count
  missions=$missions
  recommended_actions=$recommended
  blueprint_readiness=$blueprint
}

$json=$console | ConvertTo-Json -Depth 30

$out=Join-Path $StateDir ("mission_console.v1_$stamp.json")
$latest=Join-Path $StateDir "mission_console.latest.json"
$public=Join-Path $PublicState "mission_console.latest.json"

WriteUtf8NoBomLf $out $json
WriteUtf8NoBomLf $latest $json
WriteUtf8NoBomLf $public $json

$receipt=Join-Path $ReceiptDir ("assemblelink.mission_console_receipt.v1_$stamp.txt")
WriteUtf8NoBomLf $receipt ("schema=assemblelink.mission_console_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nstate=$out`nmission_count="+@($missions).Count+"`n")

$missions | Sort-Object completion_percent | Format-Table title,status,completion_percent,installed_count,missing_count,optional_count,next_action -AutoSize

Write-Host ("ASSEMBLELINK_MISSION_CONSOLE_STATE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_MISSION_CONSOLE_RECEIPT: "+$receipt) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_MISSION_CONSOLE_OK" -ForegroundColor Green
