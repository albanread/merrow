[CmdletBinding()]
param(
    [switch]$SkipVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if (-not (Test-Path -LiteralPath $cargoBin -PathType Container)) {
    throw "Rust cargo bin directory was not found: $cargoBin"
}

$currentPathEntries = @($env:Path -split ';' | Where-Object { $_ -ne '' })
if ($currentPathEntries -notcontains $cargoBin) {
    $env:Path = "$cargoBin;$env:Path"
}

Write-Host "Added Rust tools to PATH from: $cargoBin"

if (-not $SkipVerification) {
    $rustc = Get-Command rustc -ErrorAction SilentlyContinue
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue

    if (-not $rustc) {
        throw 'Rust PATH was updated, but rustc.exe is still not available.'
    }
    if (-not $cargo) {
        throw 'Rust PATH was updated, but cargo.exe is still not available.'
    }

    Write-Host "rustc.exe: $($rustc.Source)"
    & $rustc.Source --version
    Write-Host "cargo.exe: $($cargo.Source)"
    & $cargo.Source --version
}
