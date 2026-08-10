param([string]$RepoRoot='C:\dev\assemblelink')
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$catalog=Get-Content (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Raw|ConvertFrom-Json
$toolkits=Get-Content (Join-Path $RepoRoot 'catalog\toolkits.v1.json') -Raw|ConvertFrom-Json
$allocation=Get-Content (Join-Path $RepoRoot 'catalog\allocation_policy.v1.json') -Raw|ConvertFrom-Json
if($allocation.schema-ne'assemblelink.allocation_policy.v1'-or[int64]$allocation.minimum_allocation_mib-ne5120-or[int64]$allocation.maximum_allocation_mib-ne2097152){throw 'ALLOCATION_POLICY_REJECTED'}
$ids=@{}; foreach($x in @($catalog.items)){
  $id=[string]$x.id
  if($id -notmatch '^[a-z0-9][a-z0-9-]{0,63}$'){throw "UNSAFE_CATALOG_ID: $id"}
  if($ids.ContainsKey($id)){throw "DUPLICATE_CATALOG_ID: $id"}; $ids[$id]=$true
  if($x.PSObject.Properties.Name -contains 'install_command'){throw "CATALOG_COMMAND_FORBIDDEN: $id"}
  if([string]$x.source-notin@('official_or_winget','official_manual','official_release')){throw "UNKNOWN_SOURCE_POLICY: $id"}
  if($x.source -eq 'official_or_winget' -and [string]::IsNullOrWhiteSpace([string]$x.winget_id)){throw "MISSING_WINGET_ID: $id"}
  if($x.source -eq 'official_manual'){
    if(-not[string]::IsNullOrWhiteSpace([string]$x.winget_id)){throw "MANUAL_SOURCE_HAS_PACKAGE_ID: $id"}
    if([string]$x.official_url-notmatch'^https://[A-Za-z0-9.-]+(?:/|$)'){throw "INVALID_OFFICIAL_URL: $id"}
    if([string]::IsNullOrWhiteSpace([string]$x.verification)){throw "MANUAL_SOURCE_VERIFICATION_REQUIRED: $id"}
  }
  if($x.source -eq 'official_release'){
    if(-not[string]::IsNullOrWhiteSpace([string]$x.winget_id)){throw "OFFICIAL_RELEASE_HAS_PACKAGE_ID: $id"}
    if(-not($x.PSObject.Properties.Name-contains'version_provider')){throw "OFFICIAL_RELEASE_PROVIDER_REQUIRED: $id"}
  }
  if([string]::IsNullOrWhiteSpace([string]$x.category)-or[string]$x.category-notmatch'^[a-z0-9][a-z0-9-]{1,63}$'){throw "INVALID_CATEGORY: $id"}
  if([string]$x.license-notin@('free','free_open_source','license_review_required','source_available_license_review','account_required')){throw "UNKNOWN_LICENSE_POLICY: $id -> $($x.license)"}
  if(@($x.capabilities).Count-eq0){throw "MISSING_CAPABILITY: $id"};foreach($cap in @($x.capabilities)){if([string]$cap-notin@('software-development','local-ai','infrastructure','game-development','cybersecurity','content-creation')){throw "UNKNOWN_CAPABILITY: $id -> $cap"}}
}
foreach($x in @($catalog.items)){if($x.PSObject.Properties.Name -contains 'dependencies'){foreach($dep in @($x.dependencies)){if(-not $ids.ContainsKey([string]$dep)){throw "UNKNOWN_CATALOG_DEPENDENCY: $($x.id) -> $dep"}}}}
foreach($category in @($catalog.items.category|Sort-Object -Unique)){if(-not($allocation.category_estimates_mib.PSObject.Properties.Name-contains[string]$category)-or[int64]$allocation.category_estimates_mib.([string]$category)-le0){throw "ALLOCATION_CATEGORY_ESTIMATE_MISSING: $category"}}
foreach($override in @($allocation.item_overrides_mib.PSObject.Properties)){if(-not$ids.ContainsKey([string]$override.Name)-or[int64]$override.Value-le0){throw "ALLOCATION_OVERRIDE_REJECTED: $($override.Name)"}}
$visiting=@{};$visited=@{}
function Visit([string]$id){if($visiting.ContainsKey($id)){throw "CATALOG_DEPENDENCY_CYCLE: $id"};if($visited.ContainsKey($id)){return};$visiting[$id]=$true;$entry=@($catalog.items|Where-Object id -eq $id)[0];if($entry.PSObject.Properties.Name -contains 'dependencies'){foreach($dep in @($entry.dependencies)){Visit ([string]$dep)}};$visiting.Remove($id);$visited[$id]=$true}
foreach($id in @($ids.Keys|Sort-Object)){Visit $id}
$kitIds=@{}; foreach($kit in @($toolkits.toolkits)){
  $id=[string]$kit.id; if($id -notmatch '^[a-z0-9][a-z0-9-]{0,63}$'){throw "UNSAFE_TOOLKIT_ID: $id"}
  if($kitIds.ContainsKey($id)){throw "DUPLICATE_TOOLKIT_ID: $id"}; $kitIds[$id]=$true
  if([string]::IsNullOrWhiteSpace([string]$kit.job_family)){throw "TOOLKIT_JOB_FAMILY_REQUIRED: $id"}
  if(@($kit.software_ids).Count-lt5){throw "TOOLKIT_TOO_SMALL: $id"}
  foreach($softwareId in @($kit.software_ids)){if(-not $ids.ContainsKey([string]$softwareId)){throw "UNKNOWN_TOOLKIT_SOFTWARE: $id -> $softwareId"}}
}
$requiredFamilies=@('Software Development','Developer Tools','Mobile Development','Data and Databases','Cloud and Infrastructure','AI and Machine Learning','Cybersecurity','Game Development','Creative Production');foreach($family in $requiredFamilies){if(-not@($toolkits.toolkits|Where-Object {$_.job_family -eq $family}).Count){throw "MISSING_JOB_FAMILY: $family"}}
$cliCount=@($catalog.items|Where-Object{$_.category-in@('cli-utility','cloud-cli','media-cli')}).Count;if($cliCount-lt10){throw "CLI_CATALOG_COVERAGE_TOO_SMALL: $cliCount"}
if($ids.Count-lt70-or$kitIds.Count-lt20){throw 'CATALOG_OR_JOB_MATRIX_BELOW_RELEASE_FLOOR'}
[pscustomobject]@{catalog_items=$ids.Count;toolkits=$kitIds.Count;job_families=@($toolkits.toolkits.job_family|Sort-Object -Unique).Count;cli_tools=$cliCount;commands_in_catalog=0;unknown_references=0;dependency_cycles=0}|Format-List
Write-Host 'ASSEMBLELINK_SETUP_SECURITY_AUDIT_OK' -ForegroundColor Green
