param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$State=Join-Path $RepoRoot "state"
$Public=Join-Path $RepoRoot "ui\public\state"
$Idx=Join-Path $State "capability_status_index.latest.json"
$PubIdx=Join-Path $Public "capability_status_index.latest.json"

if(-not(Test-Path -LiteralPath $Idx -PathType Leaf)){ throw "STATUS_INDEX_MISSING" }
if(-not(Test-Path -LiteralPath $PubIdx -PathType Leaf)){ throw "PUBLIC_STATUS_INDEX_MISSING" }

$j=Get-Content -LiteralPath $Idx -Raw -Encoding UTF8 | ConvertFrom-Json
if([string]$j.schema -ne "assemblelink.capability_status_index.v1"){ throw "STATUS_INDEX_SCHEMA_INVALID" }
if(@($j.capabilities).Count -lt 6){ throw "STATUS_INDEX_TOO_SMALL" }

foreach($c in @($j.capabilities)){
  $id=[string]$c.capability_id
  $p=Join-Path $State ("capability_status.$id.latest.json")
  $pp=Join-Path $Public ("capability_status.$id.latest.json")
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){ throw "STATUS_FILE_MISSING: $id" }
  if(-not(Test-Path -LiteralPath $pp -PathType Leaf)){ throw "PUBLIC_STATUS_FILE_MISSING: $id" }

  $s=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
  if([string]$s.schema -ne "assemblelink.capability_status.v1"){ throw "STATUS_SCHEMA_INVALID: $id" }
}

$j.capabilities | Sort-Object name | Format-Table name,status,score,installed,missing,optional -AutoSize
Write-Host "ASSEMBLELINK_CAPABILITY_STATUS_AUDIT_OK" -ForegroundColor Green
