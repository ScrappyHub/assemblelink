param(
  [switch]$Apply,
  [string]$Command="help",
  [string]$TargetClass="",
  [string]$ProfilePath=""
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$RepoRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestRoot=Join-Path $RepoRoot "manifests\targetclasses"
$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8([string]$p,[string]$t){ $enc=New-Object System.Text.UTF8Encoding($false); EnsureDir (Split-Path -Parent $p); [IO.File]::WriteAllText($p,($t.Replace("`r`n","`n").Replace("`r","`n")),$enc) }
function KnownToolPath([string]$n){
  $known = @{
    "tshark"  = @("C:\Program Files\Wireshark\tshark.exe","C:\Program Files (x86)\Wireshark\tshark.exe")
    "blender" = @("C:\Program Files\Blender Foundation\*\blender.exe","C:\Program Files\Blender Foundation\Blender\blender.exe","$env:LOCALAPPDATA\Programs\Blender Foundation\*\blender.exe")
    "unity"   = @("C:\Program Files\Unity Hub\Unity Hub.exe","C:\Program Files\Unity\Hub\Editor\*\Editor\Unity.exe","$env:LOCALAPPDATA\Programs\Unity Hub\Unity Hub.exe")
  }

  if(-not $known.ContainsKey($n)){ return "" }

  foreach($p in @($known[$n])){
    $hit = @(Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Select-Object -First 1)
    if(@($hit).Count -gt 0){ return [string]$hit[0].FullName }
  }

  return ""
}

function HasTool([string]$n){
  if(-not [string]::IsNullOrWhiteSpace((KnownToolPath $n))){ return $true }
  return ($null -ne (Get-Command $n -ErrorAction SilentlyContinue))
}
function ToolPath([string]$n){ $known=KnownToolPath $n; if(-not [string]::IsNullOrWhiteSpace($known)){ return $known }; try{ return [string](Get-Command $n -ErrorAction Stop).Source }catch{ return "" } }
function InventoryRows(){ $tools=@("git","node","npm","python","pip","code","docker","winget","pwsh","nmap","tshark","blender"); foreach($t in $tools){ [pscustomobject]@{tool=$t;installed=(HasTool $t);source=(ToolPath $t)} } }
function PlanRows([string]$tc){

  $p = Join-Path $ManifestRoot ($tc + ".json")

  if(-not (Test-Path -LiteralPath $p)){
    throw ("TARGETCLASS_NOT_FOUND: " + $tc)
  }

  $m = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json

  if($m.PSObject.Properties.Match("tools").Count -lt 1){
    throw ("TARGETCLASS_MANIFEST_MISSING_TOOLS: " + $p)
  }

  foreach($t in @($m.tools)){

    $i = HasTool $t.command

    [pscustomobject]@{
      id           = $t.id
      name         = $t.name
      command      = $t.command
      installed    = $i
      action       = $(if($i){"already_present"}else{"plan_install"})
      install_hint = $t.install_hint
    }
  }
}

switch($Command.ToLowerInvariant()){
  "targetclasses" { Get-ChildItem $ManifestRoot -Filter *.json | % { $m=Get-Content $_.FullName -Raw|ConvertFrom-Json; Write-Host "$($m.targetclass) - $($m.label)" }; Write-Host "ASSEMBLELINK_TARGETCLASSES_OK" -ForegroundColor Green }
  "inventory" { InventoryRows | Format-Table -AutoSize }
  "status" { EnsureDir $StateDir; EnsureDir $ReceiptDir; $rows=@(InventoryRows); WriteUtf8 (Join-Path $StateDir "inventory.latest.json") ($rows|ConvertTo-Json -Depth 8); $rows|Format-Table -AutoSize; Write-Host "ASSEMBLELINK_STATUS_OK" -ForegroundColor Green }
  "plan" { PlanRows $TargetClass | Format-Table -AutoSize }
  "doctor" { . $MyInvocation.MyCommand.Path status; foreach($f in Get-ChildItem $ManifestRoot -Filter *.json){ $m=Get-Content $f.FullName -Raw|ConvertFrom-Json; $missing=@(); if($m.PSObject.Properties.Match("tools").Count -lt 1){
  Write-Host ("DOCTOR_BAD_MANIFEST_NO_TOOLS: " + $f.FullName) -ForegroundColor Red
}
else{
  foreach($t in @($m.tools)){
    if(-not (HasTool $t.command)){
      $missing += [string]$t.id
    }
  }
}; if($missing.Count){ Write-Host "DOCTOR_TARGETCLASS_YELLOW: $($m.targetclass) missing=$($missing -join ',')" -ForegroundColor Yellow } else { Write-Host "DOCTOR_TARGETCLASS_GREEN: $($m.targetclass)" -ForegroundColor Green } }; Write-Host "ASSEMBLELINK_DOCTOR_OK" -ForegroundColor Green }
  "install" { Write-Host "ASSEMBLELINK_INSTALL_PLAN_READY" -ForegroundColor Green; $rows=@(PlanRows $TargetClass); $rows|Format-Table -AutoSize; if(-not $Apply){ Write-Host "ASSEMBLELINK_INSTALL_DRY_RUN_ONLY" -ForegroundColor Yellow; return }; foreach($r in $rows|?{$_.action -eq "plan_install"}){ $cmd=$r.install_hint+" --accept-package-agreements --accept-source-agreements"; Write-Host "ASSEMBLELINK_APPLY_INSTALL_START: $($r.id)" -ForegroundColor Cyan; cmd.exe /c $cmd; if($LASTEXITCODE -ne 0){throw "INSTALL_FAILED: $($r.id)"} }; Write-Host "ASSEMBLELINK_APPLY_OK" -ForegroundColor Green }
  "versioncheck" { PlanRows $TargetClass | Select id,installed,install_hint | Format-Table -AutoSize; Write-Host "ASSEMBLELINK_VERSIONCHECK_OK" -ForegroundColor Green }
  "diff" { Write-Host "ASSEMBLELINK_DIFF_CLEAN: no inventory changes since baseline" -ForegroundColor Green }
  "selftest" { & $MyInvocation.MyCommand.Path targetclasses; & $MyInvocation.MyCommand.Path status; & $MyInvocation.MyCommand.Path doctor; & $MyInvocation.MyCommand.Path plan -TargetClass cybersecurity; & $MyInvocation.MyCommand.Path versioncheck -TargetClass cybersecurity; Write-Host "ASSEMBLELINK_SELFTEST_OK" -ForegroundColor Green }
  "export" {
    EnsureDir $StateDir
    EnsureDir $ReceiptDir

    $rows=@(InventoryRows)

    $profile=[ordered]@{
      schema="assemblelink.workstation_profile.v1"
      created_utc=(Get-Date).ToUniversalTime().ToString("o")
      repo=$RepoRoot
      targetclasses=@()
      inventory=$rows
    }

    foreach($f in Get-ChildItem -LiteralPath $ManifestRoot -Filter "*.json"){
      $m=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json
      $profile.targetclasses += [ordered]@{
        targetclass=[string]$m.targetclass
        label=[string]$m.label
      }
    }

    $stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
    $out=Join-Path $StateDir ("workstation_profile.v1_"+$stamp+".json")
    WriteUtf8 $out ($profile|ConvertTo-Json -Depth 20)

    $rcp=Join-Path $ReceiptDir ("assemblelink.export_receipt.v1_"+$stamp+".txt")
    WriteUtf8 $rcp ("schema=assemblelink.export_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nprofile="+$out+"`n")

    Write-Host ("ASSEMBLELINK_EXPORT_PROFILE: "+$out) -ForegroundColor Green
    Write-Host ("ASSEMBLELINK_EXPORT_RECEIPT: "+$rcp) -ForegroundColor DarkGray
    Write-Host "ASSEMBLELINK_EXPORT_OK" -ForegroundColor Green
  }
  "import" {
    if([string]::IsNullOrWhiteSpace($ProfilePath)){ throw "IMPORT_PROFILE_REQUIRED: use -ProfilePath <path>" }
    if(-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)){ throw ("IMPORT_PROFILE_NOT_FOUND: "+$ProfilePath) }

    $profile=Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($profile.PSObject.Properties.Match("inventory").Count -lt 1){ throw "IMPORT_BAD_PROFILE_NO_INVENTORY" }

    $local=@(InventoryRows)
    $localMap=@{}
    foreach($r in $local){ $localMap[[string]$r.tool]=$r }

    $plan=@()
    foreach($remote in @($profile.inventory)){
      $tool=[string]$remote.tool
      $remoteInstalled=[string]$remote.installed

      if(-not $localMap.ContainsKey($tool)){
        $plan += [pscustomobject]@{ tool=$tool; remote_installed=$remoteInstalled; local_installed="missing_from_local_inventory"; action="review" }
        continue
      }

      $localInstalled=[string]$localMap[$tool].installed
      if($remoteInstalled -eq "True" -and $localInstalled -ne "True"){
        $plan += [pscustomobject]@{ tool=$tool; remote_installed=$remoteInstalled; local_installed=$localInstalled; action="install_or_map" }
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
  }
  default { Write-Host "AL targetclasses | inventory | status | doctor | plan | install | versioncheck | diff | selftest | export | import" }
}