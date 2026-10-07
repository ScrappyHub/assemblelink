param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$CapDir=Join-Path $RepoRoot "manifests\capabilities"
$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$Inventory=Join-Path $StateDir "application_inventory.latest.json"
$SystemProfilePath=Join-Path $StateDir "system_profile.latest.json"

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
function PropArr([object]$obj,[string]$name){
  $p=$obj.PSObject.Properties[$name]
  if($null -eq $p){ return @() }
  if($null -eq $p.Value){ return @() }

  $items=@()
  foreach($v in $p.Value){
    $s=[string]$v
    if(-not [string]::IsNullOrWhiteSpace($s)){
      $items += $s
    }
  }
  return $items
}
function NeedlePresent([string]$haystack,[string]$needle){
  return ($haystack.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}
function MatchedNeedles([string]$haystack,[object[]]$needles){
  $out=@()
  foreach($n in @($needles)){
    $needle=[string]$n
    if([string]::IsNullOrWhiteSpace($needle)){ continue }
    if(NeedlePresent $haystack $needle){ $out += $needle }
  }
  return @($out | Sort-Object -Unique)
}
function AppExamples([object[]]$apps,[object[]]$needles){
  $set=New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  foreach($app in @($apps)){
    $name=[string]$app.name
    $publisher=[string]$app.publisher
    $path=[string]$app.install_location
    $hay=($name+" "+$publisher+" "+$path)

    foreach($n in @($needles)){
      $needle=[string]$n
      if([string]::IsNullOrWhiteSpace($needle)){ continue }

      if($hay.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -ge 0){
        if(-not [string]::IsNullOrWhiteSpace($name)){
          [void]$set.Add($name)
        }
      }
    }
  }

  $out=@()
  foreach($x in $set){ $out += [string]$x }
  return @($out | Sort-Object | Select-Object -First 18)
}
function HardwareSupport([object]$SystemProfile,[string]$CapabilityId){
  if($null -eq $SystemProfile){
    return [ordered]@{
      status="Unknown"
      notes=@("System profile missing")
    }
  }

  $notes=@()
  $status="OK"

  $ramGb=[double]$SystemProfile.memory.total_gb
  $freeStorageGb=[double]$SystemProfile.storage.free_gb
  $gpuName=""
  $vramGb=0.0

  if($SystemProfile.gpu -and @($SystemProfile.gpu).Count -gt 0){
    $gpuName=[string]$SystemProfile.gpu[0].name
    $vramGb=[double]$SystemProfile.gpu[0].vram_gb
  }

  if($CapabilityId -eq "local-ai"){
    if($gpuName -match "NVIDIA"){ $notes += "NVIDIA GPU detected: $gpuName" } else { $notes += "No NVIDIA GPU detected"; $status="Limited" }
    if($vramGb -ge 8){ $notes += "VRAM is strong for local models: $vramGb GB" }
    elseif($vramGb -ge 4){ $notes += "VRAM is usable for small local models: $vramGb GB"; if($status -eq "OK"){ $status="Partial" } }
    else { $notes += "VRAM is low for local AI: $vramGb GB"; $status="Limited" }
    if($ramGb -ge 32){ $notes += "System RAM is strong: $ramGb GB" } else { $notes += "System RAM may limit AI workloads: $ramGb GB"; $status="Partial" }
  }

  elseif($CapabilityId -eq "game-development"){
    if($gpuName){ $notes += "GPU detected for engine/editor workloads: $gpuName" }
    if($ramGb -ge 32){ $notes += "RAM is strong for game development: $ramGb GB" }
    if($freeStorageGb -lt 150){ $notes += "Free storage is low for Unity/Unreal projects: $freeStorageGb GB"; $status="Storage warning" }
  }

  elseif($CapabilityId -eq "content-creation"){
    if($ramGb -ge 32){ $notes += "RAM is strong for Adobe/video/creative workloads: $ramGb GB" }
    if($gpuName){ $notes += "GPU acceleration available: $gpuName" }
    if($freeStorageGb -lt 200){ $notes += "Free storage may be tight for media projects: $freeStorageGb GB"; $status="Storage warning" }
  }

  elseif($CapabilityId -eq "infrastructure"){
    if($ramGb -ge 32){ $notes += "RAM is strong for VMs/containers: $ramGb GB" }
    if($freeStorageGb -lt 100){ $notes += "Free storage may limit Docker/VM images: $freeStorageGb GB"; $status="Storage warning" }
  }

  else {
    $notes += "Hardware profile available"
  }

  return [ordered]@{
    status=$status
    cpu=[string]$SystemProfile.cpu.name
    ram_gb=$ramGb
    gpu=$gpuName
    vram_gb=$vramGb
    free_storage_gb=$freeStorageGb
    notes=$notes
  }
}
function MissingNeedles([object[]]$all,[object[]]$matched){
  $missing=@()
  foreach($n in @($all)){
    $needle=[string]$n
    if([string]::IsNullOrWhiteSpace($needle)){ continue }

    $found=$false
    foreach($m in @($matched)){
      if(([string]$m).Equals($needle,[System.StringComparison]::OrdinalIgnoreCase)){
        $found=$true
      }
    }

    if(-not $found){ $missing += $needle }
  }
  return $missing
}

if(-not(Test-Path -LiteralPath $Inventory -PathType Leaf)){ throw ("INVENTORY_MISSING: "+$Inventory) }

$inventoryText=Get-Content -LiteralPath $Inventory -Raw -Encoding UTF8
$parsedInventory=$inventoryText | ConvertFrom-Json
$apps=@()
foreach($item in $parsedInventory){ $apps += $item }
$appNames=@()
foreach($a in $apps){
  $p=$a.PSObject.Properties["name"]
  if($null -ne $p -and $null -ne $p.Value){
    $s=[string]$p.Value
    if(-not [string]::IsNullOrWhiteSpace($s)){ $appNames += $s }
  }
}

$systemProfile=$null
if(Test-Path -LiteralPath $SystemProfilePath -PathType Leaf){
  $systemProfile=Get-Content -LiteralPath $SystemProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$capFiles=@(Get-ChildItem -LiteralPath $CapDir -Filter "*.capability.json" | Sort-Object Name)
$results=@()

foreach($file in $capFiles){
  $cap=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

  $required=PropArr $cap "required"
  $recommended=PropArr $cap "recommended"
  $optional=PropArr $cap "optional"
  $actions=PropArr $cap "actions"

  $requiredMatched=MatchedNeedles $inventoryText $required
  $recommendedMatched=MatchedNeedles $inventoryText $recommended
  $optionalMatched=MatchedNeedles $inventoryText $optional

  $requiredScore=0
  if(@($required).Count -gt 0){ $requiredScore=[math]::Round((@($requiredMatched).Count / @($required).Count) * 55) }

  $recommendedScore=0
  if(@($recommended).Count -gt 0){ $recommendedScore=[math]::Round((@($recommendedMatched).Count / @($recommended).Count) * 35) }

  $optionalScore=0
  if(@($optional).Count -gt 0){ $optionalScore=[math]::Round((@($optionalMatched).Count / @($optional).Count) * 10) }

  $score=[int][math]::Min(100,($requiredScore+$recommendedScore+$optionalScore))
  $status="Missing"
  if($score -ge 90){ $status="Ready" }
  elseif($score -ge 75){ $status="Strong" }
  elseif($score -ge 45){ $status="Partial" }
  elseif($score -gt 0){ $status="Minimal" }

  $allMatched=@($requiredMatched + $recommendedMatched + $optionalMatched | Sort-Object -Unique)
  $examples=AppExamples -apps $apps -needles $allMatched
  if(@($examples).Count -lt 1){
    $examples=@($allMatched)
  }

  $results += [pscustomobject]@{
    id=[string]$cap.id
    name=[string]$cap.name
    icon=[string]$cap.icon
    score=$score
    status=$status
    matched_needles=@($allMatched)
    detected_count=@($examples).Count
    detected=@($examples)
    missing_required=@(MissingNeedles -all $required -matched $requiredMatched)
    actions=$actions
    hardware_support=(HardwareSupport -SystemProfile $systemProfile -CapabilityId ([string]$cap.id))
  }
}

$graph=[ordered]@{
  schema="assemblelink.capability_graph.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  software_count=$apps.Count
  capability_count=@($results).Count
  workstation_identity=[ordered]@{
    label="Multi-discipline creative + engineering workstation"
    primary=@($results | Sort-Object score -Descending | Select-Object -First 2 | ForEach-Object { $_.name })
    secondary=@($results | Sort-Object score -Descending | Select-Object -Skip 2 -First 2 | ForEach-Object { $_.name })
    recommended_expansion=@($results | Where-Object { $_.score -lt 85 } | Sort-Object score -Descending | Select-Object -First 3 | ForEach-Object { $_.name })
  }
  capabilities=$results
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("capability_graph.v1_"+$stamp+".json")
$latest=Join-Path $StateDir "capability_graph.latest.json"

WriteUtf8 $out ($graph|ConvertTo-Json -Depth 30)
WriteUtf8 $latest ($graph|ConvertTo-Json -Depth 30)

$rcp=Join-Path $ReceiptDir ("assemblelink.capability_graph_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.capability_graph_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nsoftware_count="+@($apps).Count+"`nstate="+$out+"`n")

$results | Select-Object name,status,score,detected_count | Format-Table -AutoSize
Write-Host ("ASSEMBLELINK_CAPABILITY_GRAPH_STATE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_CAPABILITY_GRAPH_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_CAPABILITY_RESOLVER_OK" -ForegroundColor Green
