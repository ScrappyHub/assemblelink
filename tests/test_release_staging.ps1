param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$root=Join-Path $env:TEMP ('assemblelink-release-stage-'+[guid]::NewGuid().ToString('n'))
try{
  New-Item -ItemType Directory -Force (Join-Path $root 'ui\src-tauri'),(Join-Path $root 'state'),(Join-Path $root 'release')|Out-Null
  WriteUtf8 (Join-Path $root 'ui\package.json') '{"version":"0.1.0"}';WriteUtf8 (Join-Path $root 'ui\src-tauri\tauri.conf.json') '{"version":"0.1.0"}'
  $installer=Join-Path $root 'fixture.exe';WriteUtf8 $installer 'unsigned fixture';WriteUtf8 ($installer+'.sha256') ((Sha $installer)+'  fixture.exe'+"`n")
  $matrix=Join-Path $root 'state\clean_machine_matrix_status.latest.json';WriteUtf8 $matrix '{"schema":"assemblelink.clean_machine_matrix_status.v1","release_ready":false,"summary":{"passed":1,"total":12}}';WriteUtf8 ($matrix+'.sha256') ((Sha $matrix)+'  clean_machine_matrix_status.latest.json'+"`n")
  $blocked=$false;try{& (Join-Path $RepoRoot 'scripts\release\stage_release_v1.ps1') -RepoRoot $root -Version '0.1.0' -InstallerPath $installer|Out-Null}catch{if($_.Exception.Message-match'RELEASE_SIGNING_GATE_FAILED'){$blocked=$true}};if(-not$blocked){throw'UNSIGNED_RELEASE_NOT_BLOCKED'}
  $manifestPath=& (Join-Path $RepoRoot 'scripts\release\stage_release_v1.ps1') -RepoRoot $root -Version '0.1.0' -InstallerPath $installer -OutputRoot (Join-Path $root 'out') -AllowUnsignedDevelopmentCandidate|Select-Object -Last 1;$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
  if($manifest.release_eligible-or$manifest.channel-ne'unsigned_development'-or$manifest.installer.file-notmatch'UNSIGNED-DEVELOPMENT'){throw'UNSIGNED_CANDIDATE_LABEL_FAILED'}
  if((Sha $manifestPath)-ne((Get-Content -LiteralPath ($manifestPath+'.sha256') -Raw)-split'\s+')[0]){throw'RELEASE_MANIFEST_SEAL_FAILED'}
  $verifyBlocked=$false;try{& (Join-Path $RepoRoot 'scripts\release\verify_release_artifact_v1.ps1') -ArtifactPath $installer|Out-Null}catch{if($_.Exception.Message-match'RELEASE_ARTIFACT_SIGNATURE_INVALID'){$verifyBlocked=$true}};if(-not$verifyBlocked){throw'UNSIGNED_VERIFY_NOT_BLOCKED'}
  Write-Host 'ASSEMBLELINK_RELEASE_STAGING_TEST_OK'
}finally{if(Test-Path $root){$resolved=(Resolve-Path $root).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
