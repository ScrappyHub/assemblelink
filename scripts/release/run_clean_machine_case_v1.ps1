param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$CaseId,
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [switch]$Execute,
  [switch]$ConfirmEnvironment
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Check([string]$Name,[bool]$Passed,$Value=$null){$script:result.checks+=@{name=$Name;passed=$Passed;value=$Value}}
function FindInstalledApp {
  $keys=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $entry=Get-ItemProperty $keys -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName-eq'AssembleLink'}|Select-Object -First 1
  if($entry){$location=[string]$entry.InstallLocation;if(-not$location-and$entry.DisplayIcon){$location=Split-Path -Parent (([string]$entry.DisplayIcon)-replace',\d+$','').Trim('"')};if($location){return [pscustomobject]@{directory=$location;executable=(Join-Path $location 'assemblelink.exe');uninstaller=(Join-Path $location 'uninstall.exe')}}}
  $fallback=Join-Path $env:LOCALAPPDATA 'AssembleLink';[pscustomobject]@{directory=$fallback;executable=(Join-Path $fallback 'assemblelink.exe');uninstaller=(Join-Path $fallback 'uninstall.exe')}
}
function Finish([string]$Outcome){
  $script:result.outcome=$Outcome;$script:result.completed_utc=(Get-Date).ToUniversalTime().ToString('o');$dir=Join-Path $RepoRoot 'proofs\clean-machine';$path=Join-Path $dir ("$CaseId.$((Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')).json");WriteUtf8 $path ($script:result|ConvertTo-Json -Depth 12);WriteUtf8 "$path.sha256" ((Sha $path)+'  '+[IO.Path]::GetFileName($path)+"`n");Write-Output $path
}

$matrix=Get-Content (Join-Path $RepoRoot 'tests\clean_machine_matrix.v1.json') -Raw|ConvertFrom-Json;$case=$matrix.cases|Where-Object{$_.id-eq$CaseId}|Select-Object -First 1
if(-not$case){throw "UNKNOWN_CLEAN_MACHINE_CASE: $CaseId"};if(-not(Test-Path -LiteralPath $InstallerPath -PathType Leaf)){throw 'INSTALLER_MISSING'}
$installer=(Resolve-Path -LiteralPath $InstallerPath).Path;$hash=Sha $installer;$signature=Get-AuthenticodeSignature -LiteralPath $installer
$script:result=[ordered]@{schema='assemblelink.clean_machine_result.v1';case_id=$CaseId;expected=[string]$case.expected;started_utc=(Get-Date).ToUniversalTime().ToString('o');host=[ordered]@{os=[Environment]::OSVersion.VersionString;build=[Environment]::OSVersion.Version.Build;arch=$env:PROCESSOR_ARCHITECTURE;user=$env:USERNAME};installer_sha256=$hash;authenticode_status=[string]$signature.Status;signer_thumbprint=$(if($signature.SignerCertificate){$signature.SignerCertificate.Thumbprint}else{''});timestamp_present=[bool]$signature.TimeStamperCertificate;executed=$false;checks=@();outcome='not_run'}
$sidecar="$installer.sha256";$sidecarHash=if(Test-Path -LiteralPath $sidecar){((Get-Content -LiteralPath $sidecar -Raw)-split'\s+')[0].ToLowerInvariant()}else{''};Check 'installer_sha256_sidecar' ($sidecarHash-eq$hash) $sidecarHash
if($case.expected-eq'release_gate_failure'){Check 'invalid_signature_rejected' ($signature.Status-ne'Valid') ([string]$signature.Status);Finish $(if($signature.Status-ne'Valid'){'passed'}else{'failed'});return}
Check 'authenticode_valid' ($signature.Status-eq'Valid') ([string]$signature.Status);Check 'trusted_timestamp_present' ([bool]$signature.TimeStamperCertificate) $(if($signature.TimeStamperCertificate){$signature.TimeStamperCertificate.Subject}else{''})
if($signature.Status-ne'Valid'){Finish 'blocked_unsigned_installer';return}
if(-not$Execute){Check 'explicit_execution_required' $true;Finish 'ready';return}
if(-not$ConfirmEnvironment){Check 'controlled_environment_confirmed' $false 'Pass -ConfirmEnvironment only inside the matching disposable test machine';Finish 'blocked_environment_confirmation';return}

$build=[Environment]::OSVersion.Version.Build;$osMatch=if([string]$case.os-like'Windows 11*'){$build-ge22000}else{$build-lt22000};$archMatch=$case.arch-eq'x64'-and$env:PROCESSOR_ARCHITECTURE-eq'AMD64';$wingetPresent=[bool](Get-Command winget.exe -ErrorAction SilentlyContinue);$wingetMatch=($case.winget-eq'present'-and$wingetPresent)-or($case.winget-eq'missing'-and-not$wingetPresent)
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent());$elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);$userMatch=($case.user-eq'administrator'-and$elevated)-or($case.user-eq'standard'-and-not$elevated)
Check 'host_os_matches_case' $osMatch $case.os;Check 'host_arch_matches_case' $archMatch $case.arch;Check 'host_user_matches_case' $userMatch $case.user;Check 'host_winget_matches_case' $wingetMatch $case.winget;Check 'network_fixture_operator_confirmed' $true $case.network
$environmentMatch=$osMatch-and$archMatch-and$userMatch-and$wingetMatch;Check 'environment_match' $environmentMatch ([ordered]@{os=$case.os;arch=$case.arch;user=$case.user;winget=$case.winget;network=$case.network})
if(@($result.checks|Where-Object{-not$_.passed}).Count){Finish 'blocked_environment_mismatch';return}

