param([string]$RepoRoot='C:\dev\assemblelink')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$fixture=Join-Path $env:TEMP ('assemblelink-repository-'+[guid]::NewGuid().ToString('n'));$runtime=Join-Path $env:TEMP ('assemblelink-repository-runtime-'+[guid]::NewGuid().ToString('n'))
try{
  New-Item -ItemType Directory -Force $fixture,$runtime|Out-Null;Copy-Item (Join-Path $RepoRoot 'catalog') $runtime -Recurse;New-Item -ItemType Directory -Force (Join-Path $runtime 'scripts\engine')|Out-Null;Copy-Item (Join-Path $RepoRoot 'scripts\engine\al_repository_requirements_v1.ps1') (Join-Path $runtime 'scripts\engine')
  [IO.File]::WriteAllText((Join-Path $fixture 'package.json'),'{"engines":{"node":">=22"}}',(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText((Join-Path $fixture 'Cargo.toml'),'[package]',(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText((Join-Path $fixture 'Dockerfile'),'FROM scratch',(New-Object Text.UTF8Encoding($false)))
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $runtime 'scripts\engine\al_repository_requirements_v1.ps1') -RepoRoot $runtime -RepositoryPath $fixture
  if($LASTEXITCODE -ne 0){throw 'REPOSITORY_ANALYZER_FAILED'};$result=Get-Content (Join-Path $runtime 'state\repository_requirements.latest.json') -Raw|ConvertFrom-Json
  foreach($id in @('nodejs-lts','rustup','docker-desktop')){if(@($result.recommended_software_ids)-notcontains$id){throw "REPOSITORY_MAPPING_MISSING: $id"}}
  if($result.summary.recognized_manifests -ne 3 -or $result.schema -ne 'assemblelink.repository_requirements.v1'){throw 'REPOSITORY_CONTRACT_INVALID'}
  $receipt=Get-ChildItem (Join-Path $runtime 'proofs\receipts') -Filter 'assemblelink.repository_requirements.*.txt'|Select-Object -First 1;if(-not$receipt-or-not(Test-Path ($receipt.FullName+'.sha256'))){throw 'REPOSITORY_RECEIPT_MISSING'}
  Write-Host 'ASSEMBLELINK_REPOSITORY_REQUIREMENTS_TESTS_OK' -ForegroundColor Green
}finally{foreach($path in @($fixture,$runtime)){if(Test-Path $path){Remove-Item $path -Recurse -Force}}}
