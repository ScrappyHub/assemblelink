param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$ManifestRoot=Join-Path $RepoRoot "manifests\targetclasses"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$ValidateModule=Join-Path $RepoRoot "scripts\commands\al_validate_manifests_v1.ps1"

function EnsureDir([string]$p){
  if(-not(Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function WriteUtf8([string]$p,[string]$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $p)
  $u=$t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $u.EndsWith("`n")){ $u+="`n" }
  [IO.File]::WriteAllText($p,$u,$enc)
}
function HasTool([string]$n){
  if($n -eq "tshark" -and (Test-Path "C:\Program Files\Wireshark\tshark.exe")){ return $true }
  return ($null -ne (Get-Command $n -ErrorAction SilentlyContinue))
}

if(-not(Test-Path -LiteralPath $ValidateModule -PathType Leaf)){
  throw ("VALIDATE_MODULE_MISSING: "+$ValidateModule)
}

Write-Host "ASSEMBLELINK_DOCTOR_START" -ForegroundColor Cyan

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ValidateModule -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  throw ("ASSEMBLELINK_DOCTOR_VALIDATE_FAILED_EXITCODE="+$LASTEXITCODE)
}

$files=@(Get-ChildItem -LiteralPath $ManifestRoot -Filter "*.json" -Force)
$rows=@()

foreach($f in $files){
  $m=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $missing=@()

  foreach($t in @($m.tools)){
    if(-not(HasTool ([string]$t.command))){
      $missing += [string]$t.id
    }
  }

  $status=$(if(@($missing).Count -gt 0){"YELLOW"}else{"GREEN"})

  $rows += [pscustomobject]@{
    targetclass=[string]$m.targetclass
    status=$status
    missing=(@($missing) -join ",")
  }

  if(@($missing).Count -gt 0){
    Write-Host ("DOCTOR_TARGETCLASS_YELLOW: "+$m.targetclass+" missing="+(@($missing) -join ",")) -ForegroundColor Yellow
  } else {
    Write-Host ("DOCTOR_TARGETCLASS_GREEN: "+$m.targetclass) -ForegroundColor Green
  }
}

EnsureDir $ReceiptDir
$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp=Join-Path $ReceiptDir ("assemblelink.doctor_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp (
  "schema=assemblelink.doctor_receipt.v1`n"+
  "utc="+(Get-Date).ToUniversalTime().ToString("o")+"`n"+
  "repo="+$RepoRoot+"`n"+
  "manifest_root="+$ManifestRoot+"`n"
)

Write-Host ("ASSEMBLELINK_DOCTOR_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_DOCTOR_OK" -ForegroundColor Green
