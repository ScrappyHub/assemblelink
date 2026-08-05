param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$catalog=Get-Content (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Raw|ConvertFrom-Json;$toolkits=Get-Content (Join-Path $RepoRoot 'catalog\toolkits.v1.json') -Raw|ConvertFrom-Json
if(@($catalog.items).Count-lt70){throw 'CATALOG_RELEASE_FLOOR_NOT_MET'};if(@($toolkits.toolkits).Count-lt20){throw 'JOB_TOOLKIT_RELEASE_FLOOR_NOT_MET'}
$testRoot=Join-Path $env:TEMP ('assemblelink-catalog-matrix-'+[guid]::NewGuid().ToString('n'));$path=Join-Path $testRoot 'setup-request.json'
try{
New-Item -ItemType Directory -Force (Join-Path $testRoot 'catalog')|Out-Null;Copy-Item -LiteralPath (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json'),(Join-Path $RepoRoot 'catalog\toolkits.v1.json') -Destination (Join-Path $testRoot 'catalog')
$request=[ordered]@{schema='assemblelink.setup_request.v1';toolkit_ids=@($toolkits.toolkits.id);software_ids=@()};[IO.File]::WriteAllText($path,($request|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
& (Join-Path $RepoRoot 'scripts\engine\al_setup_plan_v1.ps1') -RepoRoot $testRoot -RequestPath $path|Out-Null
$plan=Get-Content (Join-Path $testRoot 'state\setup_plan.latest.json') -Raw|ConvertFrom-Json
if(@($plan.items.id|Sort-Object -Unique).Count-ne@($plan.items).Count){throw 'JOB_MATRIX_PLAN_NOT_DEDUPLICATED'}
if(@($plan.items).Count-ne@($catalog.items).Count){$missing=@($catalog.items.id|Where-Object{$plan.items.id-notcontains$_});throw "CATALOG_ITEMS_NOT_REACHABLE_FROM_JOBS: $($missing-join',')"}
$catalogById=@{};foreach($x in $catalog.items){$catalogById[[string]$x.id]=$x}
foreach($item in $plan.items){$source=$catalogById[[string]$item.id];if($item.mode-eq'winget'){if($source.license-notin@('free','free_open_source')){throw "LICENSE_GATED_ITEM_AUTOMATED: $($item.id)"};if([string]::IsNullOrWhiteSpace([string]$item.winget_id)){throw "AUTOMATIC_ITEM_WITHOUT_EXACT_ID: $($item.id)"}}}
foreach($item in $plan.items){$source=$catalogById[[string]$item.id];if($source.source-in@('official_manual','official_release')-and$item.mode-ne'manual_review'){throw "MANUAL_SOURCE_WAS_AUTOMATED: $($item.id)"}}
$families=@($toolkits.toolkits.job_family|Sort-Object -Unique);if($families.Count-lt9){throw 'JOB_FAMILY_COVERAGE_TOO_SMALL'}
$categories=@($catalog.items.category|Sort-Object -Unique);if($categories.Count-lt20){throw 'CATEGORY_COVERAGE_TOO_SMALL'}
$cli=@($catalog.items|Where-Object{$_.category-in@('cli-utility','cloud-cli','media-cli')});if($cli.Count-lt10){throw 'CLI_COVERAGE_TOO_SMALL'}
$rust=Get-Content (Join-Path $RepoRoot 'ui\src-tauri\src\main.rs') -Raw;if($rust-match'generate_handler!\[[^\]]*(prepare_install|execute_install)'){throw 'LEGACY_INSTALL_IPC_STILL_EXPOSED'};if($rust-notmatch'TRUSTED_RUNTIME_FILES'-or$rust-notmatch'seed_trusted_runtime\(&root\)'){throw 'TRUSTED_RUNTIME_NOT_WIRED'}
[pscustomobject]@{catalog_items=$catalog.items.Count;categories=$categories.Count;job_toolkits=$toolkits.toolkits.Count;job_families=$families.Count;cli_tools=$cli.Count;resolved_plan_items=$plan.items.Count}|Format-List
Write-Host 'ASSEMBLELINK_CATALOG_JOB_MATRIX_TEST_OK'
}finally{if(Test-Path $testRoot){$resolved=(Resolve-Path $testRoot).Path;if($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $resolved -Recurse -Force}}}
