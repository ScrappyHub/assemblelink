param(
  [string]$RepoRoot="C:\dev\assemblelink",
  [Parameter(Mandatory=$true)][string]$CapabilityId,
  [switch]$Execute
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$StateDir=Join-Path $RepoRoot "state"
$ReceiptDir=Join-Path $RepoRoot "proofs\receipts"
$QueuePath=Join-Path $StateDir ("install_queue.$CapabilityId.latest.json")
$ProgressPath=Join-Path $StateDir ("install_queue_execution.$CapabilityId.progress.json")

function EnsureDir($p){
  if(-not(Test-Path $p -PathType Container)){
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

function SaveProgress($obj){
  WriteUtf8 $ProgressPath ($obj | ConvertTo-Json -Depth 30)
}

function Classify-WingetResult {
  param(
    [int]$ExitCode,
    [string]$Stdout,
    [string]$Stderr
  )

  $text=(($Stdout+"`n"+$Stderr) -replace "`r","").ToLowerInvariant()

  if($ExitCode -eq 0){
    if($text -match "successfully installed" -or $text -match "successfully upgraded"){
      return [pscustomobject]@{ status="installed_or_updated"; message="winget completed successfully"; action_required=$false }
    }
    return [pscustomobject]@{ status="installed_or_already_present"; message="winget completed successfully"; action_required=$false }
  }

  if($text -match "no available upgrade found" -or $text -match "no newer package versions are available"){
    return [pscustomobject]@{ status="already_current"; message="Installed package is already current"; action_required=$false }
  }

  if($text -match "files modified by the installer are currently in use" -or $text -match "currently in use by a different application"){
    return [pscustomobject]@{ status="blocked_file_lock"; message="Installer reported files in use. Close related apps/background hooks or reboot, then retry"; action_required=$true }
  }

  if($text -match "requires elevation" -or $text -match "administrator" -or $text -match "admin"){
    return [pscustomobject]@{ status="requires_admin"; message="Administrator approval required"; action_required=$true }
  }

  if($text -match "reboot" -or $text -match "restart"){
    return [pscustomobject]@{ status="requires_reboot"; message="Restart required"; action_required=$true }
  }

  if($text -match "hash" -and $text -match "failed"){
    return [pscustomobject]@{ status="hash_verification_failed"; message="Installer hash verification failed"; action_required=$true }
  }

  return [pscustomobject]@{ status="install_failed"; message=("winget exited with code "+$ExitCode); action_required=$true }
}

function Invoke-CommandCapture {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentList
  )

  $tmpOut=Join-Path $env:TEMP ("assemblelink_winget_out_"+[guid]::NewGuid().ToString("N")+".txt")
  $tmpErr=Join-Path $env:TEMP ("assemblelink_winget_err_"+[guid]::NewGuid().ToString("N")+".txt")

  $sw=[Diagnostics.Stopwatch]::StartNew()
  $p=Start-Process `
    -FilePath $FilePath `
    -ArgumentList $ArgumentList `
    -Wait `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput $tmpOut `
    -RedirectStandardError $tmpErr
  $sw.Stop()

  $stdout=""
  $stderr=""
  if(Test-Path $tmpOut){ $stdout=Get-Content $tmpOut -Raw -Encoding UTF8; Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue }
  if(Test-Path $tmpErr){ $stderr=Get-Content $tmpErr -Raw -Encoding UTF8; Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue }

  return [pscustomobject]@{
    exit_code=$p.ExitCode
    duration_seconds=[math]::Round($sw.Elapsed.TotalSeconds,2)
    stdout_tail=($stdout -split "`n" | Select-Object -Last 20) -join "`n"
    stderr_tail=($stderr -split "`n" | Select-Object -Last 20) -join "`n"
  }
}

if(-not(Test-Path $QueuePath -PathType Leaf)){
  throw "INSTALL_QUEUE_MISSING: $QueuePath"
}

$queueObj=Get-Content $QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
$queue=@($queueObj.queue)

$runId=[guid]::NewGuid().ToString("N")
$started=(Get-Date).ToUniversalTime()
$results=@()

$progress=[ordered]@{
  schema="assemblelink.install_queue_execution.progress.v1"
  run_id=$runId
  capability_id=$CapabilityId
  started_utc=$started.ToString("o")
  updated_utc=$started.ToString("o")
  executed=[bool]$Execute
  status=$(if($Execute){"running"}else{"dry_run"})
  total=$queue.Count
  completed=0
  current=""
  results=@()
}
SaveProgress $progress

for($idx=0; $idx -lt $queue.Count; $idx++){
  $item=$queue[$idx]
  $name=[string]$item.name
  $mode=[string]$item.install_mode
  $cmd=[string]$item.install_command

  $progress.current=$name
  $progress.updated_utc=(Get-Date).ToUniversalTime().ToString("o")
  SaveProgress $progress

  $status="skipped"
  $exitCode=$null
  $message=""
  $duration=0
  $stdoutTail=""
  $stderrTail=""

  if($mode -ne "winget" -or [string]::IsNullOrWhiteSpace($cmd)){
    $status="manual_review_required"
    $message="No automatic install command."
  } elseif(-not $Execute){
    $status="dry_run"
    $message="Would run: $cmd"
  } else {
    Write-Host ("["+($idx+1)+"/"+$queue.Count+"] Installing: "+$name) -ForegroundColor Cyan

    $wingetArgs=@(
      "install",
      "--id", [string]$item.winget_id,
      "--exact",
      "--accept-package-agreements",
      "--accept-source-agreements"
    )

    $r=Invoke-CommandCapture -FilePath "winget.exe" -ArgumentList $wingetArgs
    $exitCode=$r.exit_code
    $duration=$r.duration_seconds
    $stdoutTail=$r.stdout_tail
    $stderrTail=$r.stderr_tail

    $classification=Classify-WingetResult -ExitCode $exitCode -Stdout $stdoutTail -Stderr $stderrTail
    $status=$classification.status
    $message=$classification.message
  }

  $result=[pscustomobject]@{
    name=$name
    mode=$mode
    winget_id=[string]$item.winget_id
    command=$cmd
    status=$status
    exit_code=$exitCode
    duration_seconds=$duration
    message=$message
    installer_hash_verified=$(if((($stdoutTail+"`n"+$stderrTail).ToLowerInvariant()) -match "successfully verified installer hash"){ $true }else{ $false })
    action_required=$(if($status -in @("blocked_app_running","blocked_file_lock","requires_admin","requires_reboot","hash_verification_failed","install_failed")){ $true }else{ $false })
    stdout_tail=$stdoutTail
    stderr_tail=$stderrTail
  }

  $results += $result

  $progress.completed=$idx+1
  $progress.updated_utc=(Get-Date).ToUniversalTime().ToString("o")
  $progress.results=@($results)
  SaveProgress $progress
}

$ended=(Get-Date).ToUniversalTime()
$totalSeconds=[math]::Round(($ended-$started).TotalSeconds,2)

$outObj=[ordered]@{
  schema="assemblelink.install_queue_execution.v1"
  run_id=$runId
  created_utc=$ended.ToString("o")
  capability_id=$CapabilityId
  executed=[bool]$Execute
  queue_count=$queue.Count
  duration_seconds=$totalSeconds
  results=$results
}

EnsureDir $StateDir
EnsureDir $ReceiptDir

$stamp=$ended.ToString("yyyyMMdd_HHmmss")
$out=Join-Path $StateDir ("install_queue_execution.$CapabilityId.v1_$stamp.json")
$latest=Join-Path $StateDir ("install_queue_execution.$CapabilityId.latest.json")

WriteUtf8 $out ($outObj|ConvertTo-Json -Depth 30)
WriteUtf8 $latest ($outObj|ConvertTo-Json -Depth 30)

$progress.status="complete"
$progress.current=""
$progress.updated_utc=$ended.ToString("o")
$progress.duration_seconds=$totalSeconds
SaveProgress $progress

$rcp=Join-Path $ReceiptDir ("assemblelink.install_queue_execution_receipt.v1_$stamp.txt")
WriteUtf8 $rcp ("schema=assemblelink.install_queue_execution_receipt.v1`nrun_id=$runId`nutc="+$ended.ToString("o")+"`ncapability_id=$CapabilityId`nexecuted="+[bool]$Execute+"`nduration_seconds=$totalSeconds`nstate=$out`n")

$results | Format-Table name,status,exit_code,duration_seconds,message -AutoSize

Write-Host ("ASSEMBLELINK_INSTALL_QUEUE_EXECUTION_STATE: "+$out) -ForegroundColor Green
Write-Host ("ASSEMBLELINK_INSTALL_QUEUE_EXECUTION_SECONDS: "+$totalSeconds) -ForegroundColor Green
if($Execute){
  Write-Host "ASSEMBLELINK_INSTALL_QUEUE_EXECUTE_OK" -ForegroundColor Green
}else{
  Write-Host "ASSEMBLELINK_INSTALL_QUEUE_DRY_RUN_OK" -ForegroundColor Green
}
