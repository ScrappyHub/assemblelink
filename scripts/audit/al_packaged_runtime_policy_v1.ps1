param([string]$RepoRoot='C:\dev\assemblelink')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$config=Get-Content (Join-Path $RepoRoot 'ui\src-tauri\tauri.conf.json') -Raw|ConvertFrom-Json
if($config.bundle.PSObject.Properties.Name-contains'resources'){throw 'BULK_RUNTIME_RESOURCES_FORBIDDEN'}
$rust=Get-Content (Join-Path $RepoRoot 'ui\src-tauri\src\main.rs') -Raw
if($rust-match'copy_tree|engine/scripts|engine/manifests'){throw 'BULK_RUNTIME_COPY_FORBIDDEN'}
foreach($control in @('reset_trusted_runtime','remove_dir_all','TRUSTED_RESET_FAILED')){if($rust-notmatch$control){throw "TRUSTED_RUNTIME_RECONCILIATION_MISSING: $control"}}
$trusted=[regex]::Matches($rust,'(?s)\(\s*"([^"]+)"\s*,\s*include_bytes!')|ForEach-Object{$_.Groups[1].Value}
if(-not$trusted-or@($trusted|Where-Object{$_-notmatch'^(catalog|scripts)/(engine|commands|)[A-Za-z0-9_./-]+$'}).Count){throw 'TRUSTED_RUNTIME_ALLOWLIST_INVALID'}
foreach($relative in $trusted){$source=Get-Content (Join-Path $RepoRoot $relative.Replace('/','\')) -Raw;if($source-match'(?i)Invoke-Expression|cmd\.exe\s+/c|install_command'){throw "PACKAGED_COMMAND_EXECUTION_FORBIDDEN: $relative"}}
Write-Host "ASSEMBLELINK_PACKAGED_RUNTIME_POLICY_OK: $($trusted.Count) allowlisted files" -ForegroundColor Green
