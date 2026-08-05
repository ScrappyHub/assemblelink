param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$BlueprintPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8($p,$t){$d=Split-Path -Parent $p;if($d){New-Item -ItemType Directory -Force $d|Out-Null};[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){$stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}}
if(-not(Test-Path $BlueprintPath -PathType Leaf)){throw 'BLUEPRINT_NOT_FOUND'}
if([IO.Path]::GetExtension($BlueprintPath) -ne '.json'){throw 'BLUEPRINT_EXTENSION_REJECTED'}
$sidecar=$BlueprintPath+'.sha256';if(-not(Test-Path $sidecar)){throw 'BLUEPRINT_HASH_MISSING'}
$expected=((Get-Content $sidecar -Raw).Trim() -split '\s+')[0];$actual=Sha $BlueprintPath
if($expected -ne $actual){throw 'BLUEPRINT_HASH_MISMATCH'}
$blueprint=Get-Content $BlueprintPath -Raw|ConvertFrom-Json
if($blueprint.schema -ne 'assemblelink.blueprint.v1'){throw 'BLUEPRINT_SCHEMA_REJECTED'}
$request=[ordered]@{schema='assemblelink.setup_request.v1';toolkit_ids=@($blueprint.toolkit_ids);software_ids=@($blueprint.software_ids)}
$requestPath=Join-Path $RepoRoot 'state\setup_request.imported.json';WriteUtf8 $requestPath ($request|ConvertTo-Json -Depth 10)
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\engine\al_setup_plan_v1.ps1') -RepoRoot $RepoRoot -RequestPath $requestPath
if($LASTEXITCODE -ne 0){throw "BLUEPRINT_PLAN_FAILED: $LASTEXITCODE"}
