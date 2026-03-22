<#
.SYNOPSIS
    Build the wordcomglue DLL and smoke test using MSVC.
.DESCRIPTION
    Compiles wordcomglue C++ sources into a portable DLL (wordcomglue.dll)
    with an import library and links the smoke test executable against it.
    Output goes to wordcomglue\build\.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [switch]$NoBuild,
    [switch]$NoTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $projectRoot) { $projectRoot = (Get-Location).Path }
$wcgRoot = Join-Path $PSScriptRoot '..\wordcomglue' | Resolve-Path

# Ensure MSVC environment is loaded
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Host 'Loading MSVC environment...'
    . (Join-Path $PSScriptRoot 'enable_msvc.ps1')
}

$buildDir = Join-Path $wcgRoot 'build'
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

# Compiler flags
$commonFlags = @(
    '/nologo',
    '/std:c++17',
    '/EHsc',
    '/W4',
    '/DWIN32_LEAN_AND_MEAN',
    '/DUNICODE',
    '/D_UNICODE',
    "/I`"$wcgRoot`""
)

if ($Configuration -eq 'Debug') {
    $commonFlags += @('/Od', '/Zi', '/MTd', '/DDEBUG', '/D_DEBUG')
} else {
    $commonFlags += @('/O2', '/MT', '/DNDEBUG')
}

$sources = @(
    (Join-Path $wcgRoot 'src\library.cpp'),
    (Join-Path $wcgRoot 'src\session.cpp'),
    (Join-Path $wcgRoot 'src\document.cpp')
)

$linkLibs = @('ole32.lib', 'oleaut32.lib', 'uuid.lib')
$defFile = Join-Path $wcgRoot 'wordcomglue.def'

Write-Host "Configuration : $Configuration"
Write-Host "Output        : $buildDir"
Write-Host ''

# --- Compile object files ---
$objFiles = @()
foreach ($src in $sources) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $obj  = Join-Path $buildDir "$name.obj"
    $objFiles += $obj

    Write-Host "  Compiling $name.cpp ..."
    $compileArgs = $commonFlags + @('/c', "/Fo`"$obj`"", "`"$src`"")
    if ($Configuration -eq 'Debug') {
        $compileArgs += "/Fd`"$(Join-Path $buildDir 'wordcomglue.pdb')`""
    }
    & cl @compileArgs
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed for $name.cpp" }
}

# --- Create DLL and import library ---
$dllFile = Join-Path $buildDir 'wordcomglue.dll'
$importLibFile = Join-Path $buildDir 'wordcomglue_import.lib'
Write-Host "  Linking wordcomglue.dll ..."
& link /nologo /dll "/OUT:`"$dllFile`"" "/IMPLIB:`"$importLibFile`"" "/DEF:`"$defFile`"" @objFiles @linkLibs
if ($LASTEXITCODE -ne 0) { throw 'link.exe failed' }

Write-Host ''
Write-Host "DLL built    : $dllFile"
Write-Host "Import lib   : $importLibFile"

# --- Build smoke test ---
if (-not $NoTest) {
    $testSrc = Join-Path $wcgRoot 'tests\smoke_test.cpp'
    $testExe = Join-Path $buildDir 'wcg_smoke_test.exe'

    Write-Host ''
    Write-Host '  Compiling smoke_test.cpp ...'
    $testArgs = $commonFlags + @(
        "/Fe`"$testExe`"",
        "`"$testSrc`""
    )

    if ($Configuration -eq 'Debug') {
        $testArgs += "/Fd`"$(Join-Path $buildDir 'smoke_test.pdb')`""
    }

    $testArgs += @(
        "/link",
        "`"$importLibFile`""
    ) + $linkLibs

    & cl @testArgs
    if ($LASTEXITCODE -ne 0) { throw 'Smoke test compilation failed' }

    Write-Host "Smoke test built: $testExe"
}

Write-Host ''
Write-Host 'Build complete.'
