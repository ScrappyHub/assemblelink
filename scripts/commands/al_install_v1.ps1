param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TargetClass,
  [switch]$Apply
)
$ErrorActionPreference='Stop'
throw 'LEGACY_INSTALL_DISABLED: Use the AssembleLink desktop Setup Center. Installation requires an approved catalog identity, content-hashed plan, explicit approval, fixed argument vector, and sealed receipt.'
