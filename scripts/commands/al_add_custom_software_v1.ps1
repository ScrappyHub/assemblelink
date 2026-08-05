param(
  [string]$RepoRoot="C:\dev\assemblelink",
  [Parameter(Mandatory=$true)][string]$Name,
  [string]$Version="",
  [string]$Publisher="",
  [string]$Path="",
  [string]$Category="Uncategorized",
  [string]$LicenseGate="unknown",
  [string]$Notes=""
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$Custom=Join-Path $StateDir "custom_software.v1.json"

function EnsureDir($p){
  if(-not(Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function WriteUtf8($p,$t){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $p)
  $u=$t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $u.EndsWith("`n")){ $u+="`n" }
  [IO.File]::WriteAllText($p,$u,$enc)
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$items=@()
if(Test-Path -LiteralPath $Custom -PathType Leaf){
  $items=@(Get-Content -LiteralPath $Custom -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$item=[pscustomobject]@{
  name=$Name
  version=$Version
  publisher=$Publisher
  install_location=$Path
  category=$Category
  license_gate=$LicenseGate
  notes=$Notes
  source="user_added"
  added_utc=(Get-Date).ToUniversalTime().ToString("o")
}

$items += $item
$items = @($items | Sort-Object name,version,publisher -Unique)

WriteUtf8 $Custom ($items|ConvertTo-Json -Depth 10)

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$rcp=Join-Path $ReceiptDir ("assemblelink.custom_software_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.custom_software_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nname="+$Name+"`ncustom="+$Custom+"`n")

Write-Host ("ASSEMBLELINK_CUSTOM_SOFTWARE_ADDED: "+$Name) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_CUSTOM_SOFTWARE_FILE: "+$Custom) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_CUSTOM_SOFTWARE_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_ADD_CUSTOM_SOFTWARE_OK" -ForegroundColor Green