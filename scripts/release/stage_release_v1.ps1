param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [string]$OutputRoot='',
  [switch]$Draft,
  [switch]$AllowUnsignedDevelopmentCandidate
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
function WriteUtf8([string]$Path,[string]$Text){EnsureDir (Split-Path -Parent $Path);[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
if(-not(Test-Path -LiteralPath $InstallerPath -PathType Leaf)){throw'RELEASE_INSTALLER_MISSING'}
$tauri=Get-Content -LiteralPath (Join-Path $RepoRoot 'ui\src-tauri\tauri.conf.json') -Raw|ConvertFrom-Json;$package=Get-Content -LiteralPath (Join-Path $RepoRoot 'ui\package.json') -Raw|ConvertFrom-Json
if([string]$tauri.version-ne$Version-or[string]$package.version-ne$Version){throw'RELEASE_VERSION_MISMATCH'}
$installer=(Resolve-Path -LiteralPath $InstallerPath).Path;$sourceHash=Sha $installer;$sourceSide=$installer+'.sha256';if(-not(Test-Path -LiteralPath $sourceSide)){throw'RELEASE_INSTALLER_SIDECAR_MISSING'};$sideHash=((Get-Content -LiteralPath $sourceSide -Raw)-split'\s+')[0].ToLowerInvariant();if($sourceHash-ne$sideHash){throw'RELEASE_INSTALLER_SIDECAR_MISMATCH'}
$signature=Get-AuthenticodeSignature -LiteralPath $installer;$signed=$signature.Status-eq'Valid'-and$null-ne$signature.SignerCertificate;$timestamped=$null-ne$signature.TimeStamperCertificate
if((-not$signed-or-not$timestamped)-and-not$AllowUnsignedDevelopmentCandidate){throw"RELEASE_SIGNING_GATE_FAILED: $($signature.Status)"}
$matrixPath=Join-Path $RepoRoot 'state\clean_machine_matrix_status.latest.json';if(-not(Test-Path -LiteralPath $matrixPath)){throw'RELEASE_MATRIX_STATUS_MISSING'};$matrixSide=$matrixPath+'.sha256';if(-not(Test-Path -LiteralPath $matrixSide)-or((Get-Content -LiteralPath $matrixSide -Raw)-split'\s+')[0].ToLowerInvariant() -ne (Sha $matrixPath)){throw'RELEASE_MATRIX_STATUS_INTEGRITY_FAILED'};$matrix=Get-Content -LiteralPath $matrixPath -Raw|ConvertFrom-Json
if(-not[bool]$matrix.release_ready-and-not$Draft-and-not$AllowUnsignedDevelopmentCandidate){throw'RELEASE_CLEAN_MACHINE_MATRIX_INCOMPLETE'}
$kind=if(-not$signed-or-not$timestamped){'unsigned_development'}elseif(-not[bool]$matrix.release_ready){'signed_draft'}else{'production'};$releaseEligible=$kind-eq'production'
if(-not$OutputRoot){$OutputRoot=Join-Path $RepoRoot "release\out\v$Version"};EnsureDir $OutputRoot
$assetName=if($kind-eq'unsigned_development'){"AssembleLink-$Version-windows-x64-setup-UNSIGNED-DEVELOPMENT.exe"}else{"AssembleLink-$Version-windows-x64-setup.exe"};$asset=Join-Path $OutputRoot $assetName;Copy-Item -LiteralPath $installer -Destination $asset -Force;$assetHash=Sha $asset
$notesSource=Join-Path $RepoRoot "release\RELEASE_NOTES_v$Version.md";if(Test-Path -LiteralPath $notesSource){Copy-Item -LiteralPath $notesSource -Destination (Join-Path $OutputRoot 'RELEASE_NOTES.md') -Force}
$manifest=[ordered]@{schema='assemblelink.release_manifest.v1';version=$Version;channel=$kind;release_eligible=$releaseEligible;created_utc=(Get-Date).ToUniversalTime().ToString('o');platform='windows';architecture='x64';installer=[ordered]@{file=$assetName;sha256=$assetHash;bytes=(Get-Item -LiteralPath $asset).Length;authenticode_status=[string]$signature.Status;signer_thumbprint=$(if($signature.SignerCertificate){[string]$signature.SignerCertificate.Thumbprint}else{''});trusted_timestamp_present=$timestamped};clean_machine_matrix=[ordered]@{release_ready=[bool]$matrix.release_ready;passed=[int]$matrix.summary.passed;total=[int]$matrix.summary.total;state_sha256=Sha $matrixPath};limitations=@($(if(-not$signed){'Installer is not Authenticode signed.'}),$(if(-not$timestamped){'Installer has no trusted timestamp.'}),$(if(-not[bool]$matrix.release_ready){'Controlled clean-machine matrix is incomplete.'}))}
$manifestPath=Join-Path $OutputRoot 'release-manifest.v1.json';WriteUtf8 $manifestPath ($manifest|ConvertTo-Json -Depth 8);WriteUtf8 ($manifestPath+'.sha256') ((Sha $manifestPath)+'  '+[IO.Path]::GetFileName($manifestPath)+"`n");WriteUtf8 (Join-Path $OutputRoot 'SHA256SUMS.txt') ($assetHash+'  '+$assetName+"`n"+(Sha $manifestPath)+'  '+[IO.Path]::GetFileName($manifestPath)+"`n")
Write-Output $manifestPath
