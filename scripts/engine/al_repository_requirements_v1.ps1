param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$RepositoryPath
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function WriteUtf8([string]$Path,[string]$Text){$dir=Split-Path -Parent $Path;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};$normalized=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$normalized.EndsWith("`n")){$normalized+="`n"};[IO.File]::WriteAllText($Path,$normalized,(New-Object Text.UTF8Encoding($false)))}
function Sha([string]$Path){$sha=[Security.Cryptography.SHA256]::Create();try{$stream=[IO.File]::OpenRead($Path);try{return([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose()}}finally{$sha.Dispose()}}
function ReadBounded([string]$Path){$file=Get-Item -LiteralPath $Path;if($file.Length-gt1048576){throw "REPOSITORY_MANIFEST_TOO_LARGE: $($file.Name)"};return [IO.File]::ReadAllText($file.FullName)}
function AddRequirement([string]$Kind,[string[]]$CatalogIds,[string]$Evidence,[string]$Constraint='',[string]$Confidence='exact_manifest'){
  $script:requirements+= [ordered]@{kind=$Kind;catalog_ids=@($CatalogIds);evidence=$Evidence;version_constraint=$Constraint;confidence=$Confidence}
  foreach($id in $CatalogIds){[void]$script:softwareIds.Add($id)}
}
$repo=(Resolve-Path -LiteralPath $RepositoryPath).Path
if(-not(Test-Path -LiteralPath $repo -PathType Container)){throw 'REPOSITORY_PATH_REJECTED'}
$catalog=Get-Content (Join-Path $RepoRoot 'catalog\approved_software_sources.v1.json') -Raw|ConvertFrom-Json;$catalogIds=@($catalog.items.id)
$script:requirements=@();$script:softwareIds=New-Object 'System.Collections.Generic.HashSet[string]';$recognized=@()
function Evidence([string]$Path){return [IO.Path]::GetFileName($Path)}
$names=@('package.json','pyproject.toml','requirements.txt','Pipfile','poetry.lock','uv.lock','Cargo.toml','go.mod','global.json','pom.xml','build.gradle','build.gradle.kts','CMakeLists.txt','Dockerfile','compose.yaml','compose.yml','docker-compose.yml','docker-compose.yaml','.tool-versions')
$files=@(Get-ChildItem -LiteralPath $repo -File -ErrorAction Stop|Where-Object{$names-contains$_.Name-or$_.Extension-in@('.sln','.csproj','.fsproj','.vbproj')}|Sort-Object Name)
if($files.Count-gt100){throw 'REPOSITORY_MANIFEST_COUNT_REJECTED'}
foreach($file in $files){
  $name=$file.Name;$evidence=Evidence $file.FullName;$text=ReadBounded $file.FullName;$recognized+=$evidence
  switch -Regex ($name){
    '^package\.json$'{$constraint='';try{$json=$text|ConvertFrom-Json;if($json.engines.node){$constraint=[string]$json.engines.node}}catch{throw 'PACKAGE_JSON_INVALID'};AddRequirement 'javascript' @('nodejs-lts') $evidence $constraint;break}
    '^(pyproject\.toml|requirements\.txt|Pipfile|poetry\.lock|uv\.lock)$'{AddRequirement 'python' @('python','uv') $evidence;break}
    '^Cargo\.toml$'{AddRequirement 'rust' @('rustup') $evidence;break}
    '^go\.mod$'{$constraint=if($text-match'(?m)^go\s+([^\s]+)'){$Matches[1]}else{''};AddRequirement 'go' @('golang') $evidence $constraint;break}
    '^(global\.json|.+\.(sln|csproj|fsproj|vbproj))$'{AddRequirement 'dotnet' @('dotnet-sdk-8') $evidence;break}
    '^(pom\.xml|build\.gradle|build\.gradle\.kts)$'{AddRequirement 'java' @('temurin-jdk-21') $evidence;break}
    '^CMakeLists\.txt$'{AddRequirement 'native-build' @('cmake','ninja') $evidence;break}
    '^(Dockerfile|compose\.ya?ml|docker-compose\.ya?ml)$'{AddRequirement 'containers' @('docker-desktop') $evidence;break}
    '^\.tool-versions$'{
      if($text-match'(?m)^nodejs\s+([^\s]+)'){AddRequirement 'javascript' @('nodejs-lts') $evidence $Matches[1] 'declared_tool_version'}
      if($text-match'(?m)^python\s+([^\s]+)'){AddRequirement 'python' @('python','uv') $evidence $Matches[1] 'declared_tool_version'}
      if($text-match'(?m)^rust\s+([^\s]+)'){AddRequirement 'rust' @('rustup') $evidence $Matches[1] 'declared_tool_version'}
      if($text-match'(?m)^golang\s+([^\s]+)'){AddRequirement 'go' @('golang') $evidence $Matches[1] 'declared_tool_version'}
      break
    }
  }
}
if(Test-Path -LiteralPath (Join-Path $repo '.git') -PathType Container){AddRequirement 'source-control' @('git') '.git' '' 'repository_metadata'}
$unknown=@($softwareIds|Where-Object{$catalogIds-notcontains$_});if($unknown.Count){throw('REQUIREMENT_CATALOG_MAPPING_INVALID: '+($unknown-join','))}
$observed=(Get-Date).ToUniversalTime();$result=[ordered]@{schema='assemblelink.repository_requirements.v1';observed_utc=$observed.ToString('o');repository=[ordered]@{name=(Split-Path $repo -Leaf);path=$repo};summary=[ordered]@{recognized_manifests=$recognized.Count;requirement_signals=$requirements.Count;resolved_catalog_items=$softwareIds.Count;status=$(if($requirements.Count){'requirements_detected'}else{'no_supported_manifests'})};requirements=@($requirements);recommended_software_ids=@($softwareIds|Sort-Object);limitations=@('Only supported top-level manifests are analyzed.','Dependency package names are not converted into executable commands.','Version constraints are reported for review and do not bypass approved catalog identities.')}
$state=Join-Path $RepoRoot 'state';$receipts=Join-Path $RepoRoot 'proofs\receipts';$stamp=$observed.ToString('yyyyMMdd_HHmmss_fffffff');$immutable=Join-Path $state "repository_requirements.$stamp.json";$latest=Join-Path $state 'repository_requirements.latest.json';$json=$result|ConvertTo-Json -Depth 12;WriteUtf8 $immutable $json;WriteUtf8 $latest $json
$hash=Sha $immutable;WriteUtf8 ($immutable+'.sha256') "$hash  $([IO.Path]::GetFileName($immutable))";$receipt=Join-Path $receipts "assemblelink.repository_requirements.$stamp.txt";WriteUtf8 $receipt "schema=assemblelink.repository_requirements_receipt.v1`nobserved_utc=$($observed.ToString('o'))`nstate=$([IO.Path]::GetFileName($immutable))`nsha256=$hash";WriteUtf8 ($receipt+'.sha256') "$(Sha $receipt)  $([IO.Path]::GetFileName($receipt))"
Write-Output $immutable
