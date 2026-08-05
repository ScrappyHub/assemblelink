param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$InventoryFixturePath='',
  [string]$ProviderFixturePath='',
  [int]$MaxCacheAgeHours=6,
  [switch]$ForceRefresh
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest

function EnsureDir([string]$p){if(-not(Test-Path -LiteralPath $p -PathType Container)){New-Item -ItemType Directory -Force -Path $p|Out-Null}}
function WriteUtf8([string]$p,[string]$t){EnsureDir (Split-Path -Parent $p);[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$p){$stream=[IO.File]::OpenRead($p);$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}}
function Prop($o,[string]$n,[string]$fallback=''){if($o -is [Collections.IDictionary]){if($o.Contains($n)-and$null-ne$o[$n]){return [string]$o[$n]};return $fallback};$p=$o.PSObject.Properties[$n];if($null -eq $p -or $null -eq $p.Value){return $fallback};return [string]$p.Value}
function Normalize([string]$v){if([string]::IsNullOrWhiteSpace($v)){return ''};return (($v.ToLowerInvariant() -replace '[^a-z0-9]+',' ').Trim() -replace '\s+',' ')}
function ClassifyUnmatched($app){
  $name=Prop $app 'name';$normalized=Normalize $name;$publisher=Normalize (Prop $app 'publisher');$parent=Prop $app 'parent_display_name';$release=Normalize (Prop $app 'release_type');$system=Prop $app 'system_component'
  if($system-eq'1'-or-not[string]::IsNullOrWhiteSpace($parent)-or$release-match'^(update|hotfix|security update)$'){return 'system_component'}
  if($normalized-match'\b(driver|firmware|chipset)\b'-and$publisher-match'\b(nvidia|amd|intel|realtek|microsoft|asmedia|logitech)\b'){return 'driver_component'}
  if($normalized-match'\b(sdk|runtime|redistributable|templates?|toolset|targeting pack|build tools|shared framework|host fx resolver|language pack)\b'){return 'developer_component'}
  return 'application_candidate'
}
function VersionParts([string]$v){@([regex]::Matches($v,'\d+')|ForEach-Object{[int64]$_.Value})}
function CompareVersions([string]$installed,[string]$available){
  if([string]::IsNullOrWhiteSpace($installed)-or[string]::IsNullOrWhiteSpace($available)){return $null}
  $a=@(VersionParts $installed);$b=@(VersionParts $available);if($a.Count-eq 0-or$b.Count-eq 0){return $null}
  for($i=0;$i-lt[Math]::Max($a.Count,$b.Count);$i++){$av=if($i-lt$a.Count){$a[$i]}else{0};$bv=if($i-lt$b.Count){$b[$i]}else{0};if($av-lt$bv){return -1};if($av-gt$bv){return 1}}
  return 0
}
function GetRegistryInventory {
  if($InventoryFixturePath){return @(Get-Content -LiteralPath $InventoryFixturePath -Raw|ConvertFrom-Json)}
  $items=@();$roots=@('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  foreach($r in $roots){Get-ItemProperty $r -ErrorAction SilentlyContinue|Where-Object{-not[string]::IsNullOrWhiteSpace((Prop $_ 'DisplayName'))}|ForEach-Object{$items+=[pscustomobject]@{name=Prop $_ 'DisplayName';version=Prop $_ 'DisplayVersion';publisher=Prop $_ 'Publisher';source='registry_uninstall';system_component=Prop $_ 'SystemComponent';parent_display_name=Prop $_ 'ParentDisplayName';release_type=Prop $_ 'ReleaseType'}}}
  $cliProbes=[ordered]@{'git'='git.exe';'nodejs-lts'='node.exe';'python'='python.exe';'powershell'='pwsh.exe';'github-cli'='gh.exe';'rustup'='rustup.exe';'golang'='go.exe';'dotnet-sdk-8'='dotnet.exe';'temurin-jdk-21'='java.exe';'uv'='uv.exe';'terraform'='terraform.exe';'kubectl'='kubectl.exe';'helm'='helm.exe';'azure-cli'='az.exe';'aws-cli'='aws.exe';'google-cloud-cli'='gcloud.exe';'jq'='jq.exe';'yq'='yq.exe';'ripgrep'='rg.exe';'fd'='fd.exe';'bat'='bat.exe';'fzf'='fzf.exe';'cmake'='cmake.exe';'ninja'='ninja.exe';'llvm'='clang.exe';'ffmpeg'='ffmpeg.exe';'nmap'='nmap.exe';'hashcat'='hashcat.exe';'docker-desktop'='docker.exe';'podman'='podman.exe'}
  $catalogById=@{};foreach($entry in @($catalog.items)){$catalogById[[string]$entry.id]=$entry}
  foreach($id in $cliProbes.Keys){$command=Get-Command $cliProbes[$id] -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;if($command-and$catalogById.ContainsKey($id)){$version='';try{$version=[string](Get-Item -LiteralPath $command.Source).VersionInfo.ProductVersion}catch{$version=''};$items+=[pscustomobject]@{name=[string]$catalogById[$id].name;version=$version;publisher='';source='cli_file_metadata'}}}
  return @($items|Sort-Object name,version,publisher,source -Unique)
}
$script:WingetSnapshot=$null
function WingetProbe([string]$id,[string]$cacheDir){
  if($null-eq$script:WingetSnapshot){
    $script:WingetSnapshot=@{};$cache=Join-Path $cacheDir 'winget.inventory.json';$cached=$null
    if(Test-Path -LiteralPath $cache){try{$cached=Get-Content -LiteralPath $cache -Raw|ConvertFrom-Json}catch{$cached=$null}}
    if($cached-and-not$ForceRefresh-and((Get-Date).ToUniversalTime()-[datetime]$cached.checked_utc).TotalHours-le$MaxCacheAgeHours){foreach($entry in @($cached.items)){$script:WingetSnapshot[[string]$entry.id]=[ordered]@{status=[string]$entry.status;installed_version=[string]$entry.installed_version;available_version=[string]$entry.available_version;freshness='cached'}}}
    else{
      $cmd=Get-Command winget.exe -ErrorAction SilentlyContinue
      if(-not$cmd){foreach($entry in @($catalog.items|Where-Object winget_id)){$script:WingetSnapshot[[string]$entry.winget_id]=[ordered]@{status='package_manager_unavailable';installed_version='';available_version='';freshness='unknown'}}}
      else{
        $out=&$cmd.Source list --source winget --include-unknown --accept-source-agreements --disable-interactivity 2>&1;$exit=$LASTEXITCODE;$text=@($out)-join"`n";$cacheItems=@()
        foreach($entry in @($catalog.items|Where-Object winget_id)){$packageId=[string]$entry.winget_id;$probe=[ordered]@{status='not_installed';installed_version='';available_version='';freshness='live'}
          if($exit-ne0){$probe.status='provider_unavailable';$probe.freshness='unknown'}else{$line=@($text-split"`r?`n"|Where-Object{$_-match("(^|\s)"+[regex]::Escape($packageId)+"(\s|$)")}|Select-Object -Last 1);if($line.Count){$cols=@($line[0].Trim()-split'\s{2,}');$idx=[Array]::IndexOf($cols,$packageId);if($idx-lt0-or$idx+1-ge$cols.Count){$probe.status='malformed_response'}else{$probe.status='ok';$probe.installed_version=[string]$cols[$idx+1];$probe.available_version=$probe.installed_version;if($idx+2-lt$cols.Count-and$cols[$idx+2]-notin@('winget','msstore')){$probe.available_version=[string]$cols[$idx+2]}}}}
          $script:WingetSnapshot[$packageId]=$probe;$cacheItems+=[ordered]@{id=$packageId;status=$probe.status;installed_version=$probe.installed_version;available_version=$probe.available_version}
        }
        if($exit-eq0){WriteUtf8 $cache (([ordered]@{checked_utc=(Get-Date).ToUniversalTime().ToString('o');items=$cacheItems}|ConvertTo-Json -Depth 8))}
      }
    }
  }
  if($script:WingetSnapshot.ContainsKey($id)){return $script:WingetSnapshot[$id]};return [ordered]@{status='not_installed';installed_version='';available_version='';freshness='live'}
}
function GitHubReleaseProbe($provider,[string]$cacheDir){
  $owner=Prop $provider 'owner';$repo=Prop $provider 'repo';if($owner-notmatch'^[A-Za-z0-9_.-]+$'-or$repo-notmatch'^[A-Za-z0-9_.-]+$'){return [ordered]@{status='invalid_provider';available_version='';freshness='unknown'}}
  $cache=Join-Path $cacheDir ("github.$owner.$repo.json");$now=(Get-Date).ToUniversalTime();$cached=$null
  if(Test-Path -LiteralPath $cache){try{$cached=Get-Content -LiteralPath $cache -Raw|ConvertFrom-Json}catch{$cached=$null}}
  if($cached-and-not$ForceRefresh){$age=($now-[datetime]$cached.checked_utc).TotalHours;if($age-le$MaxCacheAgeHours){return [ordered]@{status='ok';available_version=[string]$cached.available_version;freshness='cached'}}}
  try{
    $headers=@{'User-Agent'='AssembleLink/0.1';'Accept'='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'};if($cached-and(Prop $cached 'etag')){$headers['If-None-Match']=[string]$cached.etag}
    $response=Invoke-WebRequest -Uri "https://api.github.com/repos/$owner/$repo/releases/latest" -Headers $headers -Method Get -TimeoutSec 15 -MaximumRedirection 0 -ErrorAction Stop
    $body=$response.Content|ConvertFrom-Json;$tag=Prop $body 'tag_name';if([string]::IsNullOrWhiteSpace($tag)){throw'MISSING_TAG_NAME'}
    $entry=[ordered]@{checked_utc=$now.ToString('o');available_version=$tag;etag=[string]$response.Headers.ETag};WriteUtf8 $cache ($entry|ConvertTo-Json -Depth 5)
    return [ordered]@{status='ok';available_version=$tag;freshness='live'}
  }catch{
    if($cached){$age=($now-[datetime]$cached.checked_utc).TotalHours;return [ordered]@{status=$(if($age-gt$MaxCacheAgeHours){'stale_cache'}else{'provider_unavailable'});available_version=[string]$cached.available_version;freshness='stale'}}
    return [ordered]@{status='provider_unavailable';available_version='';freshness='unknown'}
  }
}

$catalog=Get-Content (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Raw|ConvertFrom-Json
$fixture=$null;if($ProviderFixturePath){$fixture=Get-Content -LiteralPath $ProviderFixturePath -Raw|ConvertFrom-Json}
$aliases=@{};foreach($x in @($catalog.items)){foreach($name in @([string]$x.name)+@($(if($x.PSObject.Properties.Name-contains'detection_names'){$x.detection_names}else{@()}))){$key=Normalize $name;if($key){if($aliases.ContainsKey($key)-and$aliases[$key]-ne$x.id){throw "AMBIGUOUS_CATALOG_ALIAS: $name"};$aliases[$key]=$x.id}}}
$raw=@(GetRegistryInventory);$byCatalog=@{};$unmatched=@()
foreach($app in $raw){$key=Normalize (Prop $app 'name');if($aliases.ContainsKey($key)){$id=[string]$aliases[$key];if(-not$byCatalog.ContainsKey($id)){$byCatalog[$id]=@()};$byCatalog[$id]+=,$app}else{$unmatched+=,$app}}
$providerHealth=[ordered]@{winget=$(if(Get-Command winget.exe -ErrorAction SilentlyContinue){'available'}else{'package_manager_unavailable'});github='not_required'};$items=@();$cacheDir=Join-Path $RepoRoot 'state\provider_cache';EnsureDir $cacheDir
foreach($x in @($catalog.items|Sort-Object id)){
  $observed=@();if($byCatalog.ContainsKey([string]$x.id)){$observed=@($byCatalog[[string]$x.id])};$best=$observed|Where-Object{-not[string]::IsNullOrWhiteSpace((Prop $_ 'version'))}|Select-Object -First 1;if(-not$best-and$observed.Count){$best=$observed[0]}
  $installed=if($best){Prop $best 'version'}else{''};$publisher=if($best){Prop $best 'publisher'}else{''};$probe=[ordered]@{status='not_installed';installed_version='';available_version='';freshness='live'}
  if($null -ne $fixture){$p=$fixture.PSObject.Properties[[string]$x.id];if($null -ne $p){$probe=[ordered]@{status=(Prop $p.Value 'status' 'ok');installed_version=(Prop $p.Value 'installed_version');available_version=(Prop $p.Value 'available_version');freshness=(Prop $p.Value 'freshness' 'fixture')}}}
  elseif($x.PSObject.Properties.Name-contains'version_provider'-and$x.version_provider.type-eq'github_release'-and$observed.Count){$providerHealth.github='queried';$probe=GitHubReleaseProbe $x.version_provider $cacheDir}
  elseif(-not[string]::IsNullOrWhiteSpace([string]$x.winget_id)){$probe=WingetProbe ([string]$x.winget_id) $cacheDir}
  if(-not$installed-and(Prop $probe 'installed_version')){$installed=Prop $probe 'installed_version'}
  $available=Prop $probe 'available_version';$status='not_installed'
  if($observed.Count-or$installed){if(-not$installed){$status='installed_version_unknown'}elseif((Prop $probe 'status')-notin@('ok','not_installed')){$status='provider_unavailable'}elseif(-not$available){$status='provider_unavailable'}else{$cmp=CompareVersions $installed $available;$status=if($null-eq$cmp){'installed_version_unknown'}elseif($cmp-lt0){'update_available'}else{'current'}}}
  $items+=[ordered]@{catalog_id=[string]$x.id;winget_id=[string]$x.winget_id;name=[string]$x.name;installed=[bool]($observed.Count-or$installed);installed_version=$installed;available_version=$available;publisher=$publisher;update_status=$status;provider_status=Prop $probe 'status';freshness=Prop $probe 'freshness' 'live';match_confidence=$(if($observed.Count){'exact_alias'}else{'none'});source=$(if($observed.Count){Prop $best 'source' 'registry_uninstall'}else{'catalog'});inventory_kind='managed_application';catalog_action='managed'}
}
foreach($app in @($unmatched|Sort-Object name,version,publisher -Unique)){$kind=ClassifyUnmatched $app;$items+=[ordered]@{catalog_id=$null;winget_id='';name=Prop $app 'name';installed=$true;installed_version=Prop $app 'version';available_version='';publisher=Prop $app 'publisher';update_status='unmatched';provider_status='not_checked';freshness='local';match_confidence='none';source=Prop $app 'source' 'registry_uninstall';inventory_kind=$kind;catalog_action=$(if($kind-eq'application_candidate'){'review_catalog'}else{'informational'})}}
$applicationCandidates=@($items|Where-Object{$_.update_status-eq'unmatched'-and$_.inventory_kind-eq'application_candidate'});$uniqueApplicationCandidates=@($applicationCandidates|Group-Object { (Normalize ([string]$_.name))+'|'+(Normalize ([string]$_.publisher)) })
$summary=[ordered]@{detected=@($items|Where-Object installed).Count;catalog_matched=@($items|Where-Object{$_.installed-and$_.catalog_id}).Count;updates_available=@($items|Where-Object {$_.update_status -eq 'update_available'}).Count;current=@($items|Where-Object {$_.update_status -eq 'current'}).Count;unknown=@($items|Where-Object {$_.update_status -in @('installed_version_unknown','provider_unavailable')}).Count;unmatched=@($items|Where-Object {$_.update_status -eq 'unmatched'}).Count;unmatched_application_candidates=$applicationCandidates.Count;unmatched_unique_applications=$uniqueApplicationCandidates.Count;unmatched_components=@($items|Where-Object{$_.update_status-eq'unmatched'-and$_.inventory_kind-ne'application_candidate'}).Count}
$run=[guid]::NewGuid().ToString('n');$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss_fffffff');$result=[ordered]@{schema='assemblelink.software_intelligence.v1';run_id=$run;observed_utc=(Get-Date).ToUniversalTime().ToString('o');evidence_mode=$(if($InventoryFixturePath-or$ProviderFixturePath){'fixture'}else{'live'});provider_health=$providerHealth;summary=$summary;items=$items}
$state=Join-Path $RepoRoot "state\software_intelligence.$stamp.$run.json";$latest=Join-Path $RepoRoot 'state\software_intelligence.latest.json';$json=$result|ConvertTo-Json -Depth 15;WriteUtf8 $state $json;WriteUtf8 "$state.sha256" ((Sha $state)+"  "+[IO.Path]::GetFileName($state)+"`n");WriteUtf8 $latest $json;WriteUtf8 "$latest.sha256" ((Sha $latest)+"  "+[IO.Path]::GetFileName($latest)+"`n")
$receipt=Join-Path $RepoRoot "proofs\receipts\assemblelink.software_intelligence_receipt.$stamp.$run.json";WriteUtf8 $receipt (([ordered]@{schema='assemblelink.software_intelligence_receipt.v1';run_id=$run;observed_utc=$result.observed_utc;state=$state;sha256=Sha $state;count=$items.Count}|ConvertTo-Json -Depth 5));WriteUtf8 "$receipt.sha256" ((Sha $receipt)+"  "+[IO.Path]::GetFileName($receipt)+"`n")
Write-Output $state
