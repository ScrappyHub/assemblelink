param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

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
function ToolPath([string]$n){
  if($n -eq "tshark" -and (Test-Path "C:\Program Files\Wireshark\tshark.exe")){ return "C:\Program Files\Wireshark\tshark.exe" }
  try{ return [string](Get-Command $n -ErrorAction Stop).Source }catch{ return "" }
}
function InventoryRows(){
  $tools=@("git","node","npm","python","pip","code","docker","winget","pwsh","nmap","tshark","blender")
  foreach($t in $tools){
    [pscustomobject]@{tool=$t;installed=(HasTool $t);source=(ToolPath $t)}
  }
}

if(-not(Test-Path -LiteralPath $ProfilePath -PathType Leaf)){
  throw ("IMPORT_PROFILE_NOT_FOUND: "+$ProfilePath)
}

$profile=Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
if($profile.PSObject.Properties.Match("inventory").Count -lt 1){
  throw "IMPORT_BAD_PROFILE_NO_INVENTORY"
}

$local=@(InventoryRows)
$localMap=@{}
foreach($r in $local){ $localMap[[string]$r.tool]=$r }

$plan=@()
foreach($remote in @($profile.inventory)){
  $tool=[string]$remote.tool
  $remoteInstalled=[string]$remote.installed

  if(-not $localMap.ContainsKey($tool)){
    $plan += [pscustomobject]@{
      tool=$tool
      remote_installed=$remoteInstalled
      local_installed="missing_from_local_inventory"
      action="review"
    }
    continue
  }

  $localInstalled=[string]$localMap[$tool].installed

  if($remoteInstalled -eq "True" -and $localInstalled -ne "True"){
    $plan += [pscustomobject]@{
      tool=$tool
      remote_installed=$remoteInstalled
      local_installed=$localInstalled
      action="install_or_map"
    }
  }
}

if(@($plan).Count -lt 1){
  Write-Host "ASSEMBLELINK_IMPORT_MATCH: local machine satisfies imported profile inventory" -ForegroundColor Green
} else {
  $plan | Format-Table -AutoSize
  Write-Host ("ASSEMBLELINK_IMPORT_PLAN_FOUND: "+@($plan).Count) -ForegroundColor Yellow
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("import_plan.v1_"+$stamp+".json")
WriteUtf8 $out ($plan|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.import_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.import_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nprofile="+$ProfilePath+"`nplan="+$out+"`n")

Write-Host ("ASSEMBLELINK_IMPORT_PLAN: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_IMPORT_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_IMPORT_OK" -ForegroundColor Green
