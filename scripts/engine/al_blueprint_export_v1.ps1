param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
function WriteUtf8($p,$t){$d=Split-Path -Parent $p;if($d){New-Item -ItemType Directory -Force $d|Out-Null};[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){$stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}}
$planPath=Join-Path $RepoRoot 'state\setup_plan.latest.json'; if(-not(Test-Path $planPath)){throw 'NO_SETUP_PLAN_TO_EXPORT'}
$plan=Get-Content $planPath -Raw|ConvertFrom-Json
if($plan.schema -ne 'assemblelink.setup_plan.v1'){throw 'SETUP_PLAN_SCHEMA_REJECTED'}
$blueprint=[ordered]@{schema='assemblelink.blueprint.v1';created_utc=(Get-Date).ToUniversalTime().ToString('o');source_machine_profile=$plan.machine_profile;toolkit_ids=@($plan.toolkit_ids);software_ids=@($plan.items|ForEach-Object{[string]$_.id}|Sort-Object -Unique)}
$dir=Join-Path $RepoRoot 'exports';$path=Join-Path $dir ('AssembleLink-Blueprint-'+(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')+'.json');WriteUtf8 $path ($blueprint|ConvertTo-Json -Depth 10)
$hash=Sha $path;WriteUtf8 ($path+'.sha256') ($hash+'  '+[IO.Path]::GetFileName($path))
Write-Output $path
