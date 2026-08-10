param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$RequestPath
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function WriteUtf8([string]$Path,[string]$Text){
  $dir=Split-Path -Parent $Path; if($dir){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function ValidId([string]$Id){ return $Id -match '^[a-z0-9][a-z0-9-]{0,63}$' }
function PlanDigest($toolkitIds,$machineProfile,$items){
  $lines=@('schema=assemblelink.setup_plan.v1')
  foreach($id in @($toolkitIds|Sort-Object -Unique)){ $lines += ('toolkit='+[string]$id) }
  $lines += ('machine_type='+[string]$machineProfile.machine_type)
  $lines += ('max_allocation_mib='+[string][int64]$machineProfile.max_allocation_mib)
  foreach($x in @($items|Sort-Object id)){
    $lines += ('item='+(@([string]$x.id,[string]$x.name,[string]$x.source,[string]$x.winget_id,[string]$x.license,[string][bool]$x.admin_required,[string][bool]$x.reboot_required,(@($x.dependencies|Sort-Object)-join ','),[string]$x.mode,[string]$x.status,[string][int64]$x.estimated_installed_mib,$(if($x.PSObject.Properties.Name-contains'installed_version'){[string]$x.installed_version}else{''}),$(if($x.PSObject.Properties.Name-contains'available_version'){[string]$x.available_version}else{''}))-join '|'))
  }
  $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes((@($lines)-join "`n")+"`n")
  $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}

$catalog=Get-Content (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Raw | ConvertFrom-Json
$toolkits=Get-Content (Join-Path $RepoRoot 'catalog\toolkits.v1.json') -Raw | ConvertFrom-Json
$allocationPolicy=Get-Content (Join-Path $RepoRoot 'catalog\allocation_policy.v1.json') -Raw | ConvertFrom-Json
$request=Get-Content $RequestPath -Raw | ConvertFrom-Json
if($request.schema -ne 'assemblelink.setup_request.v1'){ throw 'SETUP_REQUEST_SCHEMA_REJECTED' }
if($allocationPolicy.schema -ne 'assemblelink.allocation_policy.v1'){throw 'ALLOCATION_POLICY_SCHEMA_REJECTED'}
if(-not($request.PSObject.Properties.Name -contains 'machine_profile')){throw 'MACHINE_PROFILE_REQUIRED'}
$machineType=[string]$request.machine_profile.machine_type
if($machineType -notin @('desktop','laptop')){throw 'MACHINE_TYPE_REJECTED'}
try{$maxAllocationMib=[int64]$request.machine_profile.max_allocation_mib}catch{throw 'MAX_ALLOCATION_REJECTED'}
$minimumAllocationMib=[int64]$allocationPolicy.minimum_allocation_mib
$maximumAllocationMib=[int64]$allocationPolicy.maximum_allocation_mib
if($maxAllocationMib -lt $minimumAllocationMib -or $maxAllocationMib -gt $maximumAllocationMib){throw 'MAX_ALLOCATION_REJECTED'}
$machineProfile=[ordered]@{machine_type=$machineType;max_allocation_mib=$maxAllocationMib}

$catalogMap=@{}; foreach($item in @($catalog.items)){ $catalogMap[[string]$item.id]=$item }
$toolkitMap=@{}; foreach($kit in @($toolkits.toolkits)){ $toolkitMap[[string]$kit.id]=$kit }
$selected=New-Object 'System.Collections.Generic.HashSet[string]'

foreach($id in @($request.toolkit_ids)){
  $id=[string]$id; if(-not(ValidId $id) -or -not $toolkitMap.ContainsKey($id)){ throw "UNKNOWN_TOOLKIT_ID: $id" }
  foreach($softwareId in @($toolkitMap[$id].software_ids)){ [void]$selected.Add([string]$softwareId) }
}
foreach($id in @($request.software_ids)){
  $id=[string]$id; if(-not(ValidId $id) -or -not $catalogMap.ContainsKey($id)){ throw "UNKNOWN_SOFTWARE_ID: $id" }
  [void]$selected.Add($id)
}
if($selected.Count -eq 0){ throw 'EMPTY_SETUP_SELECTION' }

do {
  $added=$false
  foreach($id in @($selected)){
    if(-not $catalogMap.ContainsKey($id)){throw "UNKNOWN_SOFTWARE_ID: $id"}
    $entry=$catalogMap[$id]
    if($entry.PSObject.Properties.Name -contains 'dependencies'){
      foreach($dependency in @($entry.dependencies)){
        $dependency=[string]$dependency
        if(-not(ValidId $dependency) -or -not $catalogMap.ContainsKey($dependency)){throw "UNKNOWN_DEPENDENCY_ID: $id -> $dependency"}
        if($selected.Add($dependency)){$added=$true}
      }
    }
  }
} while($added)

$remaining=@($selected|Sort-Object);$orderedIds=@()
while($remaining.Count -gt 0){
  $ready=@($remaining|Where-Object{$candidate=$_;$deps=@();$entry=$catalogMap[$candidate];if($entry.PSObject.Properties.Name -contains 'dependencies'){$deps=@($entry.dependencies)};@($deps|Where-Object{$remaining -contains [string]$_}).Count -eq 0}|Sort-Object)
  if($ready.Count -eq 0){throw ('DEPENDENCY_CYCLE: '+($remaining -join ','))}
  $orderedIds += $ready;$remaining=@($remaining|Where-Object{$ready -notcontains $_})
}

$items=@()
foreach($id in $orderedIds){
  if(-not $catalogMap.ContainsKey($id)){ throw "TOOLKIT_REFERENCES_UNKNOWN_SOFTWARE: $id" }
  $x=$catalogMap[$id]
  $estimatedMib=$null
  if($allocationPolicy.item_overrides_mib.PSObject.Properties.Name -contains [string]$x.id){$estimatedMib=[int64]$allocationPolicy.item_overrides_mib.([string]$x.id)}
  elseif($allocationPolicy.category_estimates_mib.PSObject.Properties.Name -contains [string]$x.category){$estimatedMib=[int64]$allocationPolicy.category_estimates_mib.([string]$x.category)}
  if($null -eq $estimatedMib -or $estimatedMib -le 0){throw "ALLOCATION_ESTIMATE_MISSING: $id"}
  $automatic=([string]$x.winget_id -ne '') -and ($x.license -in @('free','free_open_source'))
  $items += [ordered]@{
    id=[string]$x.id; name=[string]$x.name; source=[string]$x.source; winget_id=[string]$x.winget_id
    license=[string]$x.license; admin_required=[bool]$x.admin_required; reboot_required=$(if($x.PSObject.Properties.Name -contains 'reboot_required'){[bool]$x.reboot_required}else{$false})
    dependencies=$(if($x.PSObject.Properties.Name -contains 'dependencies'){@($x.dependencies|ForEach-Object{[string]$_}|Sort-Object -Unique)}else{@()})
    mode=$(if($automatic){'winget'}else{'manual_review'}); status=$(if($automatic){'ready_for_user_approval'}else{'manual_review_required'})
    estimated_installed_mib=$estimatedMib
  }
}
$estimatedTotalMib=[int64]0;foreach($plannedItem in $items){$estimatedTotalMib += [int64]$plannedItem.estimated_installed_mib}
if($estimatedTotalMib -gt $maxAllocationMib){throw "ALLOCATION_LIMIT_EXCEEDED: estimated_mib=$estimatedTotalMib limit_mib=$maxAllocationMib"}
$created=(Get-Date).ToUniversalTime(); $sortedToolkitIds=@($request.toolkit_ids|ForEach-Object{[string]$_}|Sort-Object -Unique);$normalizedItems=@(foreach($it in $items){$it|ConvertTo-Json -Depth 10 -Compress|ConvertFrom-Json}); $planId=PlanDigest $sortedToolkitIds $machineProfile $normalizedItems
$plan=[ordered]@{
  schema='assemblelink.setup_plan.v1'; plan_id=$planId; metadata=[ordered]@{created_utc=$created.ToString('o')}
  toolkit_ids=$sortedToolkitIds; machine_profile=$machineProfile
  allocation=[ordered]@{estimated_installed_mib=$estimatedTotalMib;max_allocation_mib=$maxAllocationMib;remaining_planned_mib=$maxAllocationMib-$estimatedTotalMib;within_limit=$true;estimation_method=[string]$allocationPolicy.estimation_method;limitations=@($allocationPolicy.limitations)}
  item_count=$items.Count
  requires_user_approval=$true; automatic_count=@($items|Where-Object mode -eq 'winget').Count
  manual_count=@($normalizedItems|Where-Object mode -eq 'manual_review').Count; items=$normalizedItems
}
$state=Join-Path $RepoRoot 'state'; $out=Join-Path $state "setup_plan.$planId.json"; $latest=Join-Path $state 'setup_plan.latest.json'
$json=$plan|ConvertTo-Json -Depth 20; WriteUtf8 $out $json; WriteUtf8 $latest $json
Write-Output $out
