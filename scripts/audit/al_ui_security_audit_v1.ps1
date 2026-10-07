param([string]$RepoRoot="C:\dev\assemblelink")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$src=Join-Path $RepoRoot "ui\src"
$conf=Join-Path $RepoRoot "ui\src-tauri\tauri.conf.json"
$rs=Join-Path $RepoRoot "ui\src-tauri\src\main.rs"
foreach($p in @($src,$conf,$rs)){ if(-not(Test-Path -LiteralPath $p)){ throw ("UI_SECURITY_FILE_MISSING: "+$p) } }

$js=Get-ChildItem -LiteralPath $src -Filter "*.js" -File
$bad=@()
foreach($f in $js){
  $t=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
  if($t -match '\beval\s*\(' -or $t -match 'new Function\s*\(' -or $t -match 'document\.write\s*\('){ $bad += ($f.Name+": dynamic code execution") }
  if($t -match '\son[a-z]+\s*=\s*["'']'){ $bad += ($f.Name+": inline event handler") }
  if($t -match 'fetch\(\s*["'']https?:'){ $bad += ($f.Name+": external fetch") }
  if($t -match 'XMLHttpRequest|WebSocket|sendBeacon'){ $bad += ($f.Name+": raw network API") }
}
if($bad.Count -gt 0){ throw ("UI_SECURITY_CHECK_FAIL: "+($bad -join "; ")) }

$confText=Get-Content -LiteralPath $conf -Raw -Encoding UTF8
if($confText -match 'unsafe-eval'){ throw "UI_SECURITY_CHECK_FAIL: CSP allows unsafe-eval" }
if($confText -notmatch "default-src 'self'"){ throw "UI_SECURITY_CHECK_FAIL: CSP default-src is not self" }

$main=Get-Content -LiteralPath (Join-Path $src "main.js") -Raw -Encoding UTF8
$rust=Get-Content -LiteralPath $rs -Raw -Encoding UTF8
$checks=@(
  [pscustomobject]@{ item="uninstall program requires approved:true"; ok=($main -match 'invokeDesktop\("uninstall_software",\{catalogId,approved:true\}\)' -and $rust -match 'UNINSTALL_REQUIRES_EXPLICIT_APPROVAL') },
  [pscustomobject]@{ item="self uninstall requires approved:true"; ok=($main -match 'invokeDesktop\("uninstall_assemblelink",\{approved:true\}\)') },
  [pscustomobject]@{ item="uninstall limited to catalog entries"; ok=($rust -match 'UNINSTALL_TARGET_NOT_IN_CATALOG' -and $rust -match 'fn valid_winget_id') },
  [pscustomobject]@{ item="self uninstall path rejects cmd metacharacters"; ok=($rust -match 'fn safe_cmd_path' -and $rust -match 'UNINSTALLER_PATH_REJECTED') },
  [pscustomobject]@{ item="install history is size capped and name strict"; ok=($rust -match 'MAX_HISTORY_FILE_BYTES' -and $rust -match 'fn is_execution_record_name') },
  [pscustomobject]@{ item="HTML escaping helper present"; ok=($main -match 'const escapeHtml') }
)
foreach($c in $checks){ if(-not $c.ok){ throw ("UI_SECURITY_CHECK_FAIL: "+$c.item) } }
$checks | Format-Table item,ok -AutoSize
Write-Host "ASSEMBLELINK_UI_SECURITY_AUDIT_OK" -ForegroundColor Green
