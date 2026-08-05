param([string]$RepoRoot='C:\dev\assemblelink')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$sourceRoot=$RepoRoot;$testRoot=Join-Path $env:TEMP ('assemblelink-setup-security-'+[guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force $testRoot|Out-Null;Copy-Item -LiteralPath (Join-Path $sourceRoot 'catalog'),(Join-Path $sourceRoot 'scripts'),(Join-Path $sourceRoot 'tests') -Destination $testRoot -Recurse;$RepoRoot=$testRoot
try{
function Run([string]$script,[string[]]$arguments){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot $script) @arguments;if($LASTEXITCODE -ne 0){throw "TEST_COMMAND_FAILED: $script"}}
Run 'scripts\engine\al_setup_plan_v1.ps1' @('-RepoRoot',$RepoRoot,'-RequestPath',(Join-Path $RepoRoot 'tests\fixtures\setup-request.valid.json'))
$plan=Get-Content (Join-Path $RepoRoot 'state\setup_plan.latest.json') -Raw|ConvertFrom-Json
Run 'scripts\engine\al_setup_execute_v1.ps1' @('-RepoRoot',$RepoRoot,'-PlanPath',(Join-Path $RepoRoot "state\setup_plan.$($plan.plan_id).json"),'-ApprovalPlanId',[string]$plan.plan_id)
$resultPath=Join-Path $RepoRoot 'state\setup_execution.latest.json';$hash=(Get-FileHash $resultPath -Algorithm SHA256).Hash;$side=((Get-Content ($resultPath+'.sha256') -Raw)-split '\s+')[0]
if($hash.ToLowerInvariant() -ne $side.ToLowerInvariant()){throw 'RESULT_HASH_MISMATCH'};$firstResult=Get-Content $resultPath -Raw|ConvertFrom-Json;if($firstResult.executed){throw 'DRY_RUN_EXECUTED'}
$firstReceipt=Join-Path $RepoRoot "proofs\receipts\assemblelink.setup_execution.$($firstResult.run_id).txt";if(-not(Test-Path $firstReceipt)){throw 'APPEND_ONLY_RECEIPT_MISSING'}
$firstReceiptSidecar=$firstReceipt+'.sha256';if(-not(Test-Path $firstReceiptSidecar)){throw 'RECEIPT_HASH_MISSING'};$receiptHash=(Get-FileHash $firstReceipt -Algorithm SHA256).Hash;$receiptSide=((Get-Content $firstReceiptSidecar -Raw)-split '\s+')[0];if($receiptHash.ToLowerInvariant() -ne $receiptSide.ToLowerInvariant()){throw 'RECEIPT_HASH_MISMATCH'}
Run 'scripts\engine\al_setup_execute_v1.ps1' @('-RepoRoot',$RepoRoot,'-PlanPath',(Join-Path $RepoRoot "state\setup_plan.$($plan.plan_id).json"),'-ApprovalPlanId',[string]$plan.plan_id)
$secondResult=Get-Content $resultPath -Raw|ConvertFrom-Json;$secondReceipt=Join-Path $RepoRoot "proofs\receipts\assemblelink.setup_execution.$($secondResult.run_id).txt"
if($firstResult.run_id -eq $secondResult.run_id -or -not(Test-Path $firstReceipt) -or -not(Test-Path $secondReceipt)){throw 'REPLAY_OVERWROTE_APPEND_ONLY_EVIDENCE'}
Run 'scripts\engine\al_setup_plan_v1.ps1' @('-RepoRoot',$RepoRoot,'-RequestPath',(Join-Path $RepoRoot 'tests\fixtures\setup-request.manual-only.json'))
$manualPlan=Get-Content (Join-Path $RepoRoot 'state\setup_plan.latest.json') -Raw|ConvertFrom-Json
$manualProgress=[ordered]@{schema='assemblelink.setup_execution.progress.v1';plan_id=[string]$manualPlan.plan_id;status='running';total=1;completed=0;results=@()}
[IO.File]::WriteAllText((Join-Path $RepoRoot 'state\setup_execution.progress.json'),($manualProgress|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Run 'scripts\engine\al_setup_execute_v1.ps1' @('-RepoRoot',$RepoRoot,'-PlanPath',(Join-Path $RepoRoot "state\setup_plan.$($manualPlan.plan_id).json"),'-ApprovalPlanId',[string]$manualPlan.plan_id,'-Execute','-Resume')
$resumed=Get-Content $resultPath -Raw|ConvertFrom-Json
if(-not$resumed.executed -or -not$resumed.metadata.resumed -or [int]$resumed.metadata.resumed_from_completed-ne0 -or $resumed.results[0].status-ne'manual_review_required'){throw 'INTERRUPTED_MANUAL_PLAN_DID_NOT_RESUME_SAFELY'}
$forged=[ordered]@{schema='assemblelink.setup_execution.progress.v1';plan_id=[string]$plan.plan_id;status='running';total=@($plan.items).Count;completed=1;results=@([ordered]@{id='forged';name='Forged';winget_id='';status='manual_review_required';exit_code=$null;verified=$false;source_verified=$false;message='forged'})}
[IO.File]::WriteAllText((Join-Path $RepoRoot 'state\setup_execution.progress.json'),($forged|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
$ErrorActionPreference='Continue';& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\engine\al_setup_execute_v1.ps1') -RepoRoot $RepoRoot -PlanPath (Join-Path $RepoRoot "state\setup_plan.$($plan.plan_id).json") -ApprovalPlanId ([string]$plan.plan_id) -Execute -Resume *> $null;$ErrorActionPreference='Stop'
if($LASTEXITCODE -eq 0){throw 'FORGED_RESUME_PREFIX_ACCEPTED'}
Run 'scripts\engine\al_setup_execute_v1.ps1' @('-RepoRoot',$RepoRoot,'-PlanPath',(Join-Path $RepoRoot "state\setup_plan.$($plan.plan_id).json"),'-ApprovalPlanId',[string]$plan.plan_id)
$tamperedPlan=Join-Path $env:TEMP 'AssembleLink-Plan-tampered.json';$tamperObj=Get-Content (Join-Path $RepoRoot "state\setup_plan.$($plan.plan_id).json") -Raw|ConvertFrom-Json;$tamperObj.items[0].name='Injected Name';[IO.File]::WriteAllText($tamperedPlan,($tamperObj|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
$ErrorActionPreference='Continue';& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\engine\al_setup_execute_v1.ps1') -RepoRoot $RepoRoot -PlanPath $tamperedPlan -ApprovalPlanId ([string]$plan.plan_id) *> $null;$ErrorActionPreference='Stop'
if($LASTEXITCODE -eq 0){throw 'TAMPERED_APPROVED_PLAN_ACCEPTED'};Remove-Item $tamperedPlan -Force -ErrorAction SilentlyContinue
$bad=@('setup-request.unknown-toolkit.json','setup-request.command-injection.json')
$ErrorActionPreference='Continue'
foreach($file in $bad){& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\engine\al_setup_plan_v1.ps1') -RepoRoot $RepoRoot -RequestPath (Join-Path $RepoRoot "tests\fixtures\$file") *> $null;if($LASTEXITCODE -eq 0){throw "UNSAFE_REQUEST_ACCEPTED: $file"}}
$ErrorActionPreference='Stop'
Run 'scripts\engine\al_setup_plan_v1.ps1' @('-RepoRoot',$RepoRoot,'-RequestPath',(Join-Path $RepoRoot 'tests\fixtures\setup-request.valid.json'))
Run 'scripts\engine\al_blueprint_export_v1.ps1' @('-RepoRoot',$RepoRoot)
$blueprint=Get-ChildItem (Join-Path $RepoRoot 'exports') -Filter 'AssembleLink-Blueprint-*.json'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
Run 'scripts\engine\al_blueprint_import_v1.ps1' @('-RepoRoot',$RepoRoot,'-BlueprintPath',$blueprint.FullName)
$tampered=Join-Path $env:TEMP 'AssembleLink-Blueprint-tampered.json';[IO.File]::WriteAllText($tampered,(Get-Content $blueprint.FullName -Raw)+' ',(New-Object Text.UTF8Encoding($false)));[IO.File]::Copy($blueprint.FullName+'.sha256',$tampered+'.sha256',$true)
$ErrorActionPreference='Continue'; & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\engine\al_blueprint_import_v1.ps1') -RepoRoot $RepoRoot -BlueprintPath $tampered *> $null; $ErrorActionPreference='Stop'
if($LASTEXITCODE -eq 0){throw 'TAMPERED_BLUEPRINT_ACCEPTED'}
Remove-Item $tampered,($tampered+'.sha256') -Force -ErrorAction SilentlyContinue
$trustedScripts=@('scripts\engine\al_setup_execute_v1.ps1','scripts\engine\al_software_intelligence_v1.ps1','scripts\engine\al_blueprint_export_v1.ps1','scripts\engine\al_blueprint_import_v1.ps1','scripts\commands\al_driver_profile_v1.ps1');foreach($trustedScript in $trustedScripts){$source=Get-Content (Join-Path $RepoRoot $trustedScript) -Raw;if($source-match'Get-FileHash'){throw "OPTIONAL_HASH_CMDLET_IN_PACKAGED_RUNTIME: $trustedScript"};if($source-notmatch'Security\.Cryptography\.SHA256'){throw "DOTNET_HASHING_NOT_WIRED: $trustedScript"}}
Write-Host 'ASSEMBLELINK_SETUP_SECURITY_TESTS_OK' -ForegroundColor Green
}finally{if(Test-Path $testRoot){$resolved=(Resolve-Path $testRoot).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
