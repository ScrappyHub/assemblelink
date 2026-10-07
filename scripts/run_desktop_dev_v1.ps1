$ErrorActionPreference="Stop"

$Rc = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter rc.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "\\x64\\rc\.exe$" } |
  Sort-Object FullName -Descending |
  Select-Object -First 1

if(-not $Rc){
  throw "RC_EXE_NOT_FOUND_INSTALL_WINDOWS_SDK"
}

$env:PATH = (Split-Path $Rc.FullName -Parent) + ";" + $env:PATH

Set-Location "C:\dev\assemblelink\ui"
npm run desktop
