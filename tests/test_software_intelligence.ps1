param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$engine=Join-Path $RepoRoot 'scripts\engine\al_software_intelligence_v1.ps1';$inv=Join-Path $RepoRoot 'tests\fixtures\inventory.software-intelligence.json';$providers=Join-Path $RepoRoot 'tests\fixtures\providers.software-intelligence.json'
$testRoot=Join-Path $env:TEMP ('assemblelink-software-intelligence-'+[guid]::NewGuid().ToString('n'))
try{
New-Item -ItemType Directory -Force (Join-Path $testRoot 'catalog')|Out-Null;Copy-Item -LiteralPath (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Destination (Join-Path $testRoot 'catalog\approved_software_sources.v1.json')
$path=&$engine -RepoRoot $testRoot -InventoryFixturePath $inv -ProviderFixturePath $providers|Select-Object -Last 1
$result=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
if($result.schema -ne 'assemblelink.software_intelligence.v1'){throw 'BAD_SCHEMA'}
if($result.evidence_mode-ne'fixture'){throw'FIXTURE_EVIDENCE_MODE_MISSING'}
$git=$result.items|Where-Object {$_.catalog_id -eq 'git'};if($git.update_status -ne 'update_available' -or $git.installed_version -ne '2.50.0' -or $git.available_version -ne '2.51.0'){throw 'GIT_CLASSIFICATION_FAILED'}
$code=$result.items|Where-Object {$_.catalog_id -eq 'vscode'};if($code.update_status -ne 'current'){throw 'CURRENT_CLASSIFICATION_FAILED'}
$node=$result.items|Where-Object {$_.catalog_id -eq 'nodejs-lts'};if($node.update_status -ne 'installed_version_unknown'){throw 'UNKNOWN_VERSION_CLASSIFICATION_FAILED'}
$stale=$result.items|Where-Object {$_.catalog_id -eq 'ghidra'};if($stale.update_status -ne 'provider_unavailable' -or $stale.freshness -ne 'stale'){throw 'STALE_PROVIDER_MUST_NOT_REPORT_UPDATE'}
$malformed=$result.items|Where-Object {$_.catalog_id -eq '7zip'};if($malformed.update_status -ne 'provider_unavailable'){throw 'MALFORMED_PROVIDER_MUST_NOT_REPORT_CURRENT'}
$mystery=$result.items|Where-Object {$_.name -eq 'Mystery Tool'};if($mystery.update_status -ne 'unmatched' -or $mystery.catalog_id){throw 'UNMATCHED_CLASSIFICATION_FAILED'}
$sdk=$result.items|Where-Object {$_.name -eq 'Example SDK (x64)'};if($sdk.inventory_kind-ne'developer_component'-or$sdk.catalog_action-ne'informational'){throw'UNMATCHED_DEVELOPER_COMPONENT_CLASSIFICATION_FAILED'}
$component=$result.items|Where-Object {$_.name -eq 'Example Support Component'};if($component.inventory_kind-ne'system_component'-or$component.catalog_action-ne'informational'){throw'UNMATCHED_SYSTEM_COMPONENT_CLASSIFICATION_FAILED'}
if($result.summary.unmatched_application_candidates-ne1-or$result.summary.unmatched_unique_applications-ne1-or$result.summary.unmatched_components-ne2){throw'UNMATCHED_SUMMARY_CLASSIFICATION_FAILED'}
$raw=Get-Content -LiteralPath $path -Raw;if($raw -match 'evil\.exe|C:\\\\secret|uninstall_string|install_location'){throw 'PRIVATE_OR_EXECUTABLE_DATA_LEAKED'}
if(-not(Test-Path -LiteralPath "$path.sha256")){throw 'MISSING_STATE_HASH'}
$expected=((Get-Content -LiteralPath "$path.sha256" -Raw)-split'\s+')[0];$actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();if($expected -ne $actual){throw 'STATE_HASH_MISMATCH'}
$latest=Join-Path $testRoot 'state\software_intelligence.latest.json';$latestExpected=((Get-Content -LiteralPath ($latest+'.sha256') -Raw)-split'\s+')[0];$latestActual=(Get-FileHash -LiteralPath $latest -Algorithm SHA256).Hash.ToLowerInvariant();if($latestExpected-ne$latestActual){throw'LATEST_STATE_HASH_MISMATCH'}
$matrix=Get-Content (Join-Path $RepoRoot 'tests\clean_machine_matrix.v1.json') -Raw|ConvertFrom-Json;if(@($matrix.cases).Count -lt 12){throw 'CLEAN_MACHINE_MATRIX_INCOMPLETE'}
$caseIds=@($matrix.cases.id|Sort-Object -Unique);if($caseIds.Count -ne @($matrix.cases).Count){throw 'DUPLICATE_CLEAN_MACHINE_CASE'}
$requiredEvidence=@('installer_sha256_sidecar','authenticode_valid','trusted_timestamp_present','environment_match','desktop_runtime_startup','workstation_assurance_receipt_sha256','post_install_identity_verification','user_evidence_preserved');foreach($evidence in $requiredEvidence){if($matrix.required_evidence-notcontains$evidence){throw "CLEAN_MACHINE_EVIDENCE_MISSING: $evidence"}}
$runner=Get-Content (Join-Path $RepoRoot 'scripts\release\run_clean_machine_case_v1.ps1') -Raw;foreach($control in @('ConfirmEnvironment','installed_app_signer_matches_installer','desktop_runtime_startup','workstation_assurance_receipt_sha256','user_evidence_preserved')){if($runner-notmatch[regex]::Escape($control)){throw "CLEAN_MACHINE_CONTROL_NOT_WIRED: $control"}}
$engineSource=Get-Content $engine -Raw;if($engineSource-notmatch'export --output \$exportPath --include-versions'){throw 'MACHINE_READABLE_WINGET_EXPORT_NOT_WIRED'}
$signingFailedClosed=$false;try{& (Join-Path $RepoRoot 'scripts\release\sign_and_verify_v1.ps1') -ArtifactPath $engine -CertificateThumbprint ''|Out-Null}catch{if($_.Exception.Message -match 'CODE_SIGNING_CERTIFICATE_THUMBPRINT_REQUIRED'){$signingFailedClosed=$true}}
if(-not$signingFailedClosed){throw 'SIGNING_GATE_DID_NOT_FAIL_CLOSED'}
$updatePath=& (Join-Path $RepoRoot 'scripts\engine\al_update_plan_v1.ps1') -RepoRoot $testRoot|Select-Object -Last 1;$update=Get-Content -LiteralPath $updatePath -Raw|ConvertFrom-Json
if($update.item_count -ne 1 -or $update.items[0].id -ne 'git' -or $update.items[0].installed_version -ne '2.50.0' -or $update.items[0].available_version -ne '2.51.0'){throw 'UPDATE_PLAN_NOT_BOUND_TO_INTELLIGENCE'}
$updateExecution=& (Join-Path $RepoRoot 'scripts\engine\al_setup_execute_v1.ps1') -RepoRoot $testRoot -PlanPath $updatePath -ApprovalPlanId ([string]$update.plan_id)|Select-Object -Last 1
$updateResult=Get-Content -LiteralPath $updateExecution -Raw|ConvertFrom-Json;if($updateResult.executed-or$updateResult.plan_id-ne$update.plan_id){throw 'LEGACY_UPDATE_PLAN_EXECUTION_REGRESSED'}
Write-Host 'ASSEMBLELINK_SOFTWARE_INTELLIGENCE_TEST_OK'
}finally{if(Test-Path $testRoot){$resolved=(Resolve-Path $testRoot).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
