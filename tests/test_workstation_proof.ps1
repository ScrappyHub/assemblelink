param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Seal([string]$Path){WriteUtf8 ($Path+'.sha256') (((Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant())+'  '+[IO.Path]::GetFileName($Path)+"`n")}
$root=Join-Path $env:TEMP ('assemblelink-workstation-proof-'+[guid]::NewGuid().ToString('n'))
try{
  New-Item -ItemType Directory -Force (Join-Path $root 'state'),(Join-Path $root 'proofs\receipts'),(Join-Path $root 'ui\src-tauri\target\release\bundle\nsis'),(Join-Path $root 'ui\src-tauri\target\release')|Out-Null
  $sys=Join-Path $root 'state\system_profile.latest.json';WriteUtf8 $sys '{"schema":"assemblelink.system_profile.v2","observation_status":"complete","machine":{"name":"fixture"},"os":{"caption":"Windows","build":"1","architecture":"64-bit"},"cpu":{"name":"CPU","cores":8,"logical_processors":16},"memory":{"total_gb":32},"gpu":[{"name":"GPU","vram_gb":0,"vram_source":"wmi_32bit_limit","vram_confidence":"unknown"}],"storage":{"total_gb":1000,"free_gb":100,"drives":[{"drive":"C:","free_gb":5,"free_percent":5}]}}';Seal $sys
  $drv=Join-Path $root 'state\driver_profile.latest.json';WriteUtf8 $drv '{"schema":"assemblelink.driver_profile.v2","observation_status":"complete","recommendations":[]}';Seal $drv
  $health=Join-Path $root 'state\workstation_health.latest.json';WriteUtf8 $health '{"schema":"assemblelink.workstation_health.v1","score":77,"areas":[{"score":97}]}'
  $cap=Join-Path $root 'state\capability_status_index.latest.json';WriteUtf8 $cap '{"schema":"assemblelink.capability_status_index.v1"}'
  $catalog=Join-Path $root 'state\catalog_verification.live.latest.json';WriteUtf8 $catalog '{"schema":"assemblelink.catalog_verification.v1","live":true,"catalog_items":72,"live_verified":70,"live_failed":0}';Seal $catalog
  $software=Join-Path $root 'state\software_intelligence.fixture.json';WriteUtf8 $software '{"schema":"assemblelink.software_intelligence.v1","evidence_mode":"live","summary":{"detected":10,"catalog_matched":5,"unmatched":5,"updates_available":0,"unknown":2}}';Seal $software
  $receipt=Join-Path $root 'proofs\receipts\assemblelink.software_intelligence_receipt.fixture.json';WriteUtf8 $receipt (([ordered]@{schema='assemblelink.software_intelligence_receipt.v1';state=$software;sha256=(Get-FileHash $software -Algorithm SHA256).Hash.ToLowerInvariant()}|ConvertTo-Json));Seal $receipt
  $installer=Join-Path $root 'ui\src-tauri\target\release\bundle\nsis\AssembleLink_0.1.0_x64-setup.exe';WriteUtf8 $installer 'fixture installer';Seal $installer
  $runtime=Join-Path $root 'ui\src-tauri\target\release\assemblelink.exe';WriteUtf8 $runtime 'fixture runtime'
  $runtimeDir=Join-Path $root 'proofs\runtime';New-Item -ItemType Directory -Force $runtimeDir|Out-Null;$runtimeSmoke=Join-Path $runtimeDir 'assemblelink.runtime_smoke.fixture.json';WriteUtf8 $runtimeSmoke (([ordered]@{schema='assemblelink.runtime_smoke.v1';runtime_sha256=(Get-FileHash $runtime -Algorithm SHA256).Hash.ToLowerInvariant();alive_after_wait=$true;status='passed'}|ConvertTo-Json));Seal $runtimeSmoke
  $proof=& (Join-Path $RepoRoot 'scripts\audit\al_workstation_proof_v1.ps1') -RepoRoot $root -InstallerPath $installer -RuntimePath $runtime|Select-Object -Last 1
  $body=Get-Content $proof -Raw|ConvertFrom-Json;if($body.schema-ne'assemblelink.workstation_proof.v1'-or$body.status-ne'verified_with_release_blocker'){throw'WORKSTATION_PROOF_POSITIVE_FAILED'}
  if($body.workstation.gpu_vram.status-ne'unknown'-or$null-ne$body.workstation.gpu_vram.gb){throw'WORKSTATION_PROOF_VRAM_FALSE_CLAIM'}
  $healthSource=Get-Content (Join-Path $RepoRoot 'scripts\engine\al_workstation_health_v1.ps1') -Raw;if($healthSource-notmatch"vramObserved"-or$healthSource-notmatch"VRAM capacity is unknown"){throw'WORKSTATION_HEALTH_VRAM_CONFIDENCE_NOT_ENFORCED'}
  $expected=((Get-Content ($proof+'.sha256') -Raw)-split'\s+')[0];if($expected-ne(Get-FileHash $proof -Algorithm SHA256).Hash.ToLowerInvariant()){throw'WORKSTATION_PROOF_OUTPUT_HASH_INVALID'}
  WriteUtf8 $sys '{"tampered":true}';$rejected=$false;try{& (Join-Path $RepoRoot 'scripts\audit\al_workstation_proof_v1.ps1') -RepoRoot $root -InstallerPath $installer -RuntimePath $runtime|Out-Null}catch{$rejected=$_.Exception.Message-like'WORKSTATION_PROOF_HASH_MISMATCH*'};if(-not$rejected){throw'WORKSTATION_PROOF_TAMPER_NOT_REJECTED'}
  Write-Host 'ASSEMBLELINK_WORKSTATION_PROOF_TEST_OK' -ForegroundColor Green
}finally{if(Test-Path $root){$resolved=(Resolve-Path $root).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
