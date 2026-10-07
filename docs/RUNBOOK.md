# AssembleLink Runbook

## Start desktop dev app

    powershell -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\run_desktop_dev_v1.ps1

## Run system profile

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\commands\al_system_profile_v1.ps1 -RepoRoot C:\dev\assemblelink

## Run workstation health

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\engine\al_workstation_health_v1.ps1 -RepoRoot C:\dev\assemblelink

## Generate install queue

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\engine\al_install_queue_v1.ps1 -RepoRoot C:\dev\assemblelink -CapabilityId content-creation

## Dry-run install queue

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\engine\al_install_queue_execute_v1.ps1 -RepoRoot C:\dev\assemblelink -CapabilityId content-creation

## Execute install queue

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\dev\assemblelink\scripts\engine\al_install_queue_execute_v1.ps1 -RepoRoot C:\dev\assemblelink -CapabilityId content-creation -Execute
