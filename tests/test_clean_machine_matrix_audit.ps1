param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$root=Join-Path $env:TEMP ('assemblelink-matrix-audit-'+[guid]::NewGuid().ToString('n'))
try{
  New-Item -ItemType Directory -Force (Join-Path $root 'tests'),(Join-Path $root 'proofs\clean-machine')|Out-Null
  WriteUtf8 (Join-Path $root 'tests\clean_machine_matrix.v1.json') '{"schema":"assemblelink.clean_machine_matrix.v1","required_evidence":[],"cases":[{"id":"negative","expected":"release_gate_failure"},{"id":"missing","expected":"install"}]}'
  $proof=Join-Path $root 'proofs\clean-machine\negative.20260101_000000.json';WriteUtf8 $proof '{"schema":"assemblelink.clean_machine_result.v1","case_id":"negative","expected":"release_gate_failure","installer_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","outcome":"passed","checks":[{"name":"installer_sha256_sidecar","passed":true},{"name":"invalid_signature_rejected","passed":true}]}';WriteUtf8 ($proof+'.sha256') ((Sha $proof)+'  '+[IO.Path]::GetFileName($proof)+"`n")
  $path=& (Join-Path $RepoRoot 'scripts\audit\al_clean_machine_matrix_audit_v1.ps1') -RepoRoot $root|Select-Object -Last 1;$result=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  if($result.schema-ne'assemblelink.clean_machine_matrix_status.v1'-or$result.release_ready){throw'MATRIX_STATUS_SCHEMA_OR_GATE_FAILED'}
  if($result.summary.total-ne2-or$result.summary.passed-ne1-or$result.summary.pending-ne1){throw'MATRIX_STATUS_COUNTS_FAILED'}
  if(-not(Test-Path -LiteralPath ($path+'.sha256'))-or(Sha $path)-ne((Get-Content -LiteralPath ($path+'.sha256') -Raw)-split'\s+')[0]){throw'MATRIX_STATUS_SEAL_FAILED'}
  WriteUtf8 $proof '{"schema":"assemblelink.clean_machine_result.v1","case_id":"negative","outcome":"passed","checks":[]}'
  $tampered=& (Join-Path $RepoRoot 'scripts\audit\al_clean_machine_matrix_audit_v1.ps1') -RepoRoot $root|Select-Object -Last 1;$bad=Get-Content -LiteralPath $tampered -Raw|ConvertFrom-Json;if(($bad.cases|Where-Object{$_.case_id-eq'negative'}).status-ne'failed'){throw'TAMPERED_PROOF_NOT_REJECTED'}
  Write-Host 'ASSEMBLELINK_CLEAN_MACHINE_MATRIX_AUDIT_TEST_OK'
}finally{if(Test-Path $root){$resolved=(Resolve-Path $root).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
