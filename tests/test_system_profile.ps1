param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Join-Path $env:TEMP ('assemblelink-system-test-'+[guid]::NewGuid().ToString('n'))
try{
  $script=Join-Path $RepoRoot 'scripts\commands\al_system_profile_v1.ps1';$fixture=Join-Path $RepoRoot 'tests\fixtures\system-profile.valid.json'
  $first=&$script -RepoRoot $root -FixturePath $fixture|Select-Object -Last 1;$second=&$script -RepoRoot $root -FixturePath $fixture|Select-Object -Last 1
  if($first-eq$second){throw 'SYSTEM_PROFILE_EVIDENCE_NOT_APPEND_ONLY'};$profile=Get-Content $second -Raw|ConvertFrom-Json
  if($profile.schema-ne'assemblelink.system_profile.v2'-or$profile.observation_status-ne'complete'){throw 'SYSTEM_PROFILE_SCHEMA_INVALID'}
  if($profile.memory.total_gb-ne32-or$profile.storage.total_gb-ne1024-or$profile.storage.free_gb-ne512){throw 'SYSTEM_PROFILE_CAPACITY_INCORRECT'}
  if(@($profile.gpu).Count-ne1-or$profile.gpu[0].vram_gb-ne2){throw 'SYSTEM_PROFILE_GPU_INCORRECT'}
  $source=Get-Content $script -Raw;if($source-match'nvidia-smi|Get-FileHash'){throw 'SYSTEM_PROFILE_UNTRUSTED_HELPER_PRESENT'}
  foreach($path in @($first,$second,(Join-Path $root 'state\system_profile.latest.json'))){$side=$path+'.sha256';$expected=((Get-Content $side -Raw)-split'\s+')[0];$actual=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();if($expected-ne$actual){throw 'SYSTEM_PROFILE_HASH_MISMATCH'}}
  $receipts=@(Get-ChildItem (Join-Path $root 'proofs\receipts') -Filter '*.json');if($receipts.Count-ne2){throw 'SYSTEM_PROFILE_RECEIPT_COUNT_INVALID'}
  Write-Host 'ASSEMBLELINK_SYSTEM_PROFILE_TEST_OK' -ForegroundColor Green
}finally{if(Test-Path $root){$resolved=(Resolve-Path $root).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
