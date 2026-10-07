param([string]$RepoRoot="C:\dev\assemblelink")

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$Latest=Join-Path $StateDir "application_inventory.latest.json"

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
function MatchAny([string]$s,[object[]]$patterns){
  foreach($p in @($patterns)){
    $needle=[string]$p
    if($s.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -ge 0){ return $true }
  }
  return $false
}

if(-not(Test-Path -LiteralPath $Latest -PathType Leaf)){
  throw ("APP_INVENTORY_LATEST_MISSING: "+$Latest)
}

$apps=@(Get-Content -LiteralPath $Latest -Raw -Encoding UTF8 | ConvertFrom-Json)

$rules=@(
  [pscustomobject]@{ capability="Game Development"; patterns=@("Unity","Unreal","Epic Games Launcher","Blender","Godot","GameMaker","RPG Maker","Aseprite","Visual Studio","FMOD") },
  [pscustomobject]@{ capability="Creative / Design"; patterns=@("Adobe","Photoshop","Illustrator","Premiere","After Effects","Audition","Lightroom","Figma","GIMP","Inkscape","Canva","Cinema 4D","OBS") },
  [pscustomobject]@{ capability="Cybersecurity / Forensics"; patterns=@("Burp","Autopsy","Nmap","Wireshark","Wazuh","USBPcap","Application Verifier","Npcap","x64dbg","Ghidra") },
  [pscustomobject]@{ capability="Software Development"; patterns=@("Visual Studio","VS Code","JetBrains","IntelliJ","PyCharm","Android Studio","Git","GitHub CLI","Postman","TablePlus","Docker","Node.js","Python","Rust","Go Programming") },
  [pscustomobject]@{ capability="Local AI / ML"; patterns=@("Ollama","NVIDIA","CUDA","Python","Docker") },
  [pscustomobject]@{ capability="Database / Backend"; patterns=@("PostgreSQL","SQL Server","LocalDB","ODBC","OLE DB","TablePlus") },
  [pscustomobject]@{ capability="Virtualization / Infrastructure"; patterns=@("Docker","VirtualBox","Windows Subsystem for Linux","PowerShell","PuTTY","WezTerm","Nushell") },
  [pscustomobject]@{ capability="Runtimes / SDKs"; patterns=@("\.NET","SDK","Runtime","Targeting Pack","Visual C\+\+","Windows SDK","Android SDK","MAUI","ASP\.NET") },
  [pscustomobject]@{ capability="Game Library / Launchers"; patterns=@("Steam","EA app","Ubisoft","Riot","Rockstar","Fallout","Cyberpunk","Terraria","Subnautica","Halo","Overwatch","VALORANT","Minecraft","Palworld") }
)

$capabilities=@()

foreach($rule in $rules){
  $matches=@()
  foreach($a in $apps){
    $name=[string]$a.name
    if(MatchAny -s $name -patterns @($rule.patterns)){
      $matches += $name
    }
  }

  $unique=@($matches | Sort-Object -Unique)

  $status=$(if(@($unique).Count -ge 5){"READY"}elseif(@($unique).Count -ge 1){"PARTIAL"}else{"NOT_DETECTED"})

  $capabilities += [pscustomobject]@{
    capability=[string]$rule.capability
    status=$status
    detected_count=@($unique).Count
    examples=@($unique | Select-Object -First 12)
  }
}

$summary=[ordered]@{
  schema="assemblelink.normalized_inventory.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  raw_inventory=$Latest
  raw_count=@($apps).Count
  capabilities=$capabilities
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("normalized_inventory.v1_"+$stamp+".json")
WriteUtf8 $out ($summary|ConvertTo-Json -Depth 20)

$latestNorm=Join-Path $StateDir "normalized_inventory.latest.json"
WriteUtf8 $latestNorm ($summary|ConvertTo-Json -Depth 20)

$rcp=Join-Path $ReceiptDir ("assemblelink.normalized_inventory_receipt.v1_"+$stamp+".txt")
WriteUtf8 $rcp ("schema=assemblelink.normalized_inventory_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nraw_count="+@($apps).Count+"`nstate="+$out+"`n")

$capabilities | Select-Object capability,status,detected_count | Format-Table -AutoSize

Write-Host ("ASSEMBLELINK_NORMALIZED_INVENTORY_STATE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_NORMALIZED_INVENTORY_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_NORMALIZED_INVENTORY_OK" -ForegroundColor Green