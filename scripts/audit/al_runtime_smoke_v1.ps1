param([string]$RepoRoot='C:\dev\assemblelink',[string]$RuntimePath='',[ValidateRange(5,30)][int]$WaitSeconds=10)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function EnsureDir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){New-Item -ItemType Directory -Force -Path $Path|Out-Null}}
function WriteUtf8([string]$Path,[string]$Text){EnsureDir (Split-Path -Parent $Path);$normalized=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$normalized.EndsWith("`n")){$normalized+="`n"};[IO.File]::WriteAllText($Path,$normalized,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path;if([string]::IsNullOrWhiteSpace($RuntimePath)){$RuntimePath=Join-Path $RepoRoot 'ui\src-tauri\target\release\assemblelink.exe'}
if(-not(Test-Path -LiteralPath $RuntimePath -PathType Leaf)){throw'RUNTIME_SMOKE_BINARY_MISSING'}
$started=(Get-Date).ToUniversalTime();$process=$null;$alive=$false;$exitCode=$null
try{$process=Start-Process -FilePath $RuntimePath -WindowStyle Hidden -PassThru;Start-Sleep -Seconds $WaitSeconds;$alive=-not$process.HasExited;if($process.HasExited){$exitCode=$process.ExitCode}}finally{if($process-and-not$process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}}
$signature=Get-AuthenticodeSignature -LiteralPath $RuntimePath;$result=[ordered]@{schema='assemblelink.runtime_smoke.v1';observed_utc=(Get-Date).ToUniversalTime().ToString('o');runtime_sha256=Sha $RuntimePath;wait_seconds=$WaitSeconds;started=$null-ne$process;alive_after_wait=$alive;exit_code=$exitCode;signature_status=[string]$signature.Status;status=$(if($alive){'passed'}else{'failed'})}
$dir=Join-Path $RepoRoot 'proofs\runtime';EnsureDir $dir;$stamp=$started.ToString('yyyyMMdd_HHmmss');$out=Join-Path $dir "assemblelink.runtime_smoke.$stamp.json";WriteUtf8 $out ($result|ConvertTo-Json -Depth 6);WriteUtf8 ($out+'.sha256') ((Sha $out)+'  '+[IO.Path]::GetFileName($out)+"`n");Write-Output $out;if(-not$alive){throw"RUNTIME_SMOKE_FAILED: $out"}
