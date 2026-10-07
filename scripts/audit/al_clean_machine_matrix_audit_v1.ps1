param([string]$RepoRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
function WriteUtf8([string]$Path,[string]$Text){EnsureDir (Split-Path -Parent $Path);[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Seal([string]$Path){WriteUtf8 "$Path.sha256" ((Sha $Path)+'  '+[IO.Path]::GetFileName($Path)+"`n")}

$matrixPath=Join-Path $RepoRoot 'tests\clean_machine_matrix.v1.json'
if(-not(Test-Path -LiteralPath $matrixPath -PathType Leaf)){throw'CLEAN_MACHINE_MATRIX_MISSING'}
$matrix=Get-Content -LiteralPath $matrixPath -Raw|ConvertFrom-Json
if($matrix.schema-ne'assemblelink.clean_machine_matrix.v1'){throw'CLEAN_MACHINE_MATRIX_SCHEMA_REJECTED'}
$proofDir=Join-Path $RepoRoot 'proofs\clean-machine';EnsureDir $proofDir
$rows=@()
foreach($case in @($matrix.cases)){
  $proof=Get-ChildItem -LiteralPath $proofDir -Filter "$($case.id).*json" -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
  $status='pending';$reason='No sealed proof has been recorded for this controlled scenario.';$proofName='';$proofHash='';$sidecarValid=$false;$outcome='not_run';$checks=@()
  if($proof){
    $proofName=$proof.Name;$proofHash=Sha $proof.FullName;$side=$proof.FullName+'.sha256';$expected=if(Test-Path -LiteralPath $side){((Get-Content -LiteralPath $side -Raw)-split'\s+')[0].ToLowerInvariant()}else{''};$sidecarValid=$expected-eq$proofHash
    try{$data=Get-Content -LiteralPath $proof.FullName -Raw|ConvertFrom-Json}catch{$data=$null}
    if(-not$sidecarValid){$status='failed';$reason='Proof sidecar is missing or does not match recomputed bytes.'}
    elseif($null-eq$data-or$data.schema-ne'assemblelink.clean_machine_result.v1'-or$data.case_id-ne$case.id){$status='failed';$reason='Proof schema or case identity is invalid.'}
    else{
      $outcome=[string]$data.outcome;$checks=@($data.checks)
      $requiredChecks=@('installer_sha256_sidecar');if($case.expected-eq'release_gate_failure'){$requiredChecks+=@('invalid_signature_rejected')}else{$requiredChecks+=@('authenticode_valid','trusted_timestamp_present','environment_match','desktop_runtime_startup','workstation_assurance_receipt_sha256','post_install_identity_verification')};if($case.expected-eq'app_removed_user_evidence_preserved'){$requiredChecks+=@('uninstaller_exit_zero','application_removed','user_evidence_preserved')}
      $failed=@($checks|Where-Object{-not$_.passed});$passedNames=@($checks|Where-Object{$_.passed}|ForEach-Object{[string]$_.name});$missing=@($requiredChecks|Where-Object{$passedNames-notcontains$_});$identityValid=([string]$data.expected-eq[string]$case.expected)-and([string]$data.installer_sha256-match'^[a-f0-9]{64}$')
      if($outcome-eq'passed'-and$failed.Count-eq0-and$missing.Count-eq0-and$identityValid){$status='passed';$reason='Latest sealed proof passed every required check.'}
      elseif($missing.Count){$status='failed';$reason='Proof is missing required checks: '+($missing-join', ')+'.'}
      elseif(-not$identityValid){$status='failed';$reason='Proof expected outcome or installer identity is invalid.'}
      elseif($outcome-like'blocked*'-or$outcome-eq'not_run'){$status='blocked';$reason="Latest proof is $outcome; the scenario is not proven."}
      else{$status='failed';$reason="Latest proof outcome is $outcome."}
    }
  }
  $rows+=[ordered]@{case_id=[string]$case.id;expected=[string]$case.expected;status=$status;reason=$reason;proof=$proofName;proof_sha256=$proofHash;sidecar_valid=$sidecarValid;outcome=$outcome;recorded_checks=@($checks|ForEach-Object{[string]$_.name})}
}
$summary=[ordered]@{total=$rows.Count;passed=@($rows|Where-Object{$_.status-eq'passed'}).Count;pending=@($rows|Where-Object{$_.status-eq'pending'}).Count;blocked=@($rows|Where-Object{$_.status-eq'blocked'}).Count;failed=@($rows|Where-Object{$_.status-eq'failed'}).Count}
$result=[ordered]@{schema='assemblelink.clean_machine_matrix_status.v1';observed_utc=(Get-Date).ToUniversalTime().ToString('o');matrix_sha256=Sha $matrixPath;release_ready=[bool]($summary.passed-eq$summary.total-and$summary.failed-eq0);summary=$summary;cases=$rows;limitations=@('A pending or blocked case is not release evidence.','This audit verifies recorded proof integrity; it does not simulate a clean machine.','Public release still requires a trusted Authenticode signature and timestamp.')}
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss_fffffff');$stateDir=Join-Path $RepoRoot 'state';$receiptDir=Join-Path $RepoRoot 'proofs\receipts';$immutable=Join-Path $stateDir "clean_machine_matrix_status.$stamp.json";$latest=Join-Path $stateDir 'clean_machine_matrix_status.latest.json';$json=$result|ConvertTo-Json -Depth 12
WriteUtf8 $immutable $json;Seal $immutable;WriteUtf8 $latest $json;Seal $latest
$receipt=Join-Path $receiptDir "assemblelink.clean_machine_matrix_audit_receipt.$stamp.json";WriteUtf8 $receipt (([ordered]@{schema='assemblelink.clean_machine_matrix_audit_receipt.v1';observed_utc=$result.observed_utc;state=[IO.Path]::GetFileName($immutable);sha256=Sha $immutable;release_ready=$result.release_ready;passed=$summary.passed;total=$summary.total}|ConvertTo-Json -Depth 5));Seal $receipt
Write-Output $immutable
