param([string]$RepoRoot='C:\dev\assemblelink',[string]$FixturePath='')

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
function Sha([string]$Path){$stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}}
function Gb([double]$bytes){
  return [math]::Round(($bytes / 1GB),2)
}
function SafeProp([object]$o,[string]$name){
  if($null -eq $o){ return "" }
  $p=$o.PSObject.Properties[$name]
  if($null -eq $p){ return "" }
  if($null -eq $p.Value){ return "" }
  return $p.Value
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$errors=@()
function SafeCim([string]$Class,[string]$Filter=''){try{if($Filter){@(Get-CimInstance $Class -Filter $Filter -ErrorAction Stop)}else{@(Get-CimInstance $Class -ErrorAction Stop)}}catch{$script:errors+=([ordered]@{source=$Class;status='unavailable'});@()}}
if($FixturePath){if(-not(Test-Path -LiteralPath $FixturePath -PathType Leaf)){throw 'SYSTEM_PROFILE_FIXTURE_MISSING'};$fixture=Get-Content -LiteralPath $FixturePath -Raw|ConvertFrom-Json;$cs=$fixture.computer_system;$os=$fixture.operating_system;$cpu=$fixture.cpu;$gpuRows=@($fixture.graphics);$diskRows=@($fixture.disks)}else{$cs=@(SafeCim 'Win32_ComputerSystem')|Select-Object -First 1;$os=@(SafeCim 'Win32_OperatingSystem')|Select-Object -First 1;$cpu=@(SafeCim 'Win32_Processor')|Select-Object -First 1;$gpuRows=@(SafeCim 'Win32_VideoController'|Select-Object -First 16);$diskRows=@(SafeCim 'Win32_LogicalDisk' 'DriveType=3'|Sort-Object DeviceID|Select-Object -First 64)}
$gpus=@($gpuRows | ForEach-Object {
  $gpuName=[string](SafeProp $_ "Name")
  $rawAdapterRam=$(if((SafeProp $_ "AdapterRAM") -ne ""){[double](SafeProp $_ "AdapterRAM")}else{0});$wmiLimited=$rawAdapterRam-ge(3.9GB);$wmiRam=$(if($wmiLimited){0}else{Gb $rawAdapterRam})

  [pscustomobject]@{
    name=$gpuName
    driver_version=[string](SafeProp $_ "DriverVersion")
    vram_gb=$wmiRam
    vram_source=$(if($wmiLimited){"wmi_32bit_limit"}else{"wmi_adapter_ram"})
    vram_confidence=$(if($wmiLimited){"unknown"}else{"low"})
    wmi_vram_gb=$(if($rawAdapterRam){Gb $rawAdapterRam}else{0})
  }
})
$drives=@($diskRows | Sort-Object DeviceID | ForEach-Object {
  [pscustomobject]@{
    drive=[string]$_.DeviceID
    label=[string](SafeProp $_ "VolumeName")
    filesystem=[string](SafeProp $_ "FileSystem")
    total_gb=Gb ([double]$_.Size)
    free_gb=Gb ([double]$_.FreeSpace)
    used_gb=Gb (([double]$_.Size)-([double]$_.FreeSpace))
    free_percent=$(if([double]$_.Size -gt 0){ [math]::Round((([double]$_.FreeSpace/[double]$_.Size)*100),1) }else{ 0 })
  }
})

$totalStorage=0.0
$freeStorage=0.0
foreach($d in $drives){
  $totalStorage += [double]$d.total_gb
  $freeStorage += [double]$d.free_gb
}

$runId=[guid]::NewGuid().ToString('n');$observed=(Get-Date).ToUniversalTime()
$profile=[ordered]@{
  schema="assemblelink.system_profile.v2"
  run_id=$runId
  observed_utc=$observed.ToString("o")
  observation_status=$(if($errors.Count){'partial'}else{'complete'})
  machine=[ordered]@{
    name=[string]$env:COMPUTERNAME
    manufacturer=[string](SafeProp $cs "Manufacturer")
    model=[string](SafeProp $cs "Model")
  }
  os=[ordered]@{
    caption=[string](SafeProp $os "Caption")
    version=[string](SafeProp $os "Version")
    build=[string](SafeProp $os "BuildNumber")
    architecture=[string](SafeProp $os "OSArchitecture")
  }
  cpu=[ordered]@{
    name=[string](SafeProp $cpu "Name")
    cores=[int](SafeProp $cpu "NumberOfCores")
    logical_processors=[int](SafeProp $cpu "NumberOfLogicalProcessors")
    max_clock_mhz=[int](SafeProp $cpu "MaxClockSpeed")
  }
  memory=[ordered]@{
    total_gb=Gb ([double](SafeProp $cs "TotalPhysicalMemory"))
    free_gb=Gb ([double](SafeProp $os "FreePhysicalMemory") * 1KB)
  }
  gpu=$gpus
  storage=[ordered]@{
    total_gb=[math]::Round($totalStorage,2)
    free_gb=[math]::Round($freeStorage,2)
    drives=$drives
  }
  collection_errors=$errors
}

$stamp=$observed.ToString("yyyyMMdd_HHmmss_fffffff")
$out=Join-Path $StateDir ("system_profile."+$stamp+"."+$runId+".json")
$latest=Join-Path $StateDir "system_profile.latest.json"

WriteUtf8 $out ($profile|ConvertTo-Json -Depth 20)
WriteUtf8 $latest ($profile|ConvertTo-Json -Depth 20)
WriteUtf8 ($out+'.sha256') ((Sha $out)+'  '+[IO.Path]::GetFileName($out))
WriteUtf8 ($latest+'.sha256') ((Sha $latest)+'  '+[IO.Path]::GetFileName($latest))

$rcp=Join-Path $ReceiptDir ("assemblelink.system_profile_receipt."+$stamp+"."+$runId+".json")
WriteUtf8 $rcp (([ordered]@{schema='assemblelink.system_profile_receipt.v2';run_id=$runId;observed_utc=$profile.observed_utc;state=[IO.Path]::GetFileName($out);state_sha256=Sha $out;observation_status=$profile.observation_status}|ConvertTo-Json -Depth 5))
WriteUtf8 ($rcp+'.sha256') ((Sha $rcp)+'  '+[IO.Path]::GetFileName($rcp))

Write-Host ("CPU: "+$profile.cpu.name)
Write-Host ("RAM GB: "+$profile.memory.total_gb)
Write-Host ("STORAGE FREE GB: "+$profile.storage.free_gb+" / "+$profile.storage.total_gb)
foreach($g in @($profile.gpu)){ Write-Host ("GPU: "+$g.name+" VRAM_GB="+$g.vram_gb+" SOURCE="+$g.vram_source+" CONFIDENCE="+$g.vram_confidence) }
$drives | Format-Table -AutoSize | Out-Host

Write-Host ("ASSEMBLELINK_SYSTEM_PROFILE_STATE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_SYSTEM_PROFILE_RECEIPT: "+$rcp) -ForegroundColor DarkGray
Write-Host "ASSEMBLELINK_SYSTEM_PROFILE_OK" -ForegroundColor Green
Write-Output $out
