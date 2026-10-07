param(
  [string]$RepoRoot='C:\dev\assemblelink',
  [string]$InstallerPath='',
  [string]$RuntimePath=''
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
function WriteUtf8([string]$Path,[string]$Text){EnsureDir (Split-Path -Parent $Path);$normalized=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$normalized.EndsWith("`n")){$normalized+="`n"};[IO.File]::WriteAllText($Path,$normalized,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function RequireFile([string]$Path,[string]$Name){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WORKSTATION_PROOF_INPUT_MISSING: $Name"}}
function VerifySidecar([string]$Path){RequireFile $Path $Path;RequireFile ($Path+'.sha256') ($Path+'.sha256');$expected=((Get-Content -LiteralPath ($Path+'.sha256') -Raw)-split'\s+')[0].ToLowerInvariant();$actual=Sha $Path;if($expected-ne$actual){throw "WORKSTATION_PROOF_HASH_MISMATCH: $Path"};$actual}
function ReadJson([string]$Path){try{Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "WORKSTATION_PROOF_JSON_INVALID: $Path"}}
function IsUnder([string]$Candidate,[string]$Parent){$c=[IO.Path]::GetFullPath($Candidate);$p=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\';$c.StartsWith($p,[StringComparison]::OrdinalIgnoreCase)}

$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$stateDir=Join-Path $RepoRoot 'state';$receiptDir=Join-Path $RepoRoot 'proofs\receipts';$proofDir=Join-Path $RepoRoot 'proofs\workstation'
$systemPath=Join-Path $stateDir 'system_profile.latest.json';$driverPath=Join-Path $stateDir 'driver_profile.latest.json';$healthPath=Join-Path $stateDir 'workstation_health.latest.json';$capabilityPath=Join-Path $stateDir 'capability_status_index.latest.json';$catalogPath=Join-Path $stateDir 'catalog_verification.live.latest.json'
if([string]::IsNullOrWhiteSpace($InstallerPath)){$InstallerPath=Join-Path $RepoRoot 'ui\src-tauri\target\release\bundle\nsis\AssembleLink_0.1.0_x64-setup.exe'}
if([string]::IsNullOrWhiteSpace($RuntimePath)){$RuntimePath=Join-Path $RepoRoot 'ui\src-tauri\target\release\assemblelink.exe'}

$systemHash=VerifySidecar $systemPath;$driverHash=VerifySidecar $driverPath;$catalogHash=VerifySidecar $catalogPath;$installerHash=VerifySidecar $InstallerPath
RequireFile $healthPath 'workstation health';RequireFile $capabilityPath 'capability status';RequireFile $RuntimePath 'desktop runtime'
$system=ReadJson $systemPath;$driver=ReadJson $driverPath;$health=ReadJson $healthPath;$capability=ReadJson $capabilityPath;$catalog=ReadJson $catalogPath
if($system.schema-ne'assemblelink.system_profile.v2'){throw'WORKSTATION_PROOF_SYSTEM_SCHEMA_INVALID'}
if($driver.schema-ne'assemblelink.driver_profile.v2'){throw'WORKSTATION_PROOF_DRIVER_SCHEMA_INVALID'}
if($catalog.schema-ne'assemblelink.catalog_verification.v1'-or-not$catalog.live){throw'WORKSTATION_PROOF_CATALOG_NOT_LIVE'}

$softwareReceipt=Get-ChildItem -LiteralPath $receiptDir -Filter 'assemblelink.software_intelligence_receipt.*.json'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
if(-not$softwareReceipt){throw'WORKSTATION_PROOF_SOFTWARE_RECEIPT_MISSING'}
$softwareReceiptHash=VerifySidecar $softwareReceipt.FullName;$softwareReceiptBody=ReadJson $softwareReceipt.FullName;$softwarePath=[string]$softwareReceiptBody.state
if(-not(IsUnder $softwarePath $stateDir)){throw'WORKSTATION_PROOF_SOFTWARE_STATE_PATH_ESCAPE'}
$softwareHash=VerifySidecar $softwarePath;if($softwareHash-ne([string]$softwareReceiptBody.sha256).ToLowerInvariant()){throw'WORKSTATION_PROOF_SOFTWARE_RECEIPT_MISMATCH'}
$software=ReadJson $softwarePath;if($software.schema-ne'assemblelink.software_intelligence.v1'){throw'WORKSTATION_PROOF_SOFTWARE_SCHEMA_INVALID'};if([string]$software.evidence_mode-ne'live'){throw'WORKSTATION_PROOF_FIXTURE_EVIDENCE_REJECTED'}

$signature=Get-AuthenticodeSignature -LiteralPath $InstallerPath
$runtimeHash=Sha $RuntimePath;$runtimeSmokeFile=Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'proofs\runtime') -Filter 'assemblelink.runtime_smoke.*.json' -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
$runtimeSmoke=$null;$runtimeSmokeHash='';$runtimeStatus='not_observed'
if($runtimeSmokeFile){$runtimeSmokeHash=VerifySidecar $runtimeSmokeFile.FullName;$runtimeSmoke=ReadJson $runtimeSmokeFile.FullName;if($runtimeSmoke.schema-ne'assemblelink.runtime_smoke.v1'-or[string]$runtimeSmoke.runtime_sha256-ne$runtimeHash){throw'WORKSTATION_PROOF_RUNTIME_SMOKE_MISMATCH'};$runtimeStatus=$(if($runtimeSmoke.status-eq'passed'-and$runtimeSmoke.alive_after_wait){'verified'}else{'failed'})}
$gpu=@($system.gpu|Select-Object -First 1);$vram=[ordered]@{status='not_observed';gb=$null;source='';confidence='unknown'}
if($gpu.Count){$confidence=[string]$gpu[0].vram_confidence;$vram=[ordered]@{status=$(if($confidence-eq'high'){'observed'}else{'unknown'});gb=$(if($confidence-eq'high'){$gpu[0].vram_gb}else{$null});source=[string]$gpu[0].vram_source;confidence=$confidence}}
$criticalDrives=@($system.storage.drives|Where-Object{[double]$_.free_percent-lt10}|ForEach-Object{[ordered]@{drive=[string]$_.drive;free_gb=$_.free_gb;free_percent=$_.free_percent}})
$lowDrives=@($system.storage.drives|Where-Object{[double]$_.free_percent-ge10-and[double]$_.free_percent-lt15}|ForEach-Object{[ordered]@{drive=[string]$_.drive;free_gb=$_.free_gb;free_percent=$_.free_percent}})
$status=if($system.observation_status-ne'complete'-or$driver.observation_status-ne'complete'){'incomplete_observation'}elseif($runtimeStatus-ne'verified'){'runtime_not_proven'}elseif([int]$catalog.live_failed-gt0){'catalog_verification_failed'}elseif($signature.Status-ne'Valid'){'verified_with_release_blocker'}elseif([int]$software.summary.unknown-gt0){'verified_with_update_unknowns'}elseif($criticalDrives.Count){'verified_with_critical_attention'}else{'verified'}
$checks=@(
  [ordered]@{name='system_profile_integrity';status='verified';sha256=$systemHash},
  [ordered]@{name='driver_profile_integrity';status='verified';sha256=$driverHash},
  [ordered]@{name='software_intelligence_integrity';status='verified';sha256=$softwareHash;receipt_sha256=$softwareReceiptHash},
  [ordered]@{name='live_catalog_identity';status=$(if([int]$catalog.live_failed-eq0){'verified'}else{'failed'});verified=[int]$catalog.live_verified;failed=[int]$catalog.live_failed;sha256=$catalogHash},
  [ordered]@{name='installer_integrity';status='verified';sha256=$installerHash},
  [ordered]@{name='desktop_runtime_startup';status=$runtimeStatus;runtime_sha256=$runtimeHash;smoke_proof_sha256=$runtimeSmokeHash},
  [ordered]@{name='installer_signature';status=$(if($signature.Status-eq'Valid'){'verified'}else{'blocked'});authenticode=[string]$signature.Status;timestamp_present=[bool]$signature.TimeStamperCertificate},
  [ordered]@{name='software_update_coverage';status=$(if([int]$software.summary.unknown-eq0){'verified'}else{'unknown'});unknown=[int]$software.summary.unknown;updates=[int]$software.summary.updates_available},
  [ordered]@{name='storage_capacity';status=$(if($criticalDrives.Count){'critical'}elseif($lowDrives.Count){'attention'}else{'verified'});critical_drives=$criticalDrives;low_drives=$lowDrives}
)
$proof=[ordered]@{
  schema='assemblelink.workstation_proof.v1';proof_id=[guid]::NewGuid().ToString('n');observed_utc=(Get-Date).ToUniversalTime().ToString('o');status=$status
  scope=[ordered]@{system=$true;drivers=$true;software_inventory=$true;software_updates=$true;capabilities=$true;catalog=$true;desktop_runtime_artifact=$true;desktop_runtime_startup=($runtimeStatus-eq'verified');installer=$true;network_security=$false;malware_scan=$false;firmware_freshness=$false}
  workstation=[ordered]@{machine=[string]$system.machine.name;os=[string]$system.os.caption;os_build=[string]$system.os.build;architecture=[string]$system.os.architecture;cpu=([string]$system.cpu.name).Trim();cores=$system.cpu.cores;logical_processors=$system.cpu.logical_processors;memory_gb=$system.memory.total_gb;gpu=$(if($gpu.Count){[string]$gpu[0].name}else{''});gpu_vram=$vram;storage_total_gb=$system.storage.total_gb;storage_free_gb=$system.storage.free_gb}
  observations=[ordered]@{system=[string]$system.observation_status;drivers=[string]$driver.observation_status;driver_recommendations=@($driver.recommendations).Count;software_detected=[int]$software.summary.detected;catalog_matched=[int]$software.summary.catalog_matched;software_unmatched=[int]$software.summary.unmatched;software_unmatched_application_candidates=$(if($software.summary.PSObject.Properties.Name-contains'unmatched_application_candidates'){[int]$software.summary.unmatched_application_candidates}else{[int]$software.summary.unmatched});software_unmatched_unique_applications=$(if($software.summary.PSObject.Properties.Name-contains'unmatched_unique_applications'){[int]$software.summary.unmatched_unique_applications}else{[int]$software.summary.unmatched});software_unmatched_components=$(if($software.summary.PSObject.Properties.Name-contains'unmatched_components'){[int]$software.summary.unmatched_components}else{0});updates_available=[int]$software.summary.updates_available;update_status_unknown=[int]$software.summary.unknown;capability_average_score=[int]$health.areas[-1].score;workstation_health_score=[int]$health.score;catalog_items=[int]$catalog.catalog_items;catalog_live_verified=[int]$catalog.live_verified}
  checks=$checks
  evidence=[ordered]@{system_profile=[ordered]@{path=[IO.Path]::GetFileName($systemPath);sha256=$systemHash};driver_profile=[ordered]@{path=[IO.Path]::GetFileName($driverPath);sha256=$driverHash};software_intelligence=[ordered]@{path=[IO.Path]::GetFileName($softwarePath);sha256=$softwareHash};software_receipt=[ordered]@{path=$softwareReceipt.Name;sha256=$softwareReceiptHash};capability_status=[ordered]@{path=[IO.Path]::GetFileName($capabilityPath);sha256=Sha $capabilityPath};workstation_health=[ordered]@{path=[IO.Path]::GetFileName($healthPath);sha256=Sha $healthPath;sealed_at_source=$false};catalog_verification=[ordered]@{path=[IO.Path]::GetFileName($catalogPath);sha256=$catalogHash};desktop_runtime=[ordered]@{path=[IO.Path]::GetFileName($RuntimePath);sha256=$runtimeHash};runtime_smoke=$(if($runtimeSmokeFile){[ordered]@{path=$runtimeSmokeFile.Name;sha256=$runtimeSmokeHash}}else{$null});installer=[ordered]@{path=[IO.Path]::GetFileName($InstallerPath);sha256=$installerHash}}
  limitations=@('Installed-software update status is unknown when provider inventory comparison is unavailable.','Unmatched inventory classes are review heuristics and never grant installation authority.','GPU VRAM is unknown when Windows exposes only the WMI 32-bit-limited value.','Driver recommendations are official support paths, not freshness claims.','This proof does not claim network security, malware absence, or firmware freshness.','Public release remains blocked unless the installer has a valid trusted signature and timestamp.')
}
EnsureDir $proofDir;$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss');$out=Join-Path $proofDir "assemblelink.workstation_proof.$stamp.json";WriteUtf8 $out ($proof|ConvertTo-Json -Depth 20);WriteUtf8 ($out+'.sha256') ((Sha $out)+'  '+[IO.Path]::GetFileName($out)+"`n")
$receipt=Join-Path $receiptDir "assemblelink.workstation_proof_receipt.$stamp.json";WriteUtf8 $receipt (([ordered]@{schema='assemblelink.workstation_proof_receipt.v1';proof=[IO.Path]::GetFileName($out);proof_sha256=Sha $out;status=$status;observed_utc=$proof.observed_utc}|ConvertTo-Json -Depth 5));WriteUtf8 ($receipt+'.sha256') ((Sha $receipt)+'  '+[IO.Path]::GetFileName($receipt)+"`n")
Write-Output $out
