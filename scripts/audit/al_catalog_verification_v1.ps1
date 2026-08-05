param([string]$RepoRoot='C:\dev\assemblelink',[switch]$Live,[ValidateRange(5,120)][int]$TimeoutSec=30)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function InvokeWingetShow([string]$Executable,[string]$Id,[int]$Seconds){
  $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$Executable;$psi.Arguments="show --id $Id --exact --source winget --accept-source-agreements --disable-interactivity";$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $proc=New-Object Diagnostics.Process;$proc.StartInfo=$psi;if(-not$proc.Start()){return [pscustomobject]@{status='start_failed';exit_code=$null;detail='process did not start'}}
  $stdout=$proc.StandardOutput.ReadToEndAsync();$stderr=$proc.StandardError.ReadToEndAsync();$finished=$proc.WaitForExit($Seconds*1000)
  if(-not$finished){try{$proc.Kill()}catch{};$proc.WaitForExit();return [pscustomobject]@{status='timeout';exit_code=$null;detail="exceeded ${Seconds}s"}}
  $text=($stdout.Result+"`n"+$stderr.Result).Trim();$verified=$proc.ExitCode-eq0-and$text-match[regex]::Escape($Id)
  [pscustomobject]@{status=$(if($verified){'verified'}else{'not_verified'});exit_code=$proc.ExitCode;detail=($text-replace'[\x00-\x1f\x7f]',' ').Substring(0,[Math]::Min(1000,($text-replace'[\x00-\x1f\x7f]',' ').Length))}
}
$catalog=Get-Content (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Raw|ConvertFrom-Json
$ids=@{};$wingetIds=@{};$aliases=@{};$liveResults=@()
function Norm([string]$v){(($v.ToLowerInvariant()-replace'[^a-z0-9]+',' ').Trim()-replace'\s+',' ')}
foreach($x in @($catalog.items)){
  if($ids.ContainsKey([string]$x.id)){throw "DUPLICATE_ID: $($x.id)"};$ids[[string]$x.id]=$true
  if([string]::IsNullOrWhiteSpace([string]$x.name)){throw "EMPTY_NAME: $($x.id)"}
  if([string]::IsNullOrWhiteSpace([string]$x.category)){throw "EMPTY_CATEGORY: $($x.id)"}
  if(-not($x.PSObject.Properties.Name-contains'admin_required')){throw "ADMIN_POLICY_MISSING: $($x.id)"}
  if(-not($x.PSObject.Properties.Name-contains'reboot_required')){throw "REBOOT_POLICY_MISSING: $($x.id)"}
  if($x.source-eq'official_or_winget'){
    $wid=[string]$x.winget_id;if($wid-notmatch'^[A-Za-z0-9][A-Za-z0-9+_.-]+$'){throw "INVALID_WINGET_ID: $($x.id)"}
    if($wingetIds.ContainsKey($wid.ToLowerInvariant())){throw "DUPLICATE_WINGET_ID: $wid"};$wingetIds[$wid.ToLowerInvariant()]=$true
  }
  elseif($x.source-eq'official_manual'){
    if(-not[string]::IsNullOrWhiteSpace([string]$x.winget_id)){throw "MANUAL_SOURCE_HAS_PACKAGE_ID: $($x.id)"}
    if([string]$x.official_url-notmatch'^https://[A-Za-z0-9.-]+(?:/|$)'){throw "INVALID_OFFICIAL_URL: $($x.id)"}
    if([string]::IsNullOrWhiteSpace([string]$x.verification)){throw "MANUAL_SOURCE_VERIFICATION_REQUIRED: $($x.id)"}
  }
  elseif($x.source-eq'official_release'){
    if(-not[string]::IsNullOrWhiteSpace([string]$x.winget_id)){throw "OFFICIAL_RELEASE_HAS_PACKAGE_ID: $($x.id)"}
    if(-not($x.PSObject.Properties.Name-contains'version_provider')){throw "OFFICIAL_RELEASE_PROVIDER_REQUIRED: $($x.id)"}
  }
  else{throw "UNKNOWN_SOURCE_POLICY: $($x.id)"}
  foreach($name in @([string]$x.name)+@($(if($x.PSObject.Properties.Name-contains'detection_names'){$x.detection_names}else{@()}))){$key=Norm $name;if($aliases.ContainsKey($key)-and$aliases[$key]-ne$x.id){throw "AMBIGUOUS_ALIAS: $name"};$aliases[$key]=[string]$x.id}
  if($x.PSObject.Properties.Name-contains'version_provider'){
    if($x.version_provider.type-ne'github_release'){throw "UNKNOWN_VERSION_PROVIDER: $($x.id)"}
    foreach($field in 'owner','repo'){if([string]::IsNullOrWhiteSpace([string]$x.version_provider.$field)-or[string]$x.version_provider.$field-notmatch'^[A-Za-z0-9_.-]+$'){throw "INVALID_PROVIDER_IDENTITY: $($x.id)"}}
  }
}
if($Live){
  $winget=Get-Command winget.exe -ErrorAction SilentlyContinue;if(-not $winget){throw 'LIVE_CATALOG_VERIFICATION_REQUIRES_WINGET'}
  foreach($x in @($catalog.items|Where-Object winget_id)){$probe=InvokeWingetShow $winget.Source ([string]$x.winget_id) $TimeoutSec;$liveResults+=[pscustomobject]@{id=[string]$x.id;winget_id=[string]$x.winget_id;verified=($probe.status-eq'verified');status=$probe.status;exit_code=$probe.exit_code;detail=$probe.detail}}
}
$failed=@($liveResults|Where-Object{-not$_.verified});$result=[ordered]@{schema='assemblelink.catalog_verification.v1';observed_utc=(Get-Date).ToUniversalTime().ToString('o');catalog_items=$ids.Count;unique_winget_ids=$wingetIds.Count;unique_detection_aliases=$aliases.Count;live=$Live.IsPresent;live_attempted=$liveResults.Count;live_verified=@($liveResults|Where-Object verified).Count;live_failed=$failed.Count;results=$liveResults}
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss');$stateDir=Join-Path $RepoRoot 'state';$receiptDir=Join-Path $RepoRoot 'proofs\receipts';$state=Join-Path $stateDir "catalog_verification.$stamp.json";$latest=Join-Path $stateDir $(if($Live){'catalog_verification.live.latest.json'}else{'catalog_verification.static.latest.json'});$json=$result|ConvertTo-Json -Depth 8;WriteUtf8 $state $json;WriteUtf8 "$state.sha256" ((Sha $state)+'  '+[IO.Path]::GetFileName($state)+"`n");WriteUtf8 $latest $json;WriteUtf8 "$latest.sha256" ((Sha $latest)+'  '+[IO.Path]::GetFileName($latest)+"`n")
$receipt=Join-Path $receiptDir "assemblelink.catalog_verification_receipt.$stamp.json";WriteUtf8 $receipt (([ordered]@{schema='assemblelink.catalog_verification_receipt.v1';observed_utc=$result.observed_utc;state=[IO.Path]::GetFileName($state);state_sha256=Sha $state;live=$Live.IsPresent;verified=$result.live_verified;failed=$result.live_failed}|ConvertTo-Json -Depth 5));WriteUtf8 "$receipt.sha256" ((Sha $receipt)+'  '+[IO.Path]::GetFileName($receipt)+"`n")
$display=[ordered]@{schema=$result.schema;observed_utc=$result.observed_utc;catalog_items=$result.catalog_items;unique_winget_ids=$result.unique_winget_ids;unique_detection_aliases=$result.unique_detection_aliases;live=$result.live;live_attempted=$result.live_attempted;live_verified=$result.live_verified;live_failed=$result.live_failed;state=$state};Write-Output ($display|ConvertTo-Json -Depth 4);if($failed.Count){throw "LIVE_CATALOG_VERIFICATION_FAILED: $($failed.Count); state=$state"}
