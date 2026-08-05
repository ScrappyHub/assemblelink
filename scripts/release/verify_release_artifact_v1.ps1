param([Parameter(Mandatory=$true)][string]$ArtifactPath,[string]$ExpectedSha256='')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(-not(Test-Path -LiteralPath $ArtifactPath -PathType Leaf)){throw"RELEASE_ARTIFACT_MISSING: $ArtifactPath"}
$resolved=(Resolve-Path -LiteralPath $ArtifactPath).Path;$hash=(Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
if($ExpectedSha256-and$ExpectedSha256-notmatch'^[A-Fa-f0-9]{64}$'){throw'EXPECTED_SHA256_INVALID'}
if($ExpectedSha256-and$hash-ne$ExpectedSha256.ToLowerInvariant()){throw'RELEASE_ARTIFACT_HASH_MISMATCH'}
$signature=Get-AuthenticodeSignature -LiteralPath $resolved
if($signature.Status-ne'Valid'){throw"RELEASE_ARTIFACT_SIGNATURE_INVALID: $($signature.Status)"}
if($null-eq$signature.SignerCertificate){throw'RELEASE_ARTIFACT_SIGNER_MISSING'}
if($null-eq$signature.TimeStamperCertificate){throw'RELEASE_ARTIFACT_TRUSTED_TIMESTAMP_MISSING'}
[ordered]@{schema='assemblelink.release_artifact_verification.v1';artifact=[IO.Path]::GetFileName($resolved);sha256=$hash;bytes=(Get-Item -LiteralPath $resolved).Length;signature_status=[string]$signature.Status;signer_subject=[string]$signature.SignerCertificate.Subject;signer_thumbprint=[string]$signature.SignerCertificate.Thumbprint;timestamp_subject=[string]$signature.TimeStamperCertificate.Subject;verified_utc=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Depth 5
