param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Ui=Join-Path $RepoRoot "ui\src\main.js"
$Css=Join-Path $RepoRoot "ui\src\style.css"
$StateDir=Join-Path $RepoRoot "state"
$PublicState=Join-Path $RepoRoot "ui\public\state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"

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
function HasText($path,$needle){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){ return $false }
  $raw=Get-Content -LiteralPath $path -Raw -Encoding UTF8
  return ($raw.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0)
}

EnsureDir $ReceiptDir

$findings=@()

if(-not(Test-Path -LiteralPath $Ui -PathType Leaf)){ throw "UI_MAIN_MISSING" }
if(-not(Test-Path -LiteralPath $Css -PathType Leaf)){ throw "UI_CSS_MISSING" }

$raw=Get-Content -LiteralPath $Ui -Raw -Encoding UTF8
$cssRaw=Get-Content -LiteralPath $Css -Raw -Encoding UTF8

$checks=@(
  @{area="UI"; item="Review capability buttons"; pass=($raw -match 'data-review'); fix="Ensure review buttons bind selectedCapabilityId"},
  @{area="UI"; item="Generate install plan button handler"; pass=($raw -match 'generateInstallPlan' -or $raw -match 'data-generate-plan'); fix="Add handler and local plan preview"},
  @{area="UI"; item="Add software button handler"; pass=($raw -match 'addSoftware' -or $raw -match 'data-add-software'); fix="Add modal/form for custom software"},
  @{area="UI"; item="Modern search styling"; pass=($cssRaw -match 'searchBox' -or $cssRaw -match 'input\[id="softwareSearch"\]'); fix="Style search input and filter row"},
  @{area="UI"; item="Detected pills spacing"; pass=($cssRaw -match 'detectedPill'); fix="Ensure pills wrap with gap and not run together"},
  @{area="UI"; item="Recommended actions render"; pass=($raw -match 'renderRecommendedActions'); fix="Load and render recommended_actions.latest.json"},
  @{area="STATE"; item="Capability graph public sync"; pass=(Test-Path (Join-Path $PublicState "capability_graph.latest.json") -PathType Leaf); fix="Sync capability graph to ui/public/state"},
  @{area="STATE"; item="System profile public sync"; pass=(Test-Path (Join-Path $PublicState "system_profile.latest.json") -PathType Leaf); fix="Sync system profile to ui/public/state"},
  @{area="STATE"; item="Driver profile public sync"; pass=(Test-Path (Join-Path $PublicState "driver_profile.latest.json") -PathType Leaf); fix="Sync driver profile to ui/public/state"},
  @{area="STATE"; item="Recommended actions public sync"; pass=(Test-Path (Join-Path $PublicState "recommended_actions.latest.json") -PathType Leaf); fix="Sync recommended actions to ui/public/state"},
  @{area="ENGINE"; item="Custom software command"; pass=(Test-Path (Join-Path $RepoRoot "scripts\commands\al_add_custom_software_v1.ps1") -PathType Leaf); fix="Create custom software add command"},
  @{area="ENGINE"; item="Driver profile command"; pass=(Test-Path (Join-Path $RepoRoot "scripts\commands\al_driver_profile_v1.ps1") -PathType Leaf); fix="Create driver profile command"},
  @{area="ENGINE"; item="Recommended actions engine"; pass=(Test-Path (Join-Path $RepoRoot "scripts\engine\al_recommended_actions_v1.ps1") -PathType Leaf); fix="Create recommended actions engine"}
)

foreach($c in $checks){
  $findings += [pscustomobject]@{
    area=$c.area
    item=$c.item
    status=$(if($c.pass){"OK"}else{"MISSING"})
    fix=$c.fix
  }
}

$buttons=@()
[regex]::Matches($raw,'<button[^>]*>(.*?)</button>') | ForEach-Object {
  $buttons += [pscustomobject]@{
    text=($_.Groups[1].Value -replace '<[^>]+>','').Trim()
    has_data_attr=($_.Value -match 'data-')
    raw=$_.Value
  }
}

$stateFiles=@()
foreach($f in Get-ChildItem -LiteralPath $StateDir -Filter "*.latest.json" -ErrorAction SilentlyContinue){
  $stateFiles += [pscustomobject]@{
    file=$f.Name
    bytes=$f.Length
    public_synced=(Test-Path (Join-Path $PublicState $f.Name) -PathType Leaf)
  }
}

$report=[ordered]@{
  schema="assemblelink.ui_audit.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  repo=$RepoRoot
  findings=$findings
  buttons=$buttons
  state_files=$stateFiles
}

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("ui_audit.v1_"+$stamp+".json")
$latest=Join-Path $StateDir "ui_audit.latest.json"
WriteUtf8 $out ($report|ConvertTo-Json -Depth 20)
WriteUtf8 $latest ($report|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.ui_audit_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.ui_audit_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nstate="+$out+"`n")

Write-Host "`nUI / ENGINE AUDIT" -ForegroundColor Cyan
$findings | Format-Table area,item,status,fix -AutoSize

Write-Host "`nBUTTONS" -ForegroundColor Cyan
$buttons | Select-Object text,has_data_attr | Format-Table -AutoSize

Write-Host "`nSTATE FILES" -ForegroundColor Cyan
$stateFiles | Format-Table -AutoSize

Write-Host ("ASSEMBLELINK_UI_AUDIT_STATE: "+$out) -ForegroundColor Green
Write-Host "ASSEMBLELINK_UI_AUDIT_OK" -ForegroundColor Green