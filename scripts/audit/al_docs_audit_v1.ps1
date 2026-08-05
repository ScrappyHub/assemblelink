param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Docs=Join-Path $RepoRoot "docs"
$Manifest=Join-Path $Docs "docs_manifest.v1.json"

$Required=@(
  "README.md",
  "USAGE.md",
  "RUNBOOK.md",
  "WHO_IS_IT_FOR.md",
  "THREAT_MODEL.md",
  "INSTALL_SECURITY_MODEL.md",
  "ROADMAP.md",
  "WBS.md",
  "ARCHITECTURE.md",
  "UI_PRODUCT_GAP.md",
  "_INDEX.md"
)

if(-not(Test-Path $Manifest -PathType Leaf)){ throw "DOCS_MANIFEST_MISSING" }

$m=Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$rows=@()

foreach($r in $Required){
  $p=Join-Path $Docs $r
  if(-not(Test-Path $p -PathType Leaf)){ throw "DOC_MISSING: $r" }

  $raw=Get-Content -LiteralPath $p -Raw -Encoding UTF8
  if($raw -match '```'){ throw "BROKEN_FENCING_FOUND: $r" }

  $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()
  $manifestItem=@($m.items | Where-Object { $_.path -eq ("docs\"+$r) }) | Select-Object -First 1
  if($null -eq $manifestItem){ throw "DOC_NOT_IN_MANIFEST: $r" }
  if($manifestItem.sha256 -ne $hash){ throw "DOC_HASH_MISMATCH: $r" }

  $rows += [pscustomobject]@{
    doc=$r
    bytes=(Get-Item $p).Length
    sha256=$hash.Substring(0,12)
    status="OK"
  }
}

$rows | Format-Table -AutoSize
Write-Host "ASSEMBLELINK_DOCS_AUDIT_OK" -ForegroundColor Green
