param(
  [string]$RepoRoot="C:\dev\assemblelink"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$GraphPath=Join-Path $StateDir "capability_graph.latest.json"
$InvPath=Join-Path $StateDir "application_inventory.latest.json"
$PublicState=Join-Path $RepoRoot "ui\public\state"

function EnsureDir([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc=New-Object System.Text.UTF8Encoding($false)
  EnsureDir (Split-Path -Parent $Path)
  $t=$Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t+="`n" }
  [IO.File]::WriteAllText($Path,$t,$enc)
}

function Slug([string]$Text){
  $s=$Text.ToLowerInvariant()
  $s=$s -replace '[^a-z0-9]+','-'
  $s=$s.Trim('-')
  return $s
}

function HasSoftware([object[]]$Inventory,[string[]]$Needles){
  foreach($item in @($Inventory)){
    $n=[string]($item.name)
    $p=[string]($item.publisher)
    $hay=($n+" "+$p).ToLowerInvariant()
    foreach($needle in $Needles){
      if($hay -like ("*"+$needle.ToLowerInvariant()+"*")){
        return $true
      }
    }
  }
  return $false
}

function SoftwareMatches([object[]]$Inventory,[string[]]$Needles){
  $matches=@()
  foreach($item in @($Inventory)){
    $n=[string]($item.name)
    $p=[string]($item.publisher)
    $hay=($n+" "+$p).ToLowerInvariant()
    foreach($needle in $Needles){
      if($hay -like ("*"+$needle.ToLowerInvariant()+"*")){
        $matches += $item
        break
      }
    }
  }
  return @($matches)
}

if(-not(Test-Path -LiteralPath $GraphPath -PathType Leaf)){ throw "CAPABILITY_GRAPH_MISSING: $GraphPath" }
if(-not(Test-Path -LiteralPath $InvPath -PathType Leaf)){ throw "APPLICATION_INVENTORY_MISSING: $InvPath" }

EnsureDir $StateDir
EnsureDir $ReceiptDir
EnsureDir $PublicState

$graph=Get-Content -LiteralPath $GraphPath -Raw -Encoding UTF8 | ConvertFrom-Json
$invObj=Get-Content -LiteralPath $InvPath -Raw -Encoding UTF8 | ConvertFrom-Json

$inventory=@()
if($invObj.PSObject.Properties["software"]){ $inventory=@($invObj.software) }
elseif($invObj.PSObject.Properties["items"]){ $inventory=@($invObj.items) }
elseif($invObj -is [array]){ $inventory=@($invObj) }

$catalog=@{
  "content-creation"=@(
    @{ id="adobe-creative-cloud"; name="Adobe Creative Cloud"; required=$false; needles=@("adobe creative cloud","photoshop","premiere","after effects","illustrator") },
    @{ id="obs-studio"; name="OBS Studio"; required=$false; needles=@("obs studio") },
    @{ id="gimp"; name="GIMP"; required=$false; needles=@("gimp") },
    @{ id="audacity"; name="Audacity"; required=$false; needles=@("audacity") },
    @{ id="blender"; name="Blender"; required=$false; needles=@("blender") }
  )
  "game-development"=@(
    @{ id="git"; name="Git"; required=$true; needles=@("git") },
    @{ id="vscode"; name="VS Code"; required=$true; needles=@("visual studio code","vs code") },
    @{ id="blender"; name="Blender"; required=$false; needles=@("blender") },
    @{ id="godot"; name="Godot Engine"; required=$false; needles=@("godot") },
    @{ id="unity"; name="Unity"; required=$false; needles=@("unity") },
    @{ id="unreal"; name="Unreal / Epic Games"; required=$false; needles=@("unreal","epic games launcher") }
  )
  "cybersecurity"=@(
    @{ id="nmap"; name="Nmap"; required=$true; needles=@("nmap") },
    @{ id="wireshark"; name="Wireshark"; required=$false; needles=@("wireshark") },
    @{ id="burp"; name="Burp Suite"; required=$false; needles=@("burp suite") },
    @{ id="autopsy"; name="Autopsy"; required=$false; needles=@("autopsy") },
    @{ id="ghidra"; name="Ghidra"; required=$false; needles=@("ghidra") }
  )
  "local-ai"=@(
    @{ id="python"; name="Python"; required=$true; needles=@("python") },
    @{ id="docker"; name="Docker Desktop"; required=$false; needles=@("docker desktop") },
    @{ id="ollama"; name="Ollama"; required=$false; needles=@("ollama") },
    @{ id="cuda-toolkit"; name="NVIDIA CUDA Toolkit"; required=$false; needles=@("cuda toolkit","nvidia cuda") },
    @{ id="vscode"; name="VS Code"; required=$false; needles=@("visual studio code","vs code") }
  )
  "software-development"=@(
    @{ id="git"; name="Git"; required=$true; needles=@("git") },
    @{ id="vscode"; name="VS Code"; required=$true; needles=@("visual studio code","vs code") },
    @{ id="nodejs"; name="Node.js"; required=$false; needles=@("node.js","nodejs") },
    @{ id="python"; name="Python"; required=$false; needles=@("python") },
    @{ id="dotnet"; name=".NET SDK"; required=$false; needles=@(".net sdk","microsoft .net sdk") },
    @{ id="docker"; name="Docker Desktop"; required=$false; needles=@("docker desktop") },
    @{ id="github-cli"; name="GitHub CLI"; required=$false; needles=@("github cli") },
    @{ id="rustup"; name="Rustup"; required=$false; needles=@("rustup") },
    @{ id="go"; name="Go"; required=$false; needles=@("go programming language","golang") }
  )
  "infrastructure"=@(
    @{ id="docker"; name="Docker Desktop"; required=$true; needles=@("docker desktop") },
    @{ id="powershell"; name="PowerShell 7"; required=$false; needles=@("powershell 7","powershell") },
    @{ id="postgresql"; name="PostgreSQL"; required=$false; needles=@("postgresql") },
    @{ id="virtualbox"; name="VirtualBox"; required=$false; needles=@("virtualbox") },
    @{ id="putty"; name="PuTTY"; required=$false; needles=@("putty") },
    @{ id="tableplus"; name="TablePlus"; required=$false; needles=@("tableplus") }
  )
}

$allStatuses=@()
$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")

foreach($cap in @($graph.capabilities)){
  $capId=[string]$cap.id
  if([string]::IsNullOrWhiteSpace($capId)){ $capId=Slug ([string]$cap.name) }

  $requirements=@()
  if($catalog.ContainsKey($capId)){ $requirements=@($catalog[$capId]) }

  $installed=@()
  $missing=@()
  $optional=@()
  $evidence=@()

  foreach($req in $requirements){
    $matches=SoftwareMatches -Inventory $inventory -Needles ([string[]]$req.needles)
    $isInstalled=@($matches).Count -gt 0

    $entry=[pscustomobject]@{
      id=$req.id
      name=$req.name
      required=[bool]$req.required
      installed=$isInstalled
      detected_names=@($matches | Select-Object -First 8 | ForEach-Object { [string]$_.name })
    }

    if($isInstalled){
      $installed += $entry
    } elseif([bool]$req.required){
      $missing += $entry
    } else {
      $optional += $entry
    }

    $evidence += $entry
  }

  $detectedExamples=@()
  if($cap.PSObject.Properties["detected"]){ $detectedExamples=@($cap.detected) }

  $installedCount=@($installed).Count
  $missingCount=@($missing).Count
  $optionalCount=@($optional).Count
  $catalogCount=@($requirements).Count
  $score=[int]($cap.score)

  $status="ready"
  if($missingCount -gt 0){ $status="needs_required_tools" }
  elseif($score -lt 90){ $status="near_ready" }

  $obj=[ordered]@{
    schema="assemblelink.capability_status.v1"
    created_utc=(Get-Date).ToUniversalTime().ToString("o")
    capability_id=$capId
    name=[string]$cap.name
    source_score=$score
    status=$status
    installed_count=$installedCount
    missing_count=$missingCount
    optional_count=$optionalCount
    catalog_count=$catalogCount
    detected_count=$(if($cap.PSObject.Properties["detected_count"]){ [int]$cap.detected_count }else{ @($detectedExamples).Count })
    detected_examples=$detectedExamples
    installed=$installed
    missing=$missing
    optional=$optional
    evidence=$evidence
  }

  $out=Join-Path $StateDir ("capability_status.$capId.v1_$stamp.json")
  $latest=Join-Path $StateDir ("capability_status.$capId.latest.json")
  $pub=Join-Path $PublicState ("capability_status.$capId.latest.json")

  $json=$obj | ConvertTo-Json -Depth 30
  WriteUtf8NoBomLf $out $json
  WriteUtf8NoBomLf $latest $json
  WriteUtf8NoBomLf $pub $json

  $allStatuses += [pscustomobject]@{
    capability_id=$capId
    name=[string]$cap.name
    status=$status
    score=$score
    installed=$installedCount
    missing=$missingCount
    optional=$optionalCount
    path=$latest
  }
}

$index=[ordered]@{
  schema="assemblelink.capability_status_index.v1"
  created_utc=(Get-Date).ToUniversalTime().ToString("o")
  count=@($allStatuses).Count
  capabilities=$allStatuses
}

$idxOut=Join-Path $StateDir ("capability_status_index.v1_$stamp.json")
$idxLatest=Join-Path $StateDir "capability_status_index.latest.json"
$idxPub=Join-Path $PublicState "capability_status_index.latest.json"

$idxJson=$index | ConvertTo-Json -Depth 30
WriteUtf8NoBomLf $idxOut $idxJson
WriteUtf8NoBomLf $idxLatest $idxJson
WriteUtf8NoBomLf $idxPub $idxJson

$rcp=Join-Path $ReceiptDir ("assemblelink.capability_status_receipt.v1_$stamp.txt")
WriteUtf8NoBomLf $rcp ("schema=assemblelink.capability_status_receipt.v1`nutc="+(Get-Date).ToUniversalTime().ToString("o")+"`nindex=$idxOut`ncount="+@($allStatuses).Count+"`n")

$allStatuses | Sort-Object name | Format-Table name,status,score,installed,missing,optional -AutoSize

Write-Host ("ASSEMBLELINK_CAPABILITY_STATUS_INDEX: "+$idxOut) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_CAPABILITY_STATUS_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_CAPABILITY_STATUS_OK" -ForegroundColor Green
