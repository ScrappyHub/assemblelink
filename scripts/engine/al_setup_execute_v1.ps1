param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$true)][string]$ApprovalPlanId,
  [switch]$Execute,
  [switch]$Resume
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){ $d=Split-Path -Parent $Path; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false))) }
function Sha([string]$Path){$stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}}
function PlanDigest($toolkitIds,$machineProfile,$items){
  $lines=@('schema=assemblelink.setup_plan.v1');foreach($id in @($toolkitIds|Sort-Object -Unique)){$lines+=('toolkit='+[string]$id)}
  $hasProfile=$null-ne$machineProfile
  if($hasProfile){$lines+=('machine_type='+[string]$machineProfile.machine_type);$lines+=('max_allocation_mib='+[string][int64]$machineProfile.max_allocation_mib)}
  foreach($x in @($items|Sort-Object id)){$fields=@([string]$x.id,[string]$x.name,[string]$x.source,[string]$x.winget_id,[string]$x.license,[string][bool]$x.admin_required,[string][bool]$x.reboot_required,(@($x.dependencies|Sort-Object)-join ','),[string]$x.mode,[string]$x.status);if($hasProfile){$fields+=[string][int64]$x.estimated_installed_mib};$fields+=@($(if($x.PSObject.Properties.Name-contains'installed_version'){[string]$x.installed_version}else{''}),$(if($x.PSObject.Properties.Name-contains'available_version'){[string]$x.available_version}else{''}));$lines+=('item='+($fields-join '|'))}
  $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes((@($lines)-join "`n")+"`n");$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
if(-not(Test-Path $PlanPath -PathType Leaf)){ throw 'SETUP_PLAN_NOT_FOUND' }
$plan=Get-Content $PlanPath -Raw|ConvertFrom-Json
if($plan.schema -ne 'assemblelink.setup_plan.v1'){ throw 'SETUP_PLAN_SCHEMA_REJECTED' }
if([string]$plan.plan_id -ne $ApprovalPlanId){ throw 'SETUP_APPROVAL_PLAN_MISMATCH' }
$machineProfile=$(if($plan.PSObject.Properties.Name-contains'machine_profile'){$plan.machine_profile}else{$null})
if($null-ne$machineProfile){
  if($machineProfile.machine_type -notin @('desktop','laptop')){throw 'SETUP_PLAN_MACHINE_TYPE_REJECTED'}
  $maxAllocationMib=[int64]$machineProfile.max_allocation_mib;$estimatedTotalMib=[int64]0;foreach($plannedItem in @($plan.items)){$estimatedTotalMib += [int64]$plannedItem.estimated_installed_mib}
  if($maxAllocationMib -lt 5120 -or $estimatedTotalMib -gt $maxAllocationMib -or [int64]$plan.allocation.estimated_installed_mib -ne $estimatedTotalMib -or -not[bool]$plan.allocation.within_limit){throw 'SETUP_PLAN_ALLOCATION_REJECTED'}
}
if((PlanDigest @($plan.toolkit_ids) $machineProfile @($plan.items)) -ne [string]$plan.plan_id){ throw 'SETUP_PLAN_CONTENT_HASH_MISMATCH' }
$state=Join-Path $RepoRoot 'state'; $receipts=Join-Path $RepoRoot 'proofs\receipts'; New-Item -ItemType Directory -Force $state,$receipts|Out-Null
$progressPath=Join-Path $state 'setup_execution.progress.json'; $results=@(); $started=(Get-Date).ToUniversalTime()
$resumedFrom=0
if($Resume){
  if(-not $Execute){throw 'SETUP_RESUME_REQUIRES_EXECUTION'}
  if(-not(Test-Path $progressPath -PathType Leaf)){throw 'SETUP_RESUME_PROGRESS_MISSING'}
  if((Get-Item $progressPath).Length -gt 2097152){throw 'SETUP_RESUME_PROGRESS_TOO_LARGE'}
  $prior=Get-Content $progressPath -Raw|ConvertFrom-Json
  if($prior.schema -ne 'assemblelink.setup_execution.progress.v1'){throw 'SETUP_RESUME_SCHEMA_REJECTED'}
  if([string]$prior.plan_id -ne $ApprovalPlanId){throw 'SETUP_RESUME_PLAN_MISMATCH'}
  if([string]$prior.status -ne 'running'){throw 'SETUP_RESUME_NOT_INTERRUPTED'}
  if([int]$prior.total -ne @($plan.items).Count){throw 'SETUP_RESUME_TOTAL_MISMATCH'}
  $priorResults=@($prior.results)
  if([int]$prior.completed -ne $priorResults.Count -or $priorResults.Count -ge @($plan.items).Count){throw 'SETUP_RESUME_COUNTS_REJECTED'}
  $terminal=@('installed_or_already_present','already_current','manual_review_required')
  for($i=0;$i-lt$priorResults.Count;$i++){
    $old=$priorResults[$i];$expected=@($plan.items)[$i]
    if([string]$old.id -ne [string]$expected.id -or [string]$old.winget_id -ne [string]$expected.winget_id){throw 'SETUP_RESUME_PREFIX_MISMATCH'}
    if([string]$old.status -notin $terminal){break}
    if($old.verified -isnot [bool] -or $old.source_verified -isnot [bool]){throw 'SETUP_RESUME_BOOLEAN_REJECTED'}
    if($expected.mode -eq 'winget'){
      if(-not [bool]$old.verified -or -not [bool]$old.source_verified){break}
      $resumeWinget=Get-Command winget.exe -ErrorAction SilentlyContinue
      if(-not $resumeWinget){throw 'SETUP_RESUME_VERIFICATION_REQUIRES_WINGET'}
      $resumeCheck=& $resumeWinget.Source list --id ([string]$expected.winget_id) --exact --source winget --accept-source-agreements --disable-interactivity 2>&1
      if($LASTEXITCODE -ne 0 -or (@($resumeCheck)-join "`n") -notmatch [regex]::Escape([string]$expected.winget_id)){break}
    }
    elseif([string]$old.status -ne 'manual_review_required'){throw 'SETUP_RESUME_MANUAL_STATUS_REJECTED'}
    $oldMessage=(([string]$old.message)-replace'[\x00-\x1f\x7f]',' ');if($oldMessage.Length-gt1024){$oldMessage=$oldMessage.Substring(0,1024)}
    $results += [ordered]@{id=[string]$expected.id;name=[string]$expected.name;winget_id=[string]$expected.winget_id;status=[string]$old.status;exit_code=$old.exit_code;verified=[bool]$old.verified;source_verified=[bool]$old.source_verified;message=$oldMessage}
  }
  $resumedFrom=$results.Count
}
$progress=[ordered]@{schema='assemblelink.setup_execution.progress.v1';plan_id=$ApprovalPlanId;status=$(if($Execute){'running'}else{'dry_run'});total=@($plan.items).Count;completed=0;results=@()}
$progress.completed=$results.Count;$progress.results=$results
WriteUtf8 $progressPath ($progress|ConvertTo-Json -Depth 20)

for($itemIndex=$results.Count;$itemIndex-lt @($plan.items).Count;$itemIndex++){
  $item=@($plan.items)[$itemIndex]
  $status='manual_review_required'; $message='This item requires a manual, account, or license step.'; $exitCode=$null; $verified=$false;$winget=$null
  if($item.mode -eq 'winget'){
    if(-not $Execute){ $status='dry_run'; $message="Would install exact Winget ID: $($item.winget_id)" }
    else {
      $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
      if(-not $winget){ $status='package_manager_unavailable'; $message='Winget is unavailable. Install or repair Windows App Installer, then retry.' }
      else {
        $identityOutput=& $winget.Source show --id ([string]$item.winget_id) --exact --source winget --accept-source-agreements --disable-interactivity 2>&1
        if($LASTEXITCODE -ne 0 -or (@($identityOutput)-join "`n") -notmatch [regex]::Escape([string]$item.winget_id)){
          $status='package_identity_unavailable';$message='The exact approved package identity was not found in the Winget community source.'
          $results += [ordered]@{id=[string]$item.id;name=[string]$item.name;winget_id=[string]$item.winget_id;status=$status;exit_code=$LASTEXITCODE;verified=$false;source_verified=$false;message=$message}
          $progress.completed=$results.Count;$progress.results=$results;WriteUtf8 $progressPath ($progress|ConvertTo-Json -Depth 20);continue
        }
        $outFile=Join-Path $env:TEMP ('assemblelink-'+[guid]::NewGuid().ToString('N')+'.out'); $errFile=$outFile+'.err'
        $p=Start-Process -FilePath $winget.Source -ArgumentList @('install','--id',[string]$item.winget_id,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements','--disable-interactivity') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $exitCode=$p.ExitCode; $text=((Get-Content $outFile,$errFile -Raw -ErrorAction SilentlyContinue)-join "`n"); Remove-Item $outFile,$errFile -Force -ErrorAction SilentlyContinue
        if($exitCode -eq 0 -or $text -match 'No available upgrade|No newer package'){
          $verifyOutput=& $winget.Source list --id ([string]$item.winget_id) --exact --source winget --accept-source-agreements --disable-interactivity 2>&1
          $verified=($LASTEXITCODE -eq 0 -and (@($verifyOutput)-join "`n") -match [regex]::Escape([string]$item.winget_id))
          if($verified){$status=$(if($exitCode -eq 0){'installed_or_already_present'}else{'already_current'});$message='Exact installed package identity independently verified.'}else{$status='verification_failed';$message='Installer returned success, but the exact installed identity could not be verified.'}
        }
        elseif($text -match 'reboot|restart'){ $status='requires_reboot';$message='Restart required before setup can continue.' }
        else {$status='install_failed';$message="Winget failed with exit code $exitCode."}
      }
    }
  }
  $results += [ordered]@{id=[string]$item.id;name=[string]$item.name;winget_id=[string]$item.winget_id;status=$status;exit_code=$exitCode;verified=$verified;source_verified=$(if($item.mode -eq 'winget' -and $Execute -and $null -ne $winget){$true}else{$false});message=$message}
  $progress.completed=$results.Count; $progress.results=$results; WriteUtf8 $progressPath ($progress|ConvertTo-Json -Depth 20)
}
$ended=(Get-Date).ToUniversalTime();$runId=[guid]::NewGuid().ToString('N'); $result=[ordered]@{schema='assemblelink.setup_execution.v1';plan_id=$ApprovalPlanId;run_id=$runId;executed=[bool]$Execute;metadata=[ordered]@{started_utc=$started.ToString('o');completed_utc=$ended.ToString('o');resumed=[bool]$Resume;resumed_from_completed=$resumedFrom};results=$results}
$resultPath=Join-Path $state ("setup_execution.$runId.json");if(Test-Path $resultPath){throw 'SETUP_RESULT_COLLISION'}; WriteUtf8 $resultPath ($result|ConvertTo-Json -Depth 20)
$hash=Sha $resultPath; WriteUtf8 ($resultPath+'.sha256') ($hash+'  '+[IO.Path]::GetFileName($resultPath))
$latest=Join-Path $state 'setup_execution.latest.json';WriteUtf8 $latest (Get-Content $resultPath -Raw);WriteUtf8 ($latest+'.sha256') ($hash+'  '+[IO.Path]::GetFileName($latest))
$receipt=Join-Path $receipts ("assemblelink.setup_execution.$runId.txt");if(Test-Path $receipt){throw 'SETUP_RECEIPT_COLLISION'}; WriteUtf8 $receipt ("schema=assemblelink.setup_execution_receipt.v1`nplan_id=$ApprovalPlanId`nrun_id=$runId`nresult=$resultPath`nsha256=$hash`n")
$receiptHash=Sha $receipt;WriteUtf8 ($receipt+'.sha256') ($receiptHash+'  '+[IO.Path]::GetFileName($receipt))
$progress.status='complete'; $progress.results=$results; WriteUtf8 $progressPath ($progress|ConvertTo-Json -Depth 20)
Write-Output $resultPath
