[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$studioExe = Join-Path $repoRoot 'zig-out\bin\merrow-studio.exe'

if (-not (Test-Path -LiteralPath $studioExe -PathType Leaf)) {
    throw "Studio executable not found at $studioExe. Run .\scripts\build_windows_cli.ps1 first."
}

Push-Location (Split-Path -Parent $studioExe)
try {
    & $studioExe @AppArgs
} finally {
    Pop-Location
}