param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$ManifestRoot=Join-Path $RepoRoot "manifests\targetclasses"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WriteUtf8([string]$p,[string]$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  $d=Split-Path -Parent $p
  if($d){ EnsureDir $d }
  $u=$t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $u.EndsWith("`n")){ $u+="`n" }
  [IO.File]::WriteAllText($p,$u,$enc)
}

if(-not(Test-Path -LiteralPath $ManifestRoot -PathType Container)){
  Die ("MANIFEST_ROOT_MISSING: "+$ManifestRoot)
}

$files=@(Get-ChildItem -LiteralPath $ManifestRoot -Filter "*.json" -Force)
if(@($files).Count -lt 1){
  Die "NO_TARGETCLASS_MANIFESTS"
}

$rows=@()
$failures=@()

foreach($f in $files){
  try{
    $m=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    $failures += [pscustomobject]@{ file=$f.FullName; error="JSON_PARSE_FAILED"; detail=[string]$_.Exception.Message }
    continue
  }

  if($m.PSObject.Properties.Match("targetclass").Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$m.targetclass)){
    $failures += [pscustomobject]@{ file=$f.FullName; error="MISSING_TARGETCLASS"; detail="" }
    continue
  }

  if($m.PSObject.Properties.Match("label").Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$m.label)){
    $failures += [pscustomobject]@{ file=$f.FullName; error="MISSING_LABEL"; detail=[string]$m.targetclass }
    continue
  }

  if($m.PSObject.Properties.Match("tools").Count -lt 1){
    $failures += [pscustomobject]@{ file=$f.FullName; error="MISSING_TOOLS"; detail=[string]$m.targetclass }
    continue
  }

  $tools=@($m.tools)
  if(@($tools).Count -lt 1){
    $failures += [pscustomobject]@{ file=$f.FullName; error="EMPTY_TOOLS"; detail=[string]$m.targetclass }
    continue
  }

  foreach($t in $tools){
    foreach($prop in @("id","name","command","install_hint")){
      if($t.PSObject.Properties.Match($prop).Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$t.$prop)){
        $failures += [pscustomobject]@{
          file=$f.FullName
          error=("TOOL_MISSING_"+$prop.ToUpperInvariant())
          detail=([string]$m.targetclass)
        }
      }
    }

    if($t.PSObject.Properties.Match("install_hint").Count -ge 1){
      $hint=[string]$t.install_hint
      if($hint -notlike "winget install *"){
        $failures += [pscustomobject]@{
          file=$f.FullName
          error="INSTALL_HINT_NOT_ALLOWED"
          detail=$hint
        }
      }
    }
  }

  $rows += [pscustomobject]@{
    targetclass=[string]$m.targetclass
    label=[string]$m.label
    tools=@($tools).Count
    file=$f.FullName
  }
}

if(@($failures).Count -gt 0){
  $failures | Format-Table -AutoSize
  Die ("ASSEMBLELINK_MANIFEST_VALIDATE_FAILED: "+@($failures).Count)
}

$rows | Sort-Object targetclass | Format-Table -AutoSize

EnsureDir $ReceiptDir
$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp=Join-Path $ReceiptDir ("assemblelink.manifest_validate_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp (
  "schema=assemblelink.manifest_validate_receipt.v1`n"+
  "utc="+(Get-Date).ToUniversalTime().ToString("o")+"`n"+
  "manifest_root="+$ManifestRoot+"`n"+
  "manifest_count="+[string]@($files).Count+"`n"
)

Write-Host ("ASSEMBLELINK_MANIFEST_VALIDATE_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_MANIFEST_VALIDATE_OK" -ForegroundColor Green