$result.executed=$true;$proc=Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden;Check 'installer_exit_zero' ($proc.ExitCode-eq0) $proc.ExitCode
$installed=FindInstalledApp;$app=$installed.executable;Check 'application_present' (Test-Path -LiteralPath $app -PathType Leaf) $app
$runtimeStartedUtc=$null
if(Test-Path -LiteralPath $app){$appSig=Get-AuthenticodeSignature -LiteralPath $app;Check 'installed_app_authenticode_valid' ($appSig.Status-eq'Valid') ([string]$appSig.Status);Check 'installed_app_signer_matches_installer' ($appSig.SignerCertificate-and$signature.SignerCertificate-and$appSig.SignerCertificate.Thumbprint-eq$signature.SignerCertificate.Thumbprint) $(if($appSig.SignerCertificate){$appSig.SignerCertificate.Thumbprint}else{''});$runtimeStartedUtc=(Get-Date).ToUniversalTime();$smoke=Start-Process -FilePath $app -WindowStyle Hidden -PassThru;Start-Sleep -Seconds 3;$alive=-not$smoke.HasExited;Check 'desktop_runtime_startup' $alive;if($alive){$assuranceDir=Join-Path $env:LOCALAPPDATA 'com.atlassystems.assemblelink\runtime\proofs\receipts';for($wait=0;$wait-lt27;$wait++){if(Get-ChildItem -LiteralPath $assuranceDir -Filter 'assemblelink.workstation_assurance.*.json' -File -ErrorAction SilentlyContinue|Where-Object{$_.LastWriteTimeUtc-ge$runtimeStartedUtc}|Select-Object -First 1){break};Start-Sleep -Seconds 1};Stop-Process -Id $smoke.Id -Force}}
$runtime=Join-Path $env:LOCALAPPDATA 'com.atlassystems.assemblelink\runtime';$engine=Join-Path $runtime 'scripts\engine\al_software_intelligence_v1.ps1';Check 'trusted_runtime_seeded' (Test-Path -LiteralPath $engine -PathType Leaf) $engine
if(Test-Path -LiteralPath $engine){$state=&$engine -RepoRoot $runtime|Select-Object -Last 1;$observation=Get-Content -LiteralPath $state -Raw|ConvertFrom-Json;Check 'live_inventory_schema' ($observation.schema-eq'assemblelink.software_intelligence.v1') $observation.summary}
$assuranceReceipt=Get-ChildItem (Join-Path $runtime 'proofs\receipts') -Filter 'assemblelink.workstation_assurance.*.json' -File -ErrorAction SilentlyContinue|Where-Object{$null-ne$runtimeStartedUtc-and$_.LastWriteTimeUtc-ge$runtimeStartedUtc}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
if($assuranceReceipt){$assuranceSide=$assuranceReceipt.FullName+'.sha256';$expected=if(Test-Path -LiteralPath $assuranceSide){((Get-Content -LiteralPath $assuranceSide -Raw)-split'\s+')[0].ToLowerInvariant()}else{''};Check 'workstation_assurance_receipt_sha256' ($expected-eq(Sha $assuranceReceipt.FullName)) $assuranceReceipt.Name}else{Check 'workstation_assurance_receipt_sha256' $false 'assurance receipt missing'}
if($case.expected-eq'app_removed_user_evidence_preserved'){$evidence=Join-Path $runtime 'proofs\receipts';$before=@(Get-ChildItem $evidence -File -ErrorAction SilentlyContinue).Count;if(Test-Path -LiteralPath $installed.uninstaller){$uninstall=Start-Process -FilePath $installed.uninstaller -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden;Check 'uninstaller_exit_zero' ($uninstall.ExitCode-eq0) $uninstall.ExitCode;Check 'application_removed' (-not(Test-Path -LiteralPath $app));$after=@(Get-ChildItem $evidence -File -ErrorAction SilentlyContinue).Count;Check 'user_evidence_preserved' ($before-gt0-and$after-ge$before) "$before->$after"}else{Check 'uninstaller_present' $false $installed.uninstaller}}
Check 'post_install_identity_verification' (-not@($result.checks|Where-Object{$_.name-in@('application_present','installed_app_authenticode_valid','installed_app_signer_matches_installer','live_inventory_schema')-and-not$_.passed}).Count)
Finish $(if(@($result.checks|Where-Object{-not$_.passed}).Count){'failed'}else{'passed'})
