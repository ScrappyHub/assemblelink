param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Join-Path $env:TEMP ('assemblelink-driver-test-'+[guid]::NewGuid().ToString('n'))
try{
  $script=Join-Path $RepoRoot 'scripts\commands\al_driver_profile_v1.ps1';$fixture=Join-Path $RepoRoot 'tests\fixtures\driver-profile.valid.json'
  $first=&$script -RepoRoot $root -FixturePath $fixture|Select-Object -Last 1;$second=&$script -RepoRoot $root -FixturePath $fixture|Select-Object -Last 1
  if($first-eq$second-or-not(Test-Path $first)-or-not(Test-Path $second)){throw 'DRIVER_EVIDENCE_NOT_APPEND_ONLY'}
  $profile=Get-Content $second -Raw|ConvertFrom-Json;if($profile.schema-ne'assemblelink.driver_profile.v2'){throw 'DRIVER_SCHEMA_INVALID'}
  if($profile.safety_policy.driver_auto_install_allowed-or$profile.safety_policy.default_install_mode-ne'recommend_only'){throw 'DRIVER_AUTOMATION_POLICY_UNSAFE'}
  if(@($profile.graphics).Count-ne1-or@($profile.network).Count-ne1-or@($profile.audio).Count-ne1){throw 'DRIVER_FIXTURE_INVENTORY_INCOMPLETE'}
  if(@($profile.recommendations).Count-lt5-or@($profile.recommendations|Where-Object{$_.install_mode-ne'recommend_only'-or$_.update_status-ne'not_checked'}).Count){throw 'DRIVER_RECOMMENDATION_POLICY_UNSAFE'}
  $raw=Get-Content $second -Raw;if($raw-match'(?i)mac_address|"mac"'){throw 'DRIVER_PROFILE_EXPOSES_MAC'}
  foreach($path in @($first,$second,(Join-Path $root 'state\driver_profile.latest.json'))){$side="$path.sha256";if(-not(Test-Path $side)){throw "DRIVER_HASH_MISSING: $path"};$expected=((Get-Content $side -Raw)-split'\s+')[0];$actual=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();if($expected-ne$actual){throw "DRIVER_HASH_MISMATCH: $path"}}
  $receipts=@(Get-ChildItem (Join-Path $root 'proofs\receipts') -Filter '*.json');if($receipts.Count-ne2){throw 'DRIVER_RECEIPT_COUNT_INVALID'};foreach($receipt in $receipts){$side=$receipt.FullName+'.sha256';$expected=((Get-Content $side -Raw)-split'\s+')[0];$actual=(Get-FileHash $receipt.FullName -Algorithm SHA256).Hash.ToLowerInvariant();if($expected-ne$actual){throw 'DRIVER_RECEIPT_HASH_MISMATCH'}}
  Write-Host 'ASSEMBLELINK_DRIVER_PROFILE_TEST_OK' -ForegroundColor Green
}finally{
  if(Test-Path $root){$resolved=(Resolve-Path $root).Path;$temp=[IO.Path]::GetFullPath($env:TEMP);if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}
}
