param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
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

$roots=@(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

function Prop([object]$o,[string]$name){
  $p=$o.PSObject.Properties[$name]
  if($null -eq $p){ return "" }
  if($null -eq $p.Value){ return "" }
  return [string]$p.Value
}

$apps=@()

foreach($r in $roots){
  Get-ItemProperty $r -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrWhiteSpace((Prop $_ "DisplayName")) } |
    ForEach-Object {
      $apps += [pscustomobject]@{
        name=(Prop $_ "DisplayName")
        version=(Prop $_ "DisplayVersion")
        publisher=(Prop $_ "Publisher")
        install_location=(Prop $_ "InstallLocation")
        uninstall_string=(Prop $_ "UninstallString")
        source="registry_uninstall"
      }
    }
}

$Custom=Join-Path $StateDir "custom_software.v1.json"
if(Test-Path -LiteralPath $Custom -PathType Leaf){
  $customItems=@(Get-Content -LiteralPath $Custom -Raw -Encoding UTF8 | ConvertFrom-Json)
  foreach($c in $customItems){
    $apps += [pscustomobject]@{
      name=(Prop $c "name")
      version=(Prop $c "version")
      publisher=(Prop $c "publisher")
      install_location=(Prop $c "install_location")
      uninstall_string=""
      source="user_added"
    }
  }
}

$apps=$apps |
  Sort-Object name,version,publisher,source -Unique

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$state=Join-Path $StateDir ("application_inventory.v1_"+$stamp+".json")
WriteUtf8 $state ($apps|ConvertTo-Json -Depth 10)

$latest=Join-Path $StateDir "application_inventory.latest.json"
WriteUtf8 $latest ($apps|ConvertTo-Json -Depth 10)

$rcp=Join-Path $ReceiptDir ("assemblelink.application_inventory_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.application_inventory_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nstate="+$state+"`ncount="+@($apps).Count+"`n")

$apps | Select-Object name,version,publisher | Format-Table -AutoSize

Write-Host ("ASSEMBLELINK_APP_INVENTORY_COUNT: "+@($apps).Count) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_APP_INVENTORY_STATE: "+$state) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_APP_INVENTORY_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_APP_INVENTORY_OK" -ForegroundColor Green