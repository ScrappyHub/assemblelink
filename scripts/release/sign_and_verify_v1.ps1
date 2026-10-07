param(
  [Parameter(Mandatory=$true)][string]$ArtifactPath,
  [string]$CertificateThumbprint=$env:ASSEMBLELINK_SIGNING_CERT_THUMBPRINT,
  [string]$TimestampUrl='https://timestamp.digicert.com'
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(-not(Test-Path -LiteralPath $ArtifactPath -PathType Leaf)){throw "SIGNING_ARTIFACT_MISSING: $ArtifactPath"}
if([string]::IsNullOrWhiteSpace($CertificateThumbprint)-or$CertificateThumbprint-notmatch'^[A-Fa-f0-9]{40}$'){throw'CODE_SIGNING_CERTIFICATE_THUMBPRINT_REQUIRED'}
if($TimestampUrl-notmatch'^https://'){throw'TIMESTAMP_URL_MUST_USE_HTTPS'}
$signtool=Get-Command signtool.exe -ErrorAction SilentlyContinue
if(-not$signtool){$candidate=Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue|Where-Object FullName -match'\\x64\\'|Sort-Object FullName -Descending|Select-Object -First 1;if($candidate){$signtool=$candidate}}
if(-not$signtool){throw'SIGNTOOL_NOT_FOUND'}
$toolPath=if($signtool.PSObject.Properties.Name-contains'Source'){$signtool.Source}else{$signtool.FullName}
& $toolPath sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 /v $ArtifactPath
if($LASTEXITCODE-ne0){throw "SIGNTOOL_SIGN_FAILED: $LASTEXITCODE"}
& $toolPath verify /pa /all /v $ArtifactPath
if($LASTEXITCODE-ne0){throw "SIGNTOOL_VERIFY_FAILED: $LASTEXITCODE"}
$signature=Get-AuthenticodeSignature -LiteralPath $ArtifactPath
if($signature.Status-ne'Valid'){throw "AUTHENTICODE_INVALID: $($signature.Status)"}
$hash=(Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{schema='assemblelink.code_signing_verification.v1';artifact=(Resolve-Path -LiteralPath $ArtifactPath).Path;sha256=$hash;signature_status=[string]$signature.Status;signer_subject=[string]$signature.SignerCertificate.Subject;timestamp_subject=[string]$signature.TimeStamperCertificate.Subject}|ConvertTo-Json -Depth 5
